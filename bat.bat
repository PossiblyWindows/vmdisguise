@echo off
title VM Spoofer - No Stop on Errors
setlocal enabledelayedexpansion

:: Admin check (optional – if fails, continue anyway)
net session >nul 2>&1
if %errorlevel% neq 0 echo [!] Not running as admin, some changes may fail.

echo ============================================================
echo Advanced VM Spoofing - Errors will be ignored
echo ============================================================
echo.

:: 1. Disable Hyper-V (ignore errors)
bcdedit /set hypervisorlaunchtype off >nul 2>&1
bcdedit /set nx AlwaysOn >nul 2>&1

:: 2. Remove VM drivers (services)
set DRV_LIST="vmx86 vmci vmhgfs vmmouse vmusb vmx_sata VBoxGuest VBoxMouse VBoxSF VBoxVideo vmbus vmic vhdmp"
for %%d in (%DRV_LIST%) do (
    sc stop %%d >nul 2>&1
    sc delete %%d >nul 2>&1
)

:: 3. Delete VM driver files (if any)
if exist "C:\Windows\System32\drivers\vm*.sys" (
    for %%f in ("C:\Windows\System32\drivers\vm*.sys") do (
        takeown /f "%%f" >nul 2>&1
        icacls "%%f" /grant administrators:F >nul 2>&1
        del /f "%%f" >nul 2>&1
    )
)
if exist "C:\Windows\System32\drivers\VBox*.sys" (
    for %%f in ("C:\Windows\System32\drivers\VBox*.sys") do (
        takeown /f "%%f" >nul 2>&1
        icacls "%%f" /grant administrators:F >nul 2>&1
        del /f "%%f" >nul 2>&1
    )
)

:: 4. Spoof disk serial numbers (PowerShell with error ignore)
echo [*] Changing disk serials...
powershell -Command "$ErrorActionPreference='SilentlyContinue'; $drives = Get-WmiObject Win32_PhysicalMedia; foreach ($d in $drives) { $d.SerialNumber = 'S3Z6NB0M' + (Get-Random -Min 1000 -Max 9999); $d.Put() }" >nul 2>&1

:: Registry fallback
reg add "HKLM\HARDWARE\DEVICEMAP\Scsi\Scsi Port 0\Scsi Bus 0\Target Id 0\Logical Unit Id 0" /v SerialNumber /t REG_SZ /d "S3Z6NB0M%RANDOM:~-4%" /f >nul 2>&1

:: 5. Spoof MAC address
echo [*] Changing MAC address...
powershell -Command "$ErrorActionPreference='SilentlyContinue'; $adapter = Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.NetEnabled -eq $true } | Select-Object -First 1; if ($adapter) { $newMac = '00-1B-44-' + (Get-Random -Min 100000 -Max 999999).ToString('X'); $adapter.MACAddress = $newMac; $adapter.Put(); Restart-Service -Name 'Ndisuio' -Force -ErrorAction SilentlyContinue }" >nul 2>&1

:: 6. Spoof processor name (registry)
echo [*] Spoofing CPU strings...
for /l %%i in (0,1,15) do (
    reg add "HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\%%i" /v ProcessorNameString /t REG_SZ /d "Intel(R) Core(TM) i9-10900K CPU @ 3.70GHz" /f >nul 2>&1
    reg add "HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\%%i" /v VendorIdentifier /t REG_SZ /d "GenuineIntel" /f >nul 2>&1
)

:: 7. Spoof BIOS and motherboard
echo [*] Spoofing BIOS strings...
reg add "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v BIOSVendor /t REG_SZ /d "American Megatrends Inc." /f >nul 2>&1
reg add "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v BIOSVersion /t REG_SZ /d "1401" /f >nul 2>&1
reg add "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v SystemManufacturer /t REG_SZ /d "ASUSTeK COMPUTER INC." /f >nul 2>&1
reg add "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v SystemProductName /t REG_SZ /d "ROG Maximus XIII Hero" /f >nul 2>&1
reg add "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v ChassisManufacturer /t REG_SZ /d "ASUSTeK COMPUTER INC." /f >nul 2>&1
reg add "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v ChassisType /t REG_SZ /d "Desktop" /f >nul 2>&1

:: 8. Spoof video adapter
echo [*] Changing video adapter description...
powershell -Command "$ErrorActionPreference='SilentlyContinue'; $adapter = Get-WmiObject Win32_VideoController | Select-Object -First 1; if ($adapter) { $adapter.Description = 'NVIDIA GeForce RTX 3080'; $adapter.Name = 'NVIDIA GeForce RTX 3080'; $adapter.DriverVersion = '31.0.15.3623'; $adapter.Put() }" >nul 2>&1

:: 9. Kill VM processes and disable tasks (ignore missing)
taskkill /f /im vmtoolsd.exe >nul 2>&1
taskkill /f /im vmusr.exe >nul 2>&1
taskkill /f /im VBoxService.exe >nul 2>&1
taskkill /f /im VBoxTray.exe >nul 2>&1
schtasks /change /tn "VMware Tools" /disable >nul 2>&1
schtasks /change /tn "Oracle VM VirtualBox Guest Additions" /disable >nul 2>&1

:: 10. Fake software artifacts
echo [*] Planting decoys...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam" /v DisplayName /t REG_SZ /d "Steam" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome" /v DisplayName /t REG_SZ /d "Google Chrome" /f >nul 2>&1
reg add "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Discord" /v DisplayName /t REG_SZ /d "Discord" /f >nul 2>&1
mkdir "%ProgramFiles%\Steam" >nul 2>&1
mkdir "%ProgramFiles%\Google\Chrome" >nul 2>&1
mkdir "%AppData%\Discord" >nul 2>&1
type nul > "%USERPROFILE%\Desktop\Important_Work.docx" 2>nul
type nul > "%USERPROFILE%\Documents\passwords.txt" 2>nul

:: 11. Power and timer adjustments
echo [*] Adjusting power scheme...
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1
bcdedit /set useplatformclock true >nul 2>&1
bcdedit /set disabledynamictick yes >nul 2>&1

:: 12. Clean network adapter names
echo [*] Renaming network adapters...
powershell -Command "$ErrorActionPreference='SilentlyContinue'; Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.Name -match 'VMware|VirtualBox|Hyper-V' } | ForEach-Object { $_.Name = 'Intel(R) Ethernet Connection (7) I219-V'; $_.Put() }" >nul 2>&1

echo.
echo ============================================================
echo [*] Spoofing finished (errors ignored). Reboot required.
echo ============================================================
shutdown /r /t 15 /c "Rebooting to apply changes. Save your work."
pause
