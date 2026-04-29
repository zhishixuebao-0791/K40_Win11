@echo off
setlocal

rem Template only. Do not use as-is until the alioth manifests and components
rem are fully populated.

if not exist "..\definitions\Desktop\ARM64\Internal\alioth.xml" (
    echo Missing definitions\Desktop\ARM64\Internal\alioth.xml
    echo Copy alioth.template.xml to alioth.xml after you replace the TODOs.
    exit /b 1
)

if not exist "..\definitions\Desktop\ARM64\PE\alioth.xml" (
    echo Missing definitions\Desktop\ARM64\PE\alioth.xml
    echo Copy alioth.template.xml to alioth.xml after you replace the TODOs.
    exit /b 1
)

if not exist "..\components\QC8250" (
    echo Missing components\QC8250
    exit /b 1
)

if not exist "..\components\Devices\Alioth" (
    echo Missing components\Devices\Alioth
    exit /b 1
)

echo This is a template pack script.
echo Next expected edits:
echo 1. Create OnlineUpdater.cmd and OfflineUpdater.cmd for alioth.
echo 2. Point both to definitions\Desktop\ARM64\Internal\alioth.xml
echo 3. Add the final file list.
echo 4. Package with 7z or Bandizip.
echo.
echo Reference:
echo .\..\sound_code\windows_xiaomi_platforms_sparse\tools\pack-vayu.cmd

endlocal
