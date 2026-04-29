@echo off
setlocal

set "FASTBOOT=C:\jcy_software\Android\sdk\commandlinetools-win-14742923_latest\platform-tools\fastboot.exe"
set "UEFI_IMG=C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1.img"

if not exist "%FASTBOOT%" (
    echo fastboot not found: %FASTBOOT%
    exit /b 1
)

if not exist "%UEFI_IMG%" (
    echo UEFI image not found: %UEFI_IMG%
    exit /b 1
)

echo Booting alioth UEFI through fastboot...
"%FASTBOOT%" boot "%UEFI_IMG%"
