# Intune Proactive Remediation Remediation Script - Reboot Toast Notification
# This script shows a toast notification prompting the user to reboot

param()

# Function to write to event log for Intune reporting
function Write-IntuneLog {
    param(
        [string]$Message,
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Level = "Information"
    )
    
    $EventID = switch ($Level) {
        "Information" { 1000 }
        "Warning" { 2000 }
        "Error" { 3000 }
    }
    
    try {
        # Create event source if it doesn't exist
        $SourceName = "IntuneRebootRemediation"
        if (-not [System.Diagnostics.EventLog]::SourceExists($SourceName)) {
            [System.Diagnostics.EventLog]::CreateEventSource($SourceName, "Application")
        }
        Write-EventLog -LogName Application -Source $SourceName -EventId $EventID -EntryType $Level -Message $Message
    }
    catch {
        # Fallback to Write-Output if event log fails
        Write-Output "$Level`: $Message"
    }
}

# Function to get given name (simplified)
function Get-GivenName {
    try {
        # Try registry first (fastest)
        $RegKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
        $DisplayName = (Get-ItemProperty -Path $RegKey -Name "LastLoggedOnDisplayName" -ErrorAction SilentlyContinue).LastLoggedOnDisplayName
        if ($DisplayName) {
            $FirstName = ($DisplayName.Trim() -split '\s+')[0]
            if ($FirstName -and $FirstName -notmatch '^\d+$' -and $FirstName.Length -gt 1) {
                return $FirstName
            }
        }
        
        # Fallback to current user
        $CurrentUser = [Environment]::UserName
        if ($CurrentUser -and $CurrentUser -ne "SYSTEM") {
            return $CurrentUser
        }
        
        return "User"
    }
    catch {
        return "User"
    }
}

# Function to test if Windows 10/11
function Test-SupportedWindows {
    try {
        $OS = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        return (($OS.Version -like "10.0.*") -AND ($OS.ProductType -eq 1))
    }
    catch {
        return $false
    }
}

# Function to ensure toast notifications are enabled
function Enable-ToastNotifications {
    try {
        $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications"
        $ToastEnabled = (Get-ItemProperty -Path $RegPath -Name "ToastEnabled" -ErrorAction SilentlyContinue).ToastEnabled
        
        if ($ToastEnabled -ne 1) {
            New-ItemProperty -Path $RegPath -Name "ToastEnabled" -PropertyType "DWORD" -Value 1 -Force | Out-Null
            Write-IntuneLog "Toast notifications enabled for user" -Level Information
        }
        return $true
    }
    catch {
        Write-IntuneLog "Failed to enable toast notifications: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

# Function to display toast notification
function Show-RebootToast {
    param(
        [string]$Title = "Restart Required",
        [string]$Message = "Your computer needs to restart to complete important updates. Please save your work and restart soon.",
        [string]$ButtonText = "Restart Now",
        [string]$AppName = "IT Support"
    )
    
    try {
        # Load Windows Runtime
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        
        # Create toast XML
        $ToastXml = @"
<toast activationType="protocol" launch="ms-settings:windowsupdate" duration="long" scenario="reminder">
    <visual>
        <binding template="ToastGeneric">
            <text>$Title</text>
            <text>$Message</text>
            <text placement="attribution">$AppName</text>
        </binding>
    </visual>
    <actions>
        <action content="$ButtonText" arguments="shutdown /r /t 300 /c 'Restarting in 5 minutes. Save your work now.'" activationType="protocol" />
        <action content="Remind me later" arguments="dismiss" activationType="system" />
    </actions>
    <audio src="ms-winsoundevent:Notification.Reminder" />
</toast>
"@
        
        # Create XML document
        $XmlDoc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $XmlDoc.LoadXml($ToastXml)
        
        # Create and show notification
        $AppId = if ($AppName) { $AppName } else { "PowerShell" }
        $Notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)
        $Toast = [Windows.UI.Notifications.ToastNotification]::new($XmlDoc)
        $Notifier.Show($Toast)
        
        Write-IntuneLog "Toast notification displayed successfully" -Level Information
        return $true
    }
    catch {
        Write-IntuneLog "Failed to display toast notification: $($_.Exception.Message)" -Level Error
        return $false
    }
}

# Main remediation logic
try {
    Write-IntuneLog "Starting reboot notification remediation (silent mode)" -Level Information
    
    # Check if user is logged in
    $LoggedInUser = (Get-WmiObject -Class Win32_ComputerSystem).UserName
    if (-not $LoggedInUser) {
        Write-IntuneLog "No user logged in - skipping notification" -Level Information
        Write-Output "No user session active"
        exit 0
    }
    
    Write-IntuneLog "User logged in: $LoggedInUser" -Level Information
    
    # Get system uptime to determine appropriate notification stage
    $Uptime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $UptimeDays = ((Get-Date) - $Uptime).Days
    
    Write-IntuneLog "System uptime: $UptimeDays days" -Level Information
    
    # Determine script location and config
    $ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $HiddenLauncher = Join-Path $ScriptDirectory "Invoke-ToastHidden.ps1"
    
    # Check if we have the hidden launcher, otherwise use direct method
    if (Test-Path $HiddenLauncher) {
        Write-IntuneLog "Using hidden launcher for completely silent execution" -Level Information
        
        # Use the hidden launcher which handles everything silently
        $Arguments = @(
            "-ExecutionPolicy", "Bypass"
            "-WindowStyle", "Hidden"
            "-NoProfile"
            "-NonInteractive"
            "-NoLogo"
            "-File", "`"$HiddenLauncher`""
            "-UptimeThreshold", "$UptimeDays"
            "-Force"
        )
        
        $Process = Start-Process -FilePath "powershell.exe" -ArgumentList $Arguments -WindowStyle Hidden -PassThru -Wait
        
        if ($Process.ExitCode -eq 0) {
            Write-IntuneLog "Hidden toast notification executed successfully" -Level Information
            Write-Output "Reboot notification displayed successfully (hidden mode)"
            exit 0
        } else {
            Write-IntuneLog "Hidden launcher returned error code: $($Process.ExitCode)" -Level Warning
            # Fall back to direct method below
        }
    }
    
    # Fallback: Direct toast notification (still hidden)
    Write-IntuneLog "Using direct toast notification method" -Level Information