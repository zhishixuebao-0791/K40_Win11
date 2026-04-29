# Alioth DSDT Audio Target Report

Generated: 2026-04-24 17:51:29
Raw ACPI root: `D:\Code\REDMIK40_Win11\RawAcpiTables_20260423_161309`
DSDT binary: `D:\Code\REDMIK40_Win11\RawAcpiTables_20260423_161309\DSDT\QCOMM_\SDM8250_\00000003\00000000.bin`
Decompiled DSL: `C:\yjc_code\K40_Win11\Alioth-Engineering\analysis\dsdt-audio-current\DSDT.dsl`
Context dump: `C:\yjc_code\K40_Win11\Alioth-Engineering\analysis\dsdt-audio-current\audio-target-context.txt`

## Result

The current Mu-alioth DSDT does expose an audio topology to Windows. The important devices are not broadly hidden by _STA; the main mismatch is that this DSDT exposes Qualcomm audio child IDs in the 05xx family while the local Kona Windows audio INFs mostly match 25xx IDs.

Because the devices are present in DSDT and ADSP._STA returns 0x0F, the next low-risk direction is a narrow INF alias experiment. Do not pivot to Mu-Silicium ACPI edits yet, and do not broad-inject Kona/SOC/USBFn packages.

## Target Table

| Target | DSDT evidence | _STA result | _DEP / dependency | Driver gap |
| --- | --- | --- | --- | --- |
| AUDS | Device(AUDS), _HID QCOM05D2, _UID 0 | No _STA in device block; default is present/enabled if parent is active | No _DEP | Kona AudioService INF expects ACPI\QCOM25D2 |
| ADSP | Device(ADSP), _HID QCOM051D | _STA returns 0x0F | _DEP: PEP0, PILC, GLNK, IPC0, RPEN, SSDD, ARPC | Not hidden; dependent children use 05xx IDs |
| SLM1 | Device(SLM1) under ADSP | No _STA in device block | No _DEP; has _CRS | Kona ADCM INF expects SLM1\QCOM2524; no explicit QCOM0524 observed in DSDT |
| ADCM | Device(ADCM), CHLD returns ADCM\QCOM0525 | No _STA in device block | _DEP: MMU0, IMM0 | Kona qcauddev INF expects ADCM\QCOM2525 |
| AUDD | Device(AUDD), CHLD returns AUDD\QCOM0537 and AUDD\QCOM052C | No _STA in device block | No _DEP; has SPI4 _CRS | Kona miniport/MBHC INFs expect AUDD\QCOM252C and AUDD\QCOM2537 |
| ARPC | Device(ARPC), _HID QCOM0560 | No _STA in device block | _DEP: MMU0, GLNK, SCM0 | Kona ADSPRPC INF expects ACPI\QCOM2560 |
| ARPD | Device(ARPD), _HID QCOM058A | No _STA in device block | _DEP: ADSP, ARPC | Kona ADSPRPCD INF expects ACPI\QCOM258A |
| CFSA | Device(CFSA), _HID FSA04480 | No _STA in device block | No _DEP; _CRS references I2C5 | ID matches FSA4480 driver; prior runtime issue is dependency/I2C stack, not ID alias |

## Narrow Alias Candidates

| DSDT/runtime ID | Candidate source INF | Existing INF match | Experiment action |
| --- | --- | --- | --- |
| ACPI\QCOM05D2 | Drivers\Audio\Orientation\AudioService8250.inf | ACPI\QCOM25D2 | Add alias only in copied INF package |
| ACPI\QCOM0560 | Drivers\Audio\RPC\ADSPRPC\qcadsprpc8250.inf | ACPI\QCOM2560 | Add alias only in copied INF package |
| ACPI\QCOM058A | Drivers\Audio\RPC\ADSPRPCD\qcadsprpcd8250.inf | ACPI\QCOM258A | Add alias only in copied INF package |
| ADCM\QCOM0525 | Drivers\Audio\Device\qcauddev8250.inf / Extensions\Audio\Device\qcauddev_ext8250.inf | ADCM\QCOM2525 | Add alias only after RPC/AudioService test |
| AUDD\QCOM052C | Drivers\Audio\AudMiniport\qcaudminiport_Base8250.inf | AUDD\QCOM252C | Add alias only after ADCM appears stable |
| AUDD\QCOM0537 | Drivers\Audio\Device\qcauddev8250.inf | AUDD\QCOM2537 | Add alias only after ADCM appears stable |
| ACPI\FSA04480 | windows_qcom_platforms\components\ANYSOC\Hardware\HARDWARE.USB.FSA4480\fsa4480.inf | ACPI\FSA04480 | No alias needed; debug I2C5/dependency instead |

## Decision

Proceed with an extremely narrow INF alias package, staged and reversible. First pass should cover only ACPI\QCOM05D2, ACPI\QCOM0560, and ACPI\QCOM058A. Do not touch SOC, USBFn, PMIC, PCIe, storage, or broad Qualcomm class packages.

If the alias pass produces new ADCM/AUDD devices without boot regression, then test ADCM\QCOM0525, AUDD\QCOM052C, and AUDD\QCOM0537 in a second pass. If these nodes fail because _DEP objects are unavailable or drivers cannot start despite ID match, then pivot to Mu-Silicium aliothPkg/ACPI work.
