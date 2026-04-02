@echo off
title VM Spoofer - Advanced (Research Only)
setlocal enabledelayedexpansion

:: Admin check
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Administrator rights required.
    pause
    exit /b 1
)

echo ============================================================
echo Advanced VM Artifact Spoofing for Reverse Engineering
echo ============================================================
echo.

:: -------------------------------------------------------------------
:: 1. Disable Hyper-V and remove hypervisor presence (if present)
:: -------------------------------------------------------------------
echo [*] Disabling Hyper-V boot flags...
bcdedit /set hypervisorlaunchtype off >nul 2>&1
bcdedit /set nx AlwaysOn >nul 2>&1

:: -------------------------------------------------------------------
:: 2. Remove common VM kernel drivers and mark for deletion
:: -------------------------------------------------------------------
echo [*] Removing VM driver services and scheduled deletion...
set DRV_LIST="vmx86 vmci vmhgfs vmmouse vmusb vmx_sata VBoxGuest VBoxMouse VBoxSF VBoxVideo vmbus vmic vhdmp"
for %%d in (%DRV_LIST%) do (
    sc stop %%d >nul 2>&1
    sc delete %%d >nul 2>&1
    echo %%d>>%temp%\drv_del.tmp
)

:: Schedule deletion of driver files on next reboot
takeown /f C:\Windows\System32\drivers\*.sys >nul 2>&1
for /f "tokens=*" %%f in ('dir /b C:\Windows\System32\drivers\vm*.sys 2^>nul') do (
    takeown /f "C:\Windows\System32\drivers\%%f" >nul 2>&1
    icacls "C:\Windows\System32\drivers\%%f" /grant administrators:F >nul 2>&1
    del /f "C:\Windows\System32\drivers\%%f" >nul 2>&1
)
for /f "tokens=*" %%f in ('dir /b C:\Windows\System32\drivers\VBox*.sys 2^>nul') do (
    takeown /f "C:\Windows\System32\drivers\%%f" >nul 2>&1
    icacls "C:\Windows\System32\drivers\%%f" /grant administrators:F >nul 2>&1
    del /f "C:\Windows\System32\drivers\%%f" >nul 2>&1
)

:: -------------------------------------------------------------------
:: 3. Change disk serial numbers (persistent across reboots)
:: -------------------------------------------------------------------
echo [*] Spoofing physical disk serial numbers...
powershell -Command "
$drives = Get-WmiObject Win32_PhysicalMedia
foreach ($drive in $drives) {
    $drive.SerialNumber = 'S3Z6NB0M' + (Get-Random -Minimum 1000 -Maximum 9999)
    $drive.Put() | Out-Null
}
"

:: Also modify IDE/ATA registry (for older detection)
reg add "HKLM\HARDWARE\DEVICEMAP\Scsi\Scsi Port 0\Scsi Bus 0\Target Id 0\Logical Unit Id 0" /v SerialNumber /t REG_SZ /d "S3Z6NB0M%RANDOM:~-4%" /f >nul 2>&1

:: -------------------------------------------------------------------
:: 4. Spoof MAC address (persistent, requires adapter restart)
:: -------------------------------------------------------------------
echo [*] Changing MAC address of active adapters...
powershell -Command "
$adapters = Get-WmiObject Win32_NetworkAdapter | Where-Object {$_.NetEnabled -eq $true}
foreach ($adapter in $adapters) {
    $newMac = '00-1B-44-' + (Get-Random -Minimum 100000 -Maximum 999999).ToString('X')
    $adapter.MACAddress = $newMac
    $adapter.Put() | Out-Null
    Restart-Service -Name 'Ndisuio' -Force -ErrorAction SilentlyContinue
}
"

:: -------------------------------------------------------------------
:: 5. Spoof processor name and vendor (affects WMIC/registry, not CPUID)
:: -------------------------------------------------------------------
echo [*] Changing CPU name strings...
for /l %%i in (0,1,15) do (
    reg add "HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\%%i" /v ProcessorNameString /t REG_SZ /d "Intel(R) Core(TM) i9-10900K CPU @ 3.70GHz" /f >nul 2>&1
    reg add "HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\%%i" /v VendorIdentifier /t REG_SZ /d "GenuineIntel" /f >nul 2>&1
)

:: -------------------------------------------------------------------
:: 6. Spoof BIOS, motherboard, and chassis strings
:: -------------------------------------------------------------------
echo [*] Spoofing DMI/BIOS strings...
reg add "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v BIOSVendor /t REG_SZ /d "American Megatrends Inc." /f >nul 2>&1
reg add "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v BIOSVersion /t REG_SZ /d "1401" /f >nul 2>&1
reg add "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v SystemManufacturer /t REG_SZ /d "ASUSTeK COMPUTER INC." /f >nul 2>&1
reg add "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v SystemProductName /t REG_SZ /d "ROG Maximus XIII Hero" /f >nul 2>&1
reg add "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v ChassisManufacturer /t REG_SZ /d "ASUSTeK COMPUTER INC." /f >nul 2>&1
reg add "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v ChassisType /t REG_SZ /d "Desktop" /f >nul 2>&1

:: -------------------------------------------------------------------
:: 7. Spoof video adapter (remove VM GPU, add fake Intel/NVIDIA)
:: -------------------------------------------------------------------
echo [*] Modifying display adapter description...
powershell -Command "
$adapter = Get-WmiObject Win32_VideoController | Select-Object -First 1
if ($adapter) {
    $adapter.Description = 'NVIDIA GeForce RTX 3080'
    $adapter.Name = 'NVIDIA GeForce RTX 3080'
    $adapter.DriverVersion = '31.0.15.3623'
    $adapter.Put() | Out-Null
}
"

:: -------------------------------------------------------------------
:: 8. Remove common VM processes and scheduled tasks
:: -------------------------------------------------------------------
echo [*] Killing and disabling VM helper processes...
taskkill /f /im vmtoolsd.exe >nul 2>&1
taskkill /f /im vmusr.exe >nul 2>&1
taskkill /f /im VBoxService.exe >nul 2>&1
taskkill /f /im VBoxTray.exe >nul 2>&1
schtasks /change /tn "VMware Tools" /disable >nul 2>&1
schtasks /change /tn "Oracle VM VirtualBox Guest Additions" /disable >nul 2>&1

:: -------------------------------------------------------------------
:: 9. Add fake user-land artifacts (installed software, temp files)
:: -------------------------------------------------------------------
echo [*] Planting decoy artifacts (common software presence)...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam" /v DisplayName /t REG_SZ /d "Steam" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome" /v DisplayName /t REG_SZ /d "Google Chrome" /f >nul 2>&1
reg add "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Discord" /v DisplayName /t REG_SZ /d "Discord" /f >nul 2>&1
mkdir "%ProgramFiles%\Steam" >nul 2>&1
mkdir "%ProgramFiles%\Google\Chrome" >nul 2>&1
mkdir "%AppData%\Discord" >nul 2>&1
type nul > "%USERPROFILE%\Desktop\Important_Work.docx" >nul 2>&1
type nul > "%USERPROFILE\Documents\passwords.txt" >nul 2>&1

:: -------------------------------------------------------------------
:: 10. Disable time-sensitive detection (reduce RDTSC noise - partial)
:: -------------------------------------------------------------------
:: Note: Cannot fix RDTSC from batch, but we can force HPET and disable dynamic tick
echo [*] Adjusting power scheme and timers...
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1  :: High performance
bcdedit /set useplatformclock true >nul 2>&1
bcdedit /set disabledynamictick yes >nul 2>&1

:: -------------------------------------------------------------------
:: 11. Modify network adapter descriptions (remove VM strings)
:: -------------------------------------------------------------------
echo [*] Cleaning network adapter names...
powershell -Command "
Get-WmiObject Win32_NetworkAdapter | Where-Object {$_.Name -match 'VMware|VirtualBox|Hyper-V'} | ForEach-Object {
    $_.Name = 'Intel(R) Ethernet Connection (7) I219-V'
    $_.Put() | Out-Null
}
"

:: -------------------------------------------------------------------
:: 12. Final steps
:: -------------------------------------------------------------------
echo.
echo ============================================================
echo [*] Spoofing completed. A reboot is required for many changes.
echo [*] After reboot, verify with:
echo     - wmic diskdrive get serialnumber
echo     - wmic nic get macaddress
echo     - wmic bios get version
echo     - systeminfo
echo     - Get-WmiObject Win32_ComputerSystem
echo.
echo [*] What remains undetectable from user mode:
echo     - CPUID hypervisor vendor (requires hypervisor config)
echo     - RDTSC timing anomalies (use hypervisor time hiding)
echo     - Certain SMBIOS tables (need BIOS mod)
echo ============================================================
shutdown /r /t 15 /c "Rebooting to apply full VM spoofing. Save your work."
pause
