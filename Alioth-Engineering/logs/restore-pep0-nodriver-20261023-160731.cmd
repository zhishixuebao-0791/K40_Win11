@echo off
reg.exe delete "HKLM\ALIOTH_P19A_RS_18772\ControlSet001\Enum\ACPI\QCOM0519\2&daba3ff&0" /v Service /f
reg.exe delete "HKLM\ALIOTH_P19A_RS_18772\ControlSet001\Enum\ACPI\QCOM0519\2&daba3ff&0" /v Driver /f
reg.exe delete "HKLM\ALIOTH_P19A_RS_18772\ControlSet001\Enum\ACPI\QCOM0519\2&daba3ff&0" /v ClassGUID /f
reg.exe delete "HKLM\ALIOTH_P19A_RS_18772\ControlSet001\Enum\ACPI\QCOM0519\2&daba3ff&0" /v Class /f
reg.exe add "HKLM\ALIOTH_P19A_RS_18772\ControlSet001\Enum\ACPI\QCOM0519\2&daba3ff&0" /v ConfigFlags /t REG_DWORD /d 0 /f
reg.exe delete "HKLM\ALIOTH_P19A_RS_18772\ControlSet001\Control\Class\{4d36e97d-e325-11ce-bfc1-08002be10318}\0039" /f
reg.exe add "HKLM\ALIOTH_P19A_RS_18772\ControlSet001\Services\pep0stub" /v Start /t REG_DWORD /d 4 /f
echo done
