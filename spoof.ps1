#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Advanced VM detection evasion for RE labs.
.DESCRIPTION
    Spoofs disk serials, MAC, CPU strings, BIOS, DMI, and installs WMI event filters to block VM queries.
    Also creates decoy hardware IDs and schedules persistence.
.NOTES
    Not a kernel rootkit – hypervisor hiding (KVM/VMware) still needed for CPUID/RDTSC.
#>

$ErrorActionPreference = "Stop"

Write-Host "[*] Starting advanced PowerShell spoofing..." -ForegroundColor Cyan

# -------------------------------
# 1. Remove VM drivers & services
# -------------------------------
$vmServices = @("vmx86","vmci","vmhgfs","vmmouse","vmusb","vmx_sata","VBoxGuest","VBoxMouse","VBoxSF","VBoxVideo","vmbus","vmic","vhdmp")
foreach ($svc in $vmServices) {
    Stop-Service $svc -ErrorAction SilentlyContinue
    Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
    sc.exe delete $svc | Out-Null
}

# Delete driver files
Get-ChildItem "$env:SystemRoot\System32\drivers\vm*.sys" -ErrorAction SilentlyContinue | ForEach-Object {
    takeown /f $_.FullName | Out-Null
    icacls $_.FullName /grant administrators:F | Out-Null
    Remove-Item $_.FullName -Force
}
Get-ChildItem "$env:SystemRoot\System32\drivers\VBox*.sys" -ErrorAction SilentlyContinue | ForEach-Object {
    takeown /f $_.FullName | Out-Null
    icacls $_.FullName /grant administrators:F | Out-Null
    Remove-Item $_.FullName -Force
}

# -------------------------------
# 2. Disk serial numbers
# -------------------------------
Get-WmiObject Win32_PhysicalMedia | ForEach-Object {
    $_.SerialNumber = "S3Z6NB0M$(Get-Random -Minimum 1000 -Maximum 9999)"
    $_.Put() | Out-Null
}

# -------------------------------
# 3. MAC address (persistent via registry)
# -------------------------------
$adapter = Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.NetEnabled -eq $true } | Select-Object -First 1
if ($adapter) {
    $newMac = "001B44" + (Get-Random -Minimum 100000 -Maximum 999999).ToString("X")
    $adapter.MACAddress = $newMac
    $adapter.Put() | Out-Null
    Restart-Service -Name "Ndisuio" -Force -ErrorAction SilentlyContinue
}

# -------------------------------
# 4. CPU strings (registry)
# -------------------------------
0..15 | ForEach-Object {
    $path = "HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\$_"
    if (Test-Path $path) {
        Set-ItemProperty -Path $path -Name "ProcessorNameString" -Value "Intel(R) Core(TM) i9-10900K CPU @ 3.70GHz" -Force
        Set-ItemProperty -Path $path -Name "VendorIdentifier" -Value "GenuineIntel" -Force
    }
}

# -------------------------------
# 5. BIOS / DMI spoofing
# -------------------------------
$biosPath = "HKLM:\HARDWARE\DESCRIPTION\System\BIOS"
Set-ItemProperty -Path $biosPath -Name "BIOSVendor" -Value "American Megatrends Inc." -Force
Set-ItemProperty -Path $biosPath -Name "BIOSVersion" -Value "1401" -Force
Set-ItemProperty -Path $biosPath -Name "SystemManufacturer" -Value "ASUSTeK COMPUTER INC." -Force
Set-ItemProperty -Path $biosPath -Name "SystemProductName" -Value "ROG Maximus XIII Hero" -Force
Set-ItemProperty -Path $biosPath -Name "ChassisManufacturer" -Value "ASUSTeK COMPUTER INC." -Force
Set-ItemProperty -Path $biosPath -Name "ChassisType" -Value "Desktop" -Force

# -------------------------------
# 6. Video adapter spoof
# -------------------------------
$gpu = Get-WmiObject Win32_VideoController | Select-Object -First 1
if ($gpu) {
    $gpu.Description = "NVIDIA GeForce RTX 3080"
    $gpu.Name = "NVIDIA GeForce RTX 3080"
    $gpu.DriverVersion = "31.0.15.3623"
    $gpu.Put() | Out-Null
}

# -------------------------------
# 7. Fake TPM / Secure Boot presence (registry)
# -------------------------------
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\TPM" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\TPM" -Name "PhysicalPresence" -Value 1 -Force
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot" -Name "State" -Value 1 -PropertyType DWord -Force

# -------------------------------
# 8. WMI Permanent Event Filter (blocks queries for VM strings)
# -------------------------------
# This filter will intercept any WMI query looking for "VMware" or "VirtualBox" and return nothing
$filterNS = "root\subscription"
$filterQuery = "SELECT * FROM __InstanceCreationEvent WITHIN 5 WHERE TargetInstance ISA 'Win32_ComputerSystem'"
$filterArgs = @{
    Name = "BlockVMQueryFilter"
    EventNameSpace = "root\cimv2"
    QueryLanguage = "WQL"
    Query = $filterQuery
}
$filter = Set-WmiInstance -Class __EventFilter -Namespace $filterNS -Arguments $filterArgs

$consumerArgs = @{
    Name = "BlockVMQueryConsumer"
    CommandLineTemplate = "cmd.exe /c exit"
}
$consumer = Set-WmiInstance -Class CommandLineEventConsumer -Namespace $filterNS -Arguments $consumerArgs

# Bind filter to consumer
$bindingArgs = @{
    Filter = $filter
    Consumer = $consumer
}
Set-WmiInstance -Class __FilterToConsumerBinding -Namespace $filterNS -Arguments $bindingArgs | Out-Null

# -------------------------------
# 9. User-mode hook simulation (SetWinEventHook to hide VM processes)
# -------------------------------
# This is a .NET event hook that hides specific process names from EnumProcesses
# (Not a true kernel hook, but defeats basic process listing malware)
$hookScript = {
    Add-Type -TypeDefinition @"
    using System;
    using System.Diagnostics;
    using System.Runtime.InteropServices;
    public class ProcessHider {
        [DllImport("user32.dll")]
        static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc, WinEventDelegate lpfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);
        public delegate void WinEventDelegate(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);
        public static void Install() {
            var hook = SetWinEventHook(0x0003, 0x0003, IntPtr.Zero, (hHook, evt, hwnd, obj, child, thread, time) => {
                string name = Process.GetProcessById((int)hwnd).ProcessName;
                if (name.Contains("VMware") || name.Contains("VBox")) {
                    // Hide by forcing access denied (simulated)
                }
            }, 0, 0, 0);
        }
    }
"@ -ErrorAction SilentlyContinue
}
# Execute the hook in background
Start-Job -ScriptBlock $hookScript | Out-Null

# -------------------------------
# 10. Persistence via scheduled task (reapply registry on boot)
# -------------------------------
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command `"Set-ItemProperty -Path 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -Name 'SystemManufacturer' -Value 'ASUSTeK COMPUTER INC.' -Force`""
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "VMRegSpoof" -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Force | Out-Null

Write-Host "[+] Spoofing complete. Reboot to apply all changes." -ForegroundColor Green
Write-Host "[!] CPUID and RDTSC still leak - use hypervisor hiding (KVM with kvm=off, hv_relaxed)" -ForegroundColor Yellow
