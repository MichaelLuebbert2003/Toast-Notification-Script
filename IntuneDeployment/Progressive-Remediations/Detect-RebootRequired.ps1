# Intune Proactive Remediation Detection Script - Reboot Required
# This script detects if a reboot is required and exits with code 1 if remediation is needed

param()

# Function to check pending reboot in registry
function Test-PendingRebootRegistry {
    $CBSRebootKey = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue
    $WURebootKey = Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue
    $FileRebootKey = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    
    return (($CBSRebootKey -ne $null) -OR ($WURebootKey -ne $null) -OR ($FileRebootKey -ne $null))
}

# Function to check pending reboot via WMI (ConfigMgr if present)
function Test-PendingRebootWMI {
    if (Get-Service -Name ccmexec -ErrorAction SilentlyContinue) {
        try {
            return ([WmiClass]"ROOT\ccm\ClientSDK:CCM_ClientUtilities").DetermineIfRebootPending().RebootPending
        }
        catch {
            return $false
        }
    }
    return $false
}

# Function to get device uptime in days
function Get-DeviceUptimeDays {
    try {
        $OS = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $Uptime = (Get-Date) - ($OS.LastBootUpTime)
        return [math]::Round($Uptime.TotalDays, 1)
    }
    catch {
        return 0
    }
}

# Configuration - adjust these values as needed
$MaxUptimeDays = 7  # Maximum allowed uptime in days
$CheckRegistryReboot = $true
$CheckWMIReboot = $true
$CheckUptime = $true

try {
    $RebootRequired = $false
    $Reasons = @()
    
    # Check registry for pending reboots
    if ($CheckRegistryReboot -and (Test-PendingRebootRegistry)) {
        $RebootRequired = $true
        $Reasons += "Registry indicates pending reboot"
    }
    
    # Check WMI for pending reboots
    if ($CheckWMIReboot -and (Test-PendingRebootWMI)) {
        $RebootRequired = $true
        $Reasons += "WMI indicates pending reboot"
    }
    
    # Check uptime
    if ($CheckUptime) {
        $UptimeDays = Get-DeviceUptimeDays
        if ($UptimeDays -gt $MaxUptimeDays) {
            $RebootRequired = $true
            $Reasons += "Uptime exceeded $MaxUptimeDays days (current: $UptimeDays days)"
        }
    }
    
    if ($RebootRequired) {
        Write-Output "Reboot required: $($Reasons -join ', ')"
        exit 1  # Exit code 1 indicates remediation is needed
    }
    else {
        Write-Output "No reboot required"
        exit 0  # Exit code 0 indicates compliance
    }
}
catch {
    Write-Output "Error during detection: $($_.Exception.Message)"
    exit 0  # Exit code 0 on error to avoid false positives
}