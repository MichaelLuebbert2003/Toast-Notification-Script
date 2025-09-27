<#
.SYNOPSIS
    Create toast notifications for pending reboot reminders in Windows 10/11.

.DESCRIPTION
    Displays toast notifications to remind users of pending reboots.
    Checks for pending reboots in registry/WMI and computer uptime.
    Everything is customizable through config-toast.xml.
    All actions are logged to a local log file in AppData\Roaming\ToastNotificationScript\New-ToastNotification.log.

.PARAMETER Config
    Specify the path for the config.xml. If none is specified, the script uses the local config.xml

.PARAMETER Force
    Force display the toast notification even if reboot conditions are not met. Useful for testing.

.NOTES
    Filename: New-ToastNotification.ps1
    Version: 2.3.0-ML
    Author: Michael Luebbert (Based on original work by Martin Bengtsson)
    Original Blog: www.imab.dk
    Original Twitter: @mwbengtsson
    
    Modified version focusing only on reboot-related functionality with enhanced auto-reboot capabilities.
#> 

[CmdletBinding()]
param(
    [Parameter(HelpMessage='Path to XML Configuration File')]
    [string]$Config,
    
    [Parameter(HelpMessage='Force display the toast notification even if reboot conditions are not met')]
    [switch]$Force
)

#region Functions
# Create Write-Log function
function Write-Log() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [Alias('LogPath')]
        [string]$Path = "$env:APPDATA\ToastNotificationScript\New-ToastNotification.log",
        [Parameter(Mandatory=$false)]
        [ValidateSet("Error","Warn","Info")]
        [string]$Level = "Info"
    )
    Begin {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'
    }
    Process {
		if (Test-Path $Path) {
			$LogSize = (Get-Item -Path $Path).Length/1MB
			$MaxLogSize = 5
		}
        # Check for file size of the log. If greater than 5MB, it will create a new one and delete the old.
        if ((Test-Path $Path) -AND $LogSize -gt $MaxLogSize) {
            Write-Error "Log file $Path already exists and file exceeds maximum file size. Deleting the log and starting fresh."
            Remove-Item $Path -Force
            $NewLogFile = New-Item $Path -Force -ItemType File
        }
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
        elseif (-NOT(Test-Path $Path)) {
            Write-Verbose "Creating $Path."
            $NewLogFile = New-Item $Path -Force -ItemType File
        }
        else {
            # Nothing to see here yet.
        }
        # Format Date for our Log File
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        # Write message to error, warning, or verbose pipeline and specify $LevelText
        switch ($Level) {
            'Error' {
                Write-Warning "ERROR: $Message"
                $LevelText = 'ERROR:'
            }
            'Warn' {
                Write-Warning $Message
                $LevelText = 'WARNING:'
            }
            'Info' {
                Write-Verbose $Message
                $LevelText = 'INFO:'
            }
        }
        # Write log entry to $Path
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
    }
    End {
    }
}

# Create Pending Reboot function for registry
function Test-PendingRebootRegistry() {
    Write-Log -Message "Running Test-PendingRebootRegistry function"
    $CBSRebootKey = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction Ignore
    $WURebootKey = Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction Ignore
    $FileRebootKey = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction Ignore
    if (($CBSRebootKey -ne $null) -OR ($WURebootKey -ne $null) -OR ($FileRebootKey -ne $null)) {
        Write-Log -Message "Check returned TRUE on ANY of the registry checks: Reboot is pending!"
        $true
    }
    else {
        Write-Log -Message "Check returned FALSE on ANY of the registry checks: Reboot is NOT pending!"
        $false
    }
}

# Create Pending Reboot function for WMI via ConfigMgr client
function Test-PendingRebootWMI() {
    Write-Log -Message "Running Test-PendingRebootWMI function"   
    if (Get-Service -Name ccmexec -ErrorAction SilentlyContinue) {
        Write-Log -Message "Computer has ConfigMgr client installed - checking for pending reboots in WMI"
        $Util = [wmiclass]"\\.\root\ccm\clientsdk:CCM_ClientUtilities"
        $Status = $Util.DetermineIfRebootPending()
        if (($Status -ne $null) -AND ($Status.RebootPending -eq $True)) {
            Write-Log -Message "Check returned TRUE on checking WMI for pending reboot: Reboot is pending!"
            $true
        }
        else {
            Write-Log -Message "Check returned FALSE on checking WMI for pending reboot: Reboot is NOT pending!"
            $false
        }
    }
    else {
        Write-Log -Level Error -Message "Computer has no ConfigMgr client installed - skipping checking WMI for pending reboots"
        $false
    }
}

# Create Get Device Uptime function
function Get-DeviceUptime() {
    Write-Log -Message "Running Get-DeviceUptime function"
    $OS = Get-CimInstance Win32_OperatingSystem
    $Uptime = (Get-Date) - ($OS.LastBootUpTime)
    $Uptime.Days
}

# Create Get GivenName function
function Get-GivenName {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Write-Log -Message "Running Get-GivenName function"
    $GivenName = $null

    # Helper: is the machine domain-joined?
    function _IsDomainJoined {
        try {
            return (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
        } catch {
            Write-Log -Level Warn -Message "Could not read PartOfDomain: $($_.Exception.Message)"
            return $false
        }
    }

    # Helper: get interactive username (sam or upn)
    function _Get-InteractiveSamOrUpn {
        try {
            $owner = Get-Process -Name explorer -IncludeUserName -ErrorAction Stop |
                     Select-Object -First 1 -ExpandProperty UserName
            if ($owner) { return ($owner -split '\\')[-1] }
        } catch {}
        try {
            $lines = (quser 2>$null) -split "`r?`n" | Where-Object { $_.Trim() }
            $active = $lines | Where-Object { $_ -match '\sActive(\s|$)' } | Select-Object -First 1
            if ($active) {
                $tokens = ($active -replace '^\s*>?\s*','') -split '\s+'
                if ($tokens.Count -gt 0 -and $tokens[0] -and $tokens[0] -ne 'USERNAME') { return $tokens[0] }
            }
        } catch {}
        try {
            $csUser = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName
            if ($csUser) { return ($csUser -split '\\')[-1] }
        } catch {}
        return $null
    }

    # Helper: resolve AD GivenName for identity (sam or upn)
    function _TryResolveAdGivenName([string]$Identity) {
        if ([string]::IsNullOrWhiteSpace($Identity)) { return $null }
        if (-not (_IsDomainJoined)) {
            Write-Log -Level Info -Message "Device not domain-joined; skipping AD GivenName lookup."
            return $null
        }
        try {
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement
            $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext `
                    ([System.DirectoryServices.AccountManagement.ContextType]::Domain)
            try {
                $p = [System.DirectoryServices.AccountManagement.Principal]::FindByIdentity(
                        $ctx,
                        [System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,
                        $Identity
                    )
                if (-not $p) {
                    $p = [System.DirectoryServices.AccountManagement.Principal]::FindByIdentity(
                            $ctx,
                            [System.DirectoryServices.AccountManagement.IdentityType]::UserPrincipalName,
                            $Identity
                        )
                }
                if ($p -and $p.GivenName) { return $p.GivenName }
            } finally {
                if ($ctx) { $ctx.Dispose() }
            }
        } catch {
            Write-Log -Level Warn -Message "AD lookup failed: $($_.Exception.Message)"
        }
        return $null
    }

    # --- 1) Your original AD lookup, but ONLY if domain-joined ---
    try {
        if (_IsDomainJoined) {
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement
            $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext `
                    ([System.DirectoryServices.AccountManagement.ContextType]::Domain)
            try {
                $p = [System.DirectoryServices.AccountManagement.Principal]::FindByIdentity(
                        $ctx,
                        [System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,
                        [Environment]::UserName
                    )
                if ($p -and $p.GivenName) { $GivenName = $p.GivenName }
            } finally {
                if ($ctx) { $ctx.Dispose() }
            }
        } else {
            Write-Log -Level Info -Message "Device not domain-joined; skipping primary AD lookup."
        }
    } catch {
        Write-Log -Level Warn -Message "Primary AD lookup failed: $($_.Exception.Message)"
    }

    if (-not [string]::IsNullOrEmpty($GivenName)) {
        Write-Log -Message "Given name retrieved from Active Directory: $GivenName"
        Write-Output $GivenName
        return
    }

    # --- 2) Your original registry fallback (LogonUI) ---
    Write-Log -Message "Given name not found in AD. Checking LogonUI registry."
    try {
        $RegKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
        $val = (Get-ItemProperty -Path $RegKey -Name "LastLoggedOnDisplayName" -ErrorAction Stop).LastLoggedOnDisplayName
        if ($val) {
            $DisplayNameParts = $val.Trim() -split '\s+'
            if ($DisplayNameParts.Count -gt 0) {
                $GivenName = $DisplayNameParts[0]
                Write-Log -Message "Given name found directly in registry: $GivenName"
            }
        } else {
            Write-Log -Message "Given name not found in registry."
        }
    } catch {
        Write-Log -Level Info -Message "LogonUI registry not available."
    }

    if (-not [string]::IsNullOrEmpty($GivenName)) {
        Write-Output $GivenName
        return
    }

    # --- 3) Robust fallback (interactive identity → AD → display name → username/env) ---
    $samOrUpn = _Get-InteractiveSamOrUpn
    if ($samOrUpn) { Write-Log -Message "Fallback: interactive identity = $samOrUpn" }

    if (-not $GivenName -and $samOrUpn) {
        $GivenName = _TryResolveAdGivenName $samOrUpn
        if ($GivenName) { Write-Log -Message "Fallback: AD GivenName = $GivenName" }
    }

    if (-not $GivenName) {
        try {
            $RegKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
            $val2 = (Get-ItemProperty -Path $RegKey -Name 'LastLoggedOnDisplayName' -ErrorAction Stop).LastLoggedOnDisplayName
            if ($val2) {
                $parts = $val2.Trim() -split '\s+'
                if ($parts.Count -gt 0) {
                    $GivenName = $parts[0]
                    Write-Log -Message "Fallback: first name from LogonUI = $GivenName"
                }
            }
        } catch {}
    }

    if (-not $GivenName) {
        if ($samOrUpn) {
            if ($samOrUpn -like '*@*') {
                $GivenName = ($samOrUpn -split '@')[0]
            } else {
                $GivenName = $samOrUpn
            }
            Write-Log -Message "Fallback: derived from username = $GivenName"
        } else {
            $GivenName = $env:USERNAME
            Write-Log -Message "Fallback: using env:USERNAME = $GivenName"
        }
    }

    Write-Output ([string]$GivenName)
}

# Create Start-ForceRebootCountdown function
# This function creates a visible countdown window and schedules a forced reboot
function Start-ForceRebootCountdown {
    param(
        [int]$CountdownSeconds = 3600,
        [string]$CompanyName = "IT Support"
    )
    
    Write-Log -Message "Starting force reboot countdown with visible timer"
    
    # Create the countdown script content
    $CountdownScript = @"
param(
    [int]`$CountdownSeconds = $CountdownSeconds,
    [string]`$CompanyName = "$CompanyName"
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Start OS-level shutdown timer as backup
try {
    Start-Process -FilePath "`$env:SystemRoot\System32\shutdown.exe" -ArgumentList "/r /f /t `$CountdownSeconds /c `"Scheduled reboot in progress. Please save your work.`"" -WindowStyle Hidden
} catch {
    Write-Host "Failed to schedule system shutdown: `$(`$_.Exception.Message)"
}

# Create countdown form
`$form = New-Object System.Windows.Forms.Form
`$form.Text = "Automatic Restart - `$CompanyName"
`$form.Size = New-Object System.Drawing.Size(500, 300)
`$form.StartPosition = 'CenterScreen'
`$form.FormBorderStyle = 'FixedDialog'
`$form.MaximizeBox = `$false
`$form.MinimizeBox = `$true
`$form.TopMost = `$true
`$form.BackColor = [System.Drawing.Color]::White

# Title label
`$titleLabel = New-Object System.Windows.Forms.Label
`$titleLabel.Text = "Automatic Restart Required"
`$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
`$titleLabel.ForeColor = [System.Drawing.Color]::DarkRed
`$titleLabel.Location = New-Object System.Drawing.Point(20, 20)
`$titleLabel.Size = New-Object System.Drawing.Size(450, 30)
`$form.Controls.Add(`$titleLabel)

# Message label
`$messageLabel = New-Object System.Windows.Forms.Label
`$messageLabel.Text = "Your computer will restart automatically to maintain security and performance.`nPlease save your work immediately."
`$messageLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10)
`$messageLabel.Location = New-Object System.Drawing.Point(20, 60)
`$messageLabel.Size = New-Object System.Drawing.Size(450, 50)
`$form.Controls.Add(`$messageLabel)

# Countdown label
`$countdownLabel = New-Object System.Windows.Forms.Label
`$countdownLabel.Font = New-Object System.Drawing.Font('Segoe UI', 24, [System.Drawing.FontStyle]::Bold)
`$countdownLabel.ForeColor = [System.Drawing.Color]::DarkRed
`$countdownLabel.TextAlign = 'MiddleCenter'
`$countdownLabel.Location = New-Object System.Drawing.Point(50, 130)
`$countdownLabel.Size = New-Object System.Drawing.Size(400, 50)
`$form.Controls.Add(`$countdownLabel)

# Progress bar
`$progressBar = New-Object System.Windows.Forms.ProgressBar
`$progressBar.Location = New-Object System.Drawing.Point(20, 190)
`$progressBar.Size = New-Object System.Drawing.Size(450, 20)
`$progressBar.Maximum = `$CountdownSeconds
`$form.Controls.Add(`$progressBar)

# Restart now button
`$restartButton = New-Object System.Windows.Forms.Button
`$restartButton.Text = "Restart Now"
`$restartButton.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
`$restartButton.BackColor = [System.Drawing.Color]::Red
`$restartButton.ForeColor = [System.Drawing.Color]::White
`$restartButton.Location = New-Object System.Drawing.Point(200, 220)
`$restartButton.Size = New-Object System.Drawing.Size(100, 30)
`$restartButton.Add_Click({
    try {
        Start-Process -FilePath "`$env:SystemRoot\System32\shutdown.exe" -ArgumentList "/a" -WindowStyle Hidden | Out-Null
    } catch {}
    Start-Process -FilePath "`$env:SystemRoot\System32\shutdown.exe" -ArgumentList "/r /f /t 0" -WindowStyle Hidden
})
`$form.Controls.Add(`$restartButton)

# Timer for countdown
`$script:remainingSeconds = `$CountdownSeconds
`$timer = New-Object System.Windows.Forms.Timer
`$timer.Interval = 1000
`$timer.Add_Tick({
    `$script:remainingSeconds--
    `$hours = [math]::Floor(`$script:remainingSeconds / 3600)
    `$minutes = [math]::Floor((`$script:remainingSeconds % 3600) / 60)
    `$seconds = `$script:remainingSeconds % 60
    `$countdownLabel.Text = "{0:D2}:{1:D2}:{2:D2}" -f `$hours, `$minutes, `$seconds
    `$progressBar.Value = `$CountdownSeconds - `$script:remainingSeconds
    
    if (`$script:remainingSeconds -le 0) {
        `$timer.Stop()
        try {
            Start-Process -FilePath "`$env:SystemRoot\System32\shutdown.exe" -ArgumentList "/r /f /t 0" -WindowStyle Hidden
        } catch {}
    }
})

# Initialize display
`$hours = [math]::Floor(`$CountdownSeconds / 3600)
`$minutes = [math]::Floor((`$CountdownSeconds % 3600) / 60)
`$secs = `$CountdownSeconds % 60
`$countdownLabel.Text = "{0:D2}:{1:D2}:{2:D2}" -f `$hours, `$minutes, `$secs

`$timer.Start()
`$form.ShowDialog()
"@

    # Save the countdown script to a temporary file
    $CountdownScriptPath = "$env:TEMP\ForceRebootCountdown.ps1"
    $CountdownScript | Out-File -FilePath $CountdownScriptPath -Encoding UTF8 -Force
    
    # Start the countdown script in a new process
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$CountdownScriptPath`"" -WindowStyle Hidden
        Write-Log -Message "Force reboot countdown window started successfully"
    }
    catch {
        Write-Log -Level Error -Message "Failed to start countdown window: $($_.Exception.Message)"
        # Fallback to immediate OS shutdown timer
        try {
            Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" -ArgumentList "/r /f /t $CountdownSeconds /c `"Forced reboot scheduled`"" -WindowStyle Hidden
            Write-Log -Message "Fallback: OS shutdown timer set for $CountdownSeconds seconds"
        }
        catch {
            Write-Log -Level Error -Message "Failed to set shutdown timer: $($_.Exception.Message)"
        }
    }
}

# Create Get-WindowsVersion function
# This is used to determine if the script is running on Windows 10 or not
function Get-WindowsVersion() {
    $OS = Get-CimInstance Win32_OperatingSystem
    if (($OS.Version -like "10.0.*") -AND ($OS.ProductType -eq 1)) {
        Write-Log -Message "Running supported version of Windows. Windows 10 and workstation OS detected"
        $true
    }
    elseif ($OS.Version -notlike "10.0.*") {
        Write-Log -Level Error -Message "Not running supported version of Windows"
        $false
    }
    else {
        Write-Log -Level Error -Message "Not running supported version of Windows"
        $false
    }
}

# Create Windows Push Notification function.
# This is testing if toast notifications generally are disabled within Windows 10
function Test-WindowsPushNotificationsEnabled() {
    $ToastEnabledKey = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name ToastEnabled -ErrorAction Ignore).ToastEnabled
    if ($ToastEnabledKey -eq "1") {
        Write-Log -Message "Toast notifications for the logged on user are enabled in Windows"
        $true
    }
    elseif ($ToastEnabledKey -eq "0") {
        Write-Log -Level Error -Message "Toast notifications for the logged on user are not enabled in Windows. The script will try to enable toast notifications for the logged on user"
        $false
    }
}

# Create Enable-WindowsPushNotifications
# This is used to re-enable toast notifications if the user disabled them generally in Windows
function Enable-WindowsPushNotifications() {
    $ToastEnabledKeyPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"
    Write-Log -Message "Trying to enable toast notifications for the logged on user"
    try {
        Set-ItemProperty -Path $ToastEnabledKeyPath -Name ToastEnabled -Value 1 -Force
        Get-Service -Name WpnUserService** | Restart-Service -Force
        Write-Log -Message "Successfully enabled toast notifications for the logged on user"
    }
    catch {
        Write-Log -Level Error -Message "Failed to enable toast notifications for the logged on user. Toast notifications will probably not be displayed"
    }
}

# Create Display-ToastNotification function
# Updated in version 2.2.0
function Display-ToastNotification() {
    try {
        if ($isSystem -eq $true) {
            Write-Log -Message "Confirmed SYSTEM context before displaying toast"
            # is running under SYSTEM context
            # show notification to all logged on users
            & (Join-Path -Path $global:CustomScriptsPath -ChildPath "InvokePSScriptAsUser.ps1") "$PSCommandPath" "$Config"
        } 
        else {
            Write-Log -Message "Confirmed USER context before displaying toast"
            # is running under user context
            $Load = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
            $Load = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
            # Load the notification into the required format
            $ToastXml = New-Object -TypeName Windows.Data.Xml.Dom.XmlDocument
            $ToastXml.LoadXml($Toast.OuterXml)
            # Display the toast notification
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($App).Show($ToastXml)
        }
        Write-Log -Message "All good. Toast notification was displayed"
        # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
        Write-Output "All good. Toast notification was displayed"
        if ($CustomAudio -eq "True") {
            Invoke-Command -ScriptBlock {
                Add-Type -AssemblyName System.Speech
                $speak = New-Object System.Speech.Synthesis.SpeechSynthesizer
                sleep 1.25
                $speak.SelectVoiceByHints("female",65)
                $speak.Speak($CustomAudioTextToSpeech)
                $speak.Dispose()
            }    
        }
        # Saving time stamp of when toast notification was run into registry
        Save-NotificationLastRunTime
        
        # Check if force reboot countdown should be started after toast
        if ($ForceRebootAfterToast -eq "True") {
            $CountdownSeconds = [int]$ForceRebootCountdownMinutes * 60
            Write-Log -Message "ForceRebootAfterToast enabled. Starting $ForceRebootCountdownMinutes minute countdown."
            Start-ForceRebootCountdown -CountdownSeconds $CountdownSeconds -CompanyName $AttributionText
        }
        
        Exit 0
    }
    catch { 
        Write-Log -Message "Something went wrong when displaying the toast notification" -Level Error
        Write-Log -Message "Make sure the script is running as the logged on user" -Level Error
        # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
        Write-Output "Something went wrong when displaying the toast notification. Make sure the script is running as the logged on user"
        Exit 1 
    }
}

# Create Test-NTSystem function
# Testing to see if the script is being run as SYSTEM
# Updated in version 2.2.0
function Test-NTSystem() {  
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($currentUser.IsSystem -eq $true) {
        Write-Log -Message "Script is initially running in SYSTEM context. Please be vary, that this has limitations and may not work!"
        $true  
    }
    elseif ($currentUser.IsSystem -eq $false) {
        Write-Log -Message "Script is initially running in USER context"
        $false
    }
}

# Create Write-CustomActionRegistry function
# This function creates custom protocols for the logged on user in HKCU. 
# This will remove the need to create the protocols outside of the toast notification script
# HUGE shout-out to Chad Brower // @Brower_Cha on Twitter
# Added in version 2.0.0
function Write-CustomActionRegistry() {
    [CmdletBinding()]
    param (
        [Parameter(Position="0")]
        [ValidateSet("ToastRunApplicationID","ToastRunPackageID","ToastRunUpdateID","ToastReboot")]
        [string]$ActionType,
        [Parameter(Position="1")]
        [string]$RegCommandPath = $global:CustomScriptsPath
    )
    Write-Log -Message "Running Write-CustomActionRegistry function: $ActionType"
    switch ($ActionType) {
        ToastReboot { 
            # Build out registry for custom action for rebooting the device via the action button
            try { 
                New-Item "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name 'URL Protocol' -Value '' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name '(default)' -Value "URL:$($ActionType) Protocol" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                $RegCommandValue = $RegCommandPath  + '\' + "$($ActionType).cmd"
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Name '(default)' -Value $RegCommandValue -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                Write-Log -Level Error "Failed to create the $ActionType custom protocol in HKCU\Software\Classes. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
        }
        ToastRunUpdateID { 
            # Build out registry for custom action for running software update via the action button
            try { 
                New-Item "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name 'URL Protocol' -Value '' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name '(default)' -Value "URL:$($ActionType) Protocol" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                $RegCommandValue = $RegCommandPath  + '\' + "$($ActionType).cmd"
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Name '(default)' -Value $RegCommandValue -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                Write-Log -Level Error "Failed to create the $ActionType custom protocol in HKCU\Software\Classes. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
        }
        ToastRunPackageID { 
            # Build out registry for custom action for running packages and task sequences via the action button
            try { 
                New-Item "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name 'URL Protocol' -Value '' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name '(default)' -Value "URL:$($ActionType) Protocol" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                $RegCommandValue = $RegCommandPath  + '\' + "$($ActionType).cmd"
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Name '(default)' -Value $RegCommandValue -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                Write-Log -Level Error "Failed to create the $ActionType custom protocol in HKCU\Software\Classes. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
        }
        ToastRunApplicationID { 
            # Build out registry for custom action for running applications via the action button
            try { 
                New-Item "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name 'URL Protocol' -Value '' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name '(default)' -Value "URL:$($ActionType) Protocol" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                $RegCommandValue = $RegCommandPath  + '\' + "$($ActionType).cmd"
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Name '(default)' -Value $RegCommandValue -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                Write-Log -Level Error "Failed to create the $ActionType custom protocol in HKCU\Software\Classes. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
        }
    }
}

# Create Write-CustomActionScript function
# This function creates the custom scripts in ProgramData\ToastNotificationScript which is used to carry out custom protocol actions
# HUGE shout-out to Chad Brower // @Brower_Cha on Twitter
# Added in version 2.0.0
# Updated in version 2.2.0
function Write-CustomActionScript() {
    [CmdletBinding()]
    param (
        [Parameter(Position="0")]
        [ValidateSet("ToastRunApplicationID","ToastRunPackageID","ToastRunUpdateID","ToastReboot","InvokePSScriptAsUser")]
        [string]$Type,
        [Parameter(Position="1")]
        [String]$Path = $global:CustomScriptsPath
    )
    Write-Log -Message "Running Write-CustomActionScript function: $Type"
    switch ($Type) {
        # Create custom scripts for running software updates via the action button
        ToastRunUpdateID {
            try {
                $CMDFileName = $Type + '.cmd'
                $CMDFilePath = $Path + '\' + $CMDFileName
                try {
                    New-item -Path $Path -Name $CMDFileName -Force -OutVariable PathInfo | Out-Null
                }
                catch { 
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -NoProfile -WindowStyle Hidden -File `"$global:CustomScriptsPath\ToastRunUpdateID.ps1`""
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
            }
            catch {
                Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
            try {
                $PS1FileName = $Type + '.ps1'
                $PS1FilePath = $Path + '\' + $PS1FileName
                try {
                    New-item -Path $Path -Name $PS1FileName -Force -OutVariable PathInfo | Out-Null
                }
                catch { 
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = @'
$RegistryPath = "HKCU:\SOFTWARE\ToastNotificationScript"
$UpdateID = (Get-ItemProperty -Path $RegistryPath -Name "RunUpdateID").RunUpdateID
$TestUpdateID = Get-WmiObject -Namespace ROOT\ccm\ClientSDK -Query "SELECT * FROM CCM_SoftwareUpdate WHERE UpdateID = '$UpdateID'"
if (-NOT[string]::IsNullOrEmpty($TestUpdateID)) {
    Invoke-WmiMethod -Namespace ROOT\ccm\ClientSDK -Class CCM_SoftwareUpdatesManager -Name InstallUpdates -ArgumentList (,$TestUpdateID)
    if (Test-Path -Path "$env:windir\CCM\ClientUX\SCClient.exe") { Start-Process -FilePath "$env:windir\CCM\ClientUX\SCClient.exe" -ArgumentList "SoftwareCenter:Page=Updates" -WindowStyle Maximized }
}
exit 0
'@
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .ps1 script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
            }
            catch {
                Write-Log -Level Error "Failed to create the custom .ps1 script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
            # Do not run another type; break
            Break
        }
        # Create custom script for rebooting the device directly from the action button
        ToastReboot {
            try {
                $CMDFileName = $Type + '.cmd'
                $CMDFilePath = $Path + '\' + $CMDFileName
                try {
                    New-item -Path $Path -Name $CMDFileName -Force -OutVariable PathInfo | Out-Null
                 }
                catch {
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"              
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = 'shutdown /r /t 0 /d p:0:0 /c "Toast Notification Reboot"'
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
            }
            catch {
                Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
            # Do not run another type; break
            Break
        }
        # Script output updated in 2.0.1 to dynamically pick up the Program ID. 
        # Previously this was hard coded to '*', making it work for task sequences only. Now also works for regular packages (only one program).
        # Create custom scripts to run packages and task sequences directly from the action button
        ToastRunPackageID {
            try {
                $CMDFileName = $Type + '.cmd'
                $CMDFilePath = $Path + '\' + $CMDFileName
                try {
                    New-item -Path $Path -Name $CMDFileName -Force -OutVariable PathInfo | Out-Null
                }
                catch { 
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -NoProfile -WindowStyle Hidden -File `"$global:CustomScriptsPath\ToastRunPackageID.ps1`""
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
            }
            catch {
                Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
            try {
                $PS1FileName = $Type + '.ps1'
                $PS1FilePath = $Path + '\' + $PS1FileName
                try {
                    New-item -Path $Path -Name $PS1FileName -Force -OutVariable PathInfo | Out-Null
                }
                catch { 
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = @'
$RegistryPath = "HKCU:\SOFTWARE\ToastNotificationScript"
$PackageID = (Get-ItemProperty -Path $RegistryPath -Name "RunPackageID").RunPackageID
$TestPackageID = Get-WmiObject -Namespace ROOT\ccm\ClientSDK -Query "SELECT * FROM CCM_Program where PackageID = '$PackageID'"
if (-NOT[string]::IsNullOrEmpty($TestPackageID)) {
    $ProgramID = $TestPackageID.ProgramID
    ([wmiclass]'ROOT\ccm\ClientSDK:CCM_ProgramsManager').ExecuteProgram($ProgramID,$PackageID)
    if (Test-Path -Path "$env:windir\CCM\ClientUX\SCClient.exe") { Start-Process -FilePath "$env:windir\CCM\ClientUX\SCClient.exe" -ArgumentList "SoftwareCenter:Page=OSD" -WindowStyle Maximized }
}
exit 0
'@
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .ps1 script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
            }
            catch {
                Write-Log -Level Error "Failed to create the custom .ps1 script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
            # Do not run another type; break
            Break
        }
        InvokePSScriptAsUser {
            # create ps1 script that can invoke another script under all logged users (if started as SYSTEM)
            try {
                $PS1FileName = 'InvokePSScriptAsUser.ps1'
                try {
                    New-Item -Path $Path -Name $PS1FileName -Force -OutVariable PathInfo | Out-Null
                } 
                catch {
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = @'
param($File, $argument)

$Source = @"
using System;
using System.Runtime.InteropServices;

namespace Runasuser
{
    public static class ProcessExtensions
    {
        #region Win32 Constants

        private const int CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        private const int CREATE_NO_WINDOW = 0x08000000;

        private const int CREATE_NEW_CONSOLE = 0x00000010;

        private const uint INVALID_SESSION_ID = 0xFFFFFFFF;
        private static readonly IntPtr WTS_CURRENT_SERVER_HANDLE = IntPtr.Zero;

        #endregion

        #region DllImports

        [DllImport("advapi32.dll", EntryPoint = "CreateProcessAsUser", SetLastError = true, CharSet = CharSet.Ansi, CallingConvention = CallingConvention.StdCall)]
        private static extern bool CreateProcessAsUser(
            IntPtr hToken,
            String lpApplicationName,
            String lpCommandLine,
            IntPtr lpProcessAttributes,
            IntPtr lpThreadAttributes,
            bool bInheritHandle,
            uint dwCreationFlags,
            IntPtr lpEnvironment,
            String lpCurrentDirectory,
            ref STARTUPINFO lpStartupInfo,
            out PROCESS_INFORMATION lpProcessInformation);

        [DllImport("advapi32.dll", EntryPoint = "DuplicateTokenEx")]
        private static extern bool DuplicateTokenEx(
            IntPtr ExistingTokenHandle,
            uint dwDesiredAccess,
            IntPtr lpThreadAttributes,
            int TokenType,
            int ImpersonationLevel,
            ref IntPtr DuplicateTokenHandle);

        [DllImport("userenv.dll", SetLastError = true)]
        private static extern bool CreateEnvironmentBlock(ref IntPtr lpEnvironment, IntPtr hToken, bool bInherit);

        [DllImport("userenv.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr hSnapshot);

        [DllImport("kernel32.dll")]
        private static extern uint WTSGetActiveConsoleSessionId();

        [DllImport("Wtsapi32.dll")]
        private static extern uint WTSQueryUserToken(uint SessionId, ref IntPtr phToken);

        [DllImport("wtsapi32.dll", SetLastError = true)]
        private static extern int WTSEnumerateSessions(
            IntPtr hServer,
            int Reserved,
            int Version,
            ref IntPtr ppSessionInfo,
            ref int pCount);

        #endregion

        #region Win32 Structs

        private enum SW
        {
            SW_HIDE = 0,
            SW_SHOWNORMAL = 1,
            SW_NORMAL = 1,
            SW_SHOWMINIMIZED = 2,
            SW_SHOWMAXIMIZED = 3,
            SW_MAXIMIZE = 3,
            SW_SHOWNOACTIVATE = 4,
            SW_SHOW = 5,
            SW_MINIMIZE = 6,
            SW_SHOWMINNOACTIVE = 7,
            SW_SHOWNA = 8,
            SW_RESTORE = 9,
            SW_SHOWDEFAULT = 10,
            SW_MAX = 10
        }

        private enum WTS_CONNECTSTATE_CLASS
        {
            WTSActive,
            WTSConnected,
            WTSConnectQuery,
            WTSShadow,
            WTSDisconnected,
            WTSIdle,
            WTSListen,
            WTSReset,
            WTSDown,
            WTSInit
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public uint dwProcessId;
            public uint dwThreadId;
        }

        private enum SECURITY_IMPERSONATION_LEVEL
        {
            SecurityAnonymous = 0,
            SecurityIdentification = 1,
            SecurityImpersonation = 2,
            SecurityDelegation = 3,
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct STARTUPINFO
        {
            public int cb;
            public String lpReserved;
            public String lpDesktop;
            public String lpTitle;
            public uint dwX;
            public uint dwY;
            public uint dwXSize;
            public uint dwYSize;
            public uint dwXCountChars;
            public uint dwYCountChars;
            public uint dwFillAttribute;
            public uint dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        private enum TOKEN_TYPE
        {
            TokenPrimary = 1,
            TokenImpersonation = 2
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct WTS_SESSION_INFO
        {
            public readonly UInt32 SessionID;

            [MarshalAs(UnmanagedType.LPStr)]
            public readonly String pWinStationName;

            public readonly WTS_CONNECTSTATE_CLASS State;
        }

        #endregion

        // Gets the user token from the currently active session
        private static bool GetSessionUserToken(ref IntPtr phUserToken)
        {
            var bResult = false;
            var hImpersonationToken = IntPtr.Zero;
            var activeSessionId = INVALID_SESSION_ID;
            var pSessionInfo = IntPtr.Zero;
            var sessionCount = 0;

            // Get a handle to the user access token for the current active session.
            if (WTSEnumerateSessions(WTS_CURRENT_SERVER_HANDLE, 0, 1, ref pSessionInfo, ref sessionCount) != 0)
            {
                var arrayElementSize = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
                var current = pSessionInfo;

                for (var i = 0; i < sessionCount; i++)
                {
                    var si = (WTS_SESSION_INFO)Marshal.PtrToStructure((IntPtr)current, typeof(WTS_SESSION_INFO));
                    current += arrayElementSize;

                    if (si.State == WTS_CONNECTSTATE_CLASS.WTSActive)
                    {
                        activeSessionId = si.SessionID;
                    }
                }
            }

            // If enumerating did not work, fall back to the old method
            if (activeSessionId == INVALID_SESSION_ID)
            {
                activeSessionId = WTSGetActiveConsoleSessionId();
            }

            if (WTSQueryUserToken(activeSessionId, ref hImpersonationToken) != 0)
            {
                // Convert the impersonation token to a primary token
                bResult = DuplicateTokenEx(hImpersonationToken, 0, IntPtr.Zero,
                    (int)SECURITY_IMPERSONATION_LEVEL.SecurityImpersonation, (int)TOKEN_TYPE.TokenPrimary,
                    ref phUserToken);

                CloseHandle(hImpersonationToken);
            }

            return bResult;
        }

        public static bool StartProcessAsCurrentUser(string appPath, string cmdLine = null, string workDir = null, bool visible = true)
        {
            var hUserToken = IntPtr.Zero;
            var startInfo = new STARTUPINFO();
            var procInfo = new PROCESS_INFORMATION();
            var pEnv = IntPtr.Zero;
            int iResultOfCreateProcessAsUser;

            startInfo.cb = Marshal.SizeOf(typeof(STARTUPINFO));

            try
            {
                if (!GetSessionUserToken(ref hUserToken))
                {
                    throw new Exception("StartProcessAsCurrentUser: GetSessionUserToken failed.");
                }

                uint dwCreationFlags = CREATE_UNICODE_ENVIRONMENT | (uint)(visible ? CREATE_NEW_CONSOLE : CREATE_NO_WINDOW);
                startInfo.wShowWindow = (short)(visible ? SW.SW_SHOW : SW.SW_HIDE);
                startInfo.lpDesktop = "winsta0\\default";

                if (!CreateEnvironmentBlock(ref pEnv, hUserToken, false))
                {
                    throw new Exception("StartProcessAsCurrentUser: CreateEnvironmentBlock failed.");
                }

                if (!CreateProcessAsUser(hUserToken,
                    appPath, // Application Name
                    cmdLine, // Command Line
                    IntPtr.Zero,
                    IntPtr.Zero,
                    false,
                    dwCreationFlags,
                    pEnv,
                    workDir, // Working directory
                    ref startInfo,
                    out procInfo))
                {
                    iResultOfCreateProcessAsUser = Marshal.GetLastWin32Error();
                    throw new Exception("StartProcessAsCurrentUser: CreateProcessAsUser failed.  Error Code -" + iResultOfCreateProcessAsUser);
                }

                iResultOfCreateProcessAsUser = Marshal.GetLastWin32Error();
            }
            finally
            {
                CloseHandle(hUserToken);
                if (pEnv != IntPtr.Zero)
                {
                    DestroyEnvironmentBlock(pEnv);
                }
                CloseHandle(procInfo.hThread);
                CloseHandle(procInfo.hProcess);
            }

            return true;
        }

    }
}
"@

# Load the custom type
Add-Type -ReferencedAssemblies 'System', 'System.Runtime.InteropServices' -TypeDefinition $Source -Language CSharp -ErrorAction Stop

# Run PS as user completely hidden (no console window)
[Runasuser.ProcessExtensions]::StartProcessAsCurrentUser("$env:windir\System32\WindowsPowerShell\v1.0\Powershell.exe", " -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$File`" $argument", $null, $false) | Out-Null
'@
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                } 
                catch {
                    Write-Log -Level Error "Failed to create the .ps1 script for $Type. Show notification if run under SYSTEM might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }

            } 
            catch {
                Write-Log -Level Error "Failed to create the .ps1 script for $Type. Show notification if run under SYSTEM might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
        }
    }
}

# Create function to retrieve the last run time of the notification
# Added in version 2.2.0
function Get-NotificationLastRunTime() {
    $LastRunTime = (Get-ItemProperty $global:RegistryPath -Name LastRunTime -ErrorAction Ignore).LastRunTime
    $CurrentTime = Get-Date -Format s
    if (-NOT[string]::IsNullOrEmpty($LastRunTime)) {
        $Difference = ([datetime]$CurrentTime - ([datetime]$LastRunTime)) 
        $MinutesSinceLastRunTime = [math]::Round($Difference.TotalMinutes)
        Write-Log -Message "Toast notification was previously displayed $MinutesSinceLastRunTime minutes ago"
        $MinutesSinceLastRunTime
    }
}

# Create function to store the timestamp of the notification execution
# Added in version 2.2.0
function Save-NotificationLastRunTime() {
    $RunTime = Get-Date -Format s
    if (-NOT(Get-ItemProperty -Path $global:RegistryPath -Name LastRunTime -ErrorAction Ignore)) {
        New-ItemProperty -Path $global:RegistryPath -Name LastRunTime -Value $RunTime -Force | Out-Null
    }
    else {
        Set-ItemProperty -Path $global:RegistryPath -Name LastRunTime -Value $RunTime -Force | Out-Null
    }
}
# Create function to register custom notification app
# Added in version 2.3.0
# Bits and pieces kindly borrowed from Mr. Trevor Jones: smsagent.blog
function Register-CustomNotificationApp($fAppID,$fAppDisplayName) {
    Write-Log -Message "Running Register-NotificationApp function"
    $AppID = $fAppID
    $AppDisplayName = $fAppDisplayName
    # This removes the option to disable to toast notification
    [int]$ShowInSettings = 0
    # Adds an icon next to the display name of the notifyhing app
    [int]$IconBackgroundColor = 0
    $IconUri = "%SystemRoot%\ImmersiveControlPanel\images\logo.png"
    # Moved this into HKCU, in order to modify this directly from the toast notification running in user context
    $AppRegPath = "HKCU:\Software\Classes\AppUserModelId"
    $RegPath = "$AppRegPath\$AppID"
    try {
        if (-NOT(Test-Path $RegPath)) {
            New-Item -Path $AppRegPath -Name $AppID -Force | Out-Null
        }
        $DisplayName = Get-ItemProperty -Path $RegPath -Name DisplayName -ErrorAction SilentlyContinue | Select -ExpandProperty DisplayName -ErrorAction SilentlyContinue
        if ($DisplayName -ne $AppDisplayName) {
            New-ItemProperty -Path $RegPath -Name DisplayName -Value $AppDisplayName -PropertyType String -Force | Out-Null
        }
        $ShowInSettingsValue = Get-ItemProperty -Path $RegPath -Name ShowInSettings -ErrorAction SilentlyContinue | Select -ExpandProperty ShowInSettings -ErrorAction SilentlyContinue
        if ($ShowInSettingsValue -ne $ShowInSettings) {
            New-ItemProperty -Path $RegPath -Name ShowInSettings -Value $ShowInSettings -PropertyType DWORD -Force | Out-Null
        }
        $IconUriValue = Get-ItemProperty -Path $RegPath -Name IconUri -ErrorAction SilentlyContinue | Select -ExpandProperty IconUri -ErrorAction SilentlyContinue
        if ($IconUriValue -ne $IconUri) {
            New-ItemProperty -Path $RegPath -Name IconUri -Value $IconUri -PropertyType ExpandString -Force | Out-Null
        }
        $IconBackgroundColorValue = Get-ItemProperty -Path $RegPath -Name IconBackgroundColor -ErrorAction SilentlyContinue | Select -ExpandProperty IconBackgroundColor -ErrorAction SilentlyContinue
        if ($IconBackgroundColorValue -ne $IconBackgroundColor) {
            New-ItemProperty -Path $RegPath -Name IconBackgroundColor -Value $IconBackgroundColor -PropertyType ExpandString -Force | Out-Null
        }
        Write-Log "Created registry entries for custom notification app: $fAppDisplayName"
    }
    catch {
        Write-Log -Message "Failed to create one or more registry entries for the custom notification app" -Level Error
        Write-Log -Message "Toast Notifications are usually not displayed if the notification app does not exist" -Level Error
    }
}
#endregion

#region Variables
# Setting global script version
$global:ScriptVersion = "2.3.0-ML"
# Setting executing directory
$global:ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
# Setting global custom action script location
$global:CustomScriptsPath = "$env:APPDATA\ToastNotificationScript\Scripts"
# Setting global registry path
$global:RegistryPath = "HKCU:\SOFTWARE\ToastNotificationScript"
# Get running OS build
$RunningOS = try { Get-CimInstance -Class Win32_OperatingSystem | Select-Object BuildNumber } catch { Write-Log -Level Error -Message "Failed to get running OS build. This is used with the OSUpgrade option, which now might not work properly" }
# Get user culture for multilanguage support
$userCulture = try { (Get-Culture).Name } catch { Write-Log -Level Error -Message "Failed to get users local culture. This is used with the multilanguage option, which now might not work properly" }
# Setting the default culture to en-US. This will be the default language if MultiLanguageSupport is not enabled in the config
$defaultUserCulture = "en-US"
# Temporary location for images if images are hosted online on blob storage or similar
$LogoImageTemp = "$env:TEMP\ToastLogoImage.jpg"
$HeroImageTemp = "$env:TEMP\ToastHeroImage.jpg"
# Setting path to local images
$ImagesPath = "file:///$global:ScriptPath/Images"
#endregion

#region Main Process
# Create the global registry path for the toast notification script
if (-NOT(Test-Path -Path $global:RegistryPath)) {
    Write-Log -Message "ToastNotificationScript registry path not found. Creating it: $global:RegistryPath"
    try {
        New-Item -Path $global:RegistryPath -Force | Out-Null
    }
    catch { 
        Write-Log -Message "Failed to create the ToastNotificationScript registry path: $global:RegistryPath" -Level Error
        Write-Log -Message "This is required. Script will now exit" -Level Error
        Exit 1
    }
}

# Create the global path for the custom action scipts used by the custom action protocols
if (-NOT(Test-Path -Path $global:CustomScriptsPath)) {
    Write-Log -Message "CustomScriptPath not found. Creating it: $global:CustomScriptsPath"
    try {
        New-item -Path $global:CustomScriptsPath -ItemType Directory -Force | Out-Null
    }
    catch {
        Write-Log -Level Error -Message "Failed to create the CustomScriptPath folder: $global:CustomScriptsPath"
        Write-Log -Message "This is required. Script will now exit" -Level Error
        Exit 1
    }
}

# Testing for prerequisites
# Test if the script is being run on a supported version of Windows. Windows 10 AND workstation OS is required
$SupportedWindowsVersion = Get-WindowsVersion
if ($SupportedWindowsVersion -eq $False) {
    Write-Log -Message "Aborting script" -Level Error
    Exit 1
}

# Testing if script is being run as SYSTEM.
$isSystem = Test-NTSystem
if ($isSystem -eq $true) {
    Write-Log -Message "The toast notification script is being run as SYSTEM. This is not recommended, but can be required in certain situations"
    Write-Log -Message "Scripts and log file are now located in: C:\Windows\System32\config\systemprofile\AppData\Roaming\ToastNotificationScript"
}

# Testing for blockers of toast notifications in Windows
$WindowsPushNotificationsEnabled = Test-WindowsPushNotificationsEnabled
if ($WindowsPushNotificationsEnabled -eq $False) {
    Enable-WindowsPushNotifications
}
# If no config file is set as parameter, use the default. 
# Default is executing directory. In this case, the config-toast.xml must exist in same directory as the New-ToastNotification.ps1 file
if (-NOT($Config)) {
    Write-Log -Message "No config file set as parameter. Using local config file"
    $Config = Join-Path ($global:ScriptPath) "config-toast.xml"
}

# Load config.xml
# Catering for when config.xml is hosted online on blob storage or similar
# Loading the config.xml file here is relevant for when used with Endpoint Analytics in Intune
if (($Config.StartsWith("https://")) -OR ($Config.StartsWith("http://"))) {
    Write-Log -Message "Specified config file seems hosted [online]. Treating it accordingly"
    try { $testOnlineConfig = Invoke-WebRequest -Uri $Config -UseBasicParsing } catch { <# nothing to see here. Used to make webrequest silent #> }
    if ($testOnlineConfig.StatusDescription -eq "OK") {
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.Encoding = [System.Text.Encoding]::UTF8
            $Xml = [xml]$webClient.DownloadString($Config)
            Write-Log -Message "Successfully loaded $Config"
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Log -Message "Error, could not read $Config" -Level Error
            Write-Log -Message "Error message: $ErrorMessage" -Level Error
            # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
            Write-Output "Error, could not read $Config. Error message: $ErrorMessage"
            Exit 1
        }
    }
    else {
        Write-Log -Level Error -Message "The provided URL to the config does not reply or does not come back OK"
        # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
        Write-Output "The provided URL to the config does not reply or does not come back OK"
        Exit 1
    }
}

# Catering for when config.xml is hosted locally or on fileshare
elseif (-NOT($Config.StartsWith("https://")) -OR (-NOT($Config.StartsWith("http://")))) {
    Write-Log -Message "Specified config file seems hosted [locally or fileshare]. Treating it accordingly"
    if (Test-Path -Path $Config) {
        try { 
            $Xml = [xml](Get-Content -Path $Config -Encoding UTF8)
            Write-Log -Message "Successfully loaded $Config"
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Log -Message "Error, could not read $Config" -Level Error
            Write-Log -Message "Error message: $ErrorMessage" -Level Error
            Exit 1
        }
    }
    else {
        Write-Log -Level Error -Message "No config file found on the specified location [locally or fileshare]"
        Exit 1
    }
}
else {
    Write-Log -Level Error -Message "Something about the config file is completely off"
    # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
    Write-Output "Something about the config file is completely off"
    Exit 1
}

# Load xml content into variables
if(-NOT[string]::IsNullOrEmpty($Xml)) {
    try {
        Write-Log -Message "Loading xml content from $Config into variables"
        # Load Toast Notification features (reboot-related only)
        $ToastEnabled = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'Toast'} | Select-Object -ExpandProperty 'Enabled'
        $PendingRebootUptime = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'PendingRebootUptime'} | Select-Object -ExpandProperty 'Enabled'
        $PendingRebootCheck = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'PendingRebootCheck'} | Select-Object -ExpandProperty 'Enabled'
        
        # Load Toast Notification options (reboot-related only)
        $PendingRebootUptimeTextEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'PendingRebootUptimeText'} | Select-Object -ExpandProperty 'Enabled'
        $MaxUptimeDays = $Xml.Configuration.Option | Where-Object {$_.Name -like 'MaxUptimeDays'} | Select-Object -ExpandProperty 'Value'
        $PendingRebootCheckTextEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'PendingRebootCheckText'} | Select-Object -ExpandProperty 'Enabled'
        
        # Force reboot options for Day 10+ scenarios
        $ForceRebootAfterToast = $Xml.Configuration.Option | Where-Object {$_.Name -like 'ForceRebootAfterToast'} | Select-Object -ExpandProperty 'Enabled'
        $ForceRebootCountdownMinutes = $Xml.Configuration.Option | Where-Object {$_.Name -like 'ForceRebootCountdownMinutes'} | Select-Object -ExpandProperty 'Value'
        
        # Creating Scripts and Protocols
        $CreateScriptsProtocolsEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'CreateScriptsAndProtocols'} | Select-Object -ExpandProperty 'Enabled'
        
        # Added in version 2.2.0
        $LimitToastToRunEveryMinutesEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'LimitToastToRunEveryMinutes'} | Select-Object -ExpandProperty 'Enabled'
        $LimitToastToRunEveryMinutesValue = $Xml.Configuration.Option | Where-Object {$_.Name -like 'LimitToastToRunEveryMinutes'} | Select-Object -ExpandProperty 'Value'
        
        # Custom app doing the notification
        $CustomAppEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'CustomNotificationApp'} | Select-Object -ExpandProperty 'Enabled'
        $CustomAppValue = $Xml.Configuration.Option | Where-Object {$_.Name -like 'CustomNotificationApp'} | Select-Object -ExpandProperty 'Value'
        $SCAppName = $Xml.Configuration.Option | Where-Object {$_.Name -like 'UseSoftwareCenterApp'} | Select-Object -ExpandProperty 'Name'
        $SCAppStatus = $Xml.Configuration.Option | Where-Object {$_.Name -like 'UseSoftwareCenterApp'} | Select-Object -ExpandProperty 'Enabled'
        $PSAppName = $Xml.Configuration.Option | Where-Object {$_.Name -like 'UsePowershellApp'} | Select-Object -ExpandProperty 'Name'
        $PSAppStatus = $Xml.Configuration.Option | Where-Object {$_.Name -like 'UsePowershellApp'} | Select-Object -ExpandProperty 'Enabled'
        $CustomAudio = $Xml.Configuration.Option | Where-Object {$_.Name -like 'CustomAudio'} | Select-Object -ExpandProperty 'Enabled'
        $LogoImageFileName = $Xml.Configuration.Option | Where-Object {$_.Name -like 'LogoImageName'} | Select-Object -ExpandProperty 'Value'
        $HeroImageFileName = $Xml.Configuration.Option | Where-Object {$_.Name -like 'HeroImageName'} | Select-Object -ExpandProperty 'Value'
        # Rewriting image variables to cater for images being hosted online, as well as being hosted locally. 
        # Needed image including path in one variable
        if ((-NOT[string]::IsNullOrEmpty($LogoImageFileName)) -OR (-NOT[string]::IsNullOrEmpty($HeroImageFileName)))  {
            $LogoImage = $ImagesPath + "/" + $LogoImageFileName
            $HeroImage = $ImagesPath + "/" + $HeroImageFileName
        }
        $Scenario = $Xml.Configuration.Option | Where-Object {$_.Name -like 'Scenario'} | Select-Object -ExpandProperty 'Type'
        $Action = $Xml.Configuration.Option | Where-Object {$_.Name -like 'Action'} | Select-Object -ExpandProperty 'Value'
        $Action1 = $Xml.Configuration.Option | Where-Object {$_.Name -like 'Action1'} | Select-Object -ExpandProperty 'Value'
        $Action2 = $Xml.Configuration.Option | Where-Object {$_.Name -like 'Action2'} | Select-Object -ExpandProperty 'Value'
        $GreetGivenName = $Xml.Configuration.Text | Where-Object {$_.Option -like 'GreetGivenName'} | Select-Object -ExpandProperty 'Enabled'
        $MultiLanguageSupport = $Xml.Configuration.Text | Where-Object {$_.Option -like 'MultiLanguageSupport'} | Select-Object -ExpandProperty 'Enabled'
        # Load Toast Notification buttons
        $ActionButton1Enabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'ActionButton1'} | Select-Object -ExpandProperty 'Enabled'
        $ActionButton2Enabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'ActionButton2'} | Select-Object -ExpandProperty 'Enabled'
        $DismissButtonEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'DismissButton'} | Select-Object -ExpandProperty 'Enabled'
        $SnoozeButtonEnabled = $Xml.Configuration.Option | Where-Object {$_.Name -like 'SnoozeButton'} | Select-Object -ExpandProperty 'Enabled'
        # Multi language support
        if ($MultiLanguageSupport -eq "True") {
            Write-Log -Message "MultiLanguageSupport set to True. Current language culture is $userCulture. Checking for language support"
            # Check config xml if language support is added for the users culture
            if (-NOT[string]::IsNullOrEmpty($xml.Configuration.$userCulture)) {
                Write-Log -Message "Support for the users language culture found, localizing text using $userCulture"
                $XmlLang = $xml.Configuration.$userCulture
            }
            # Else fallback to using default language "en-US"
            elseif (-NOT[string]::IsNullOrEmpty($xml.Configuration.$defaultUserCulture)) {
                Write-Log -Message "No support for the users language culture found, using $defaultUserCulture as default fallback language"
                $XmlLang = $xml.Configuration.$defaultUserCulture
            }
        }
        # If multilanguagesupport is set to False use default language "en-US"
        elseif ($MultiLanguageSupport -eq "False") {
            $XmlLang = $xml.Configuration.$defaultUserCulture
        }
        # Regardless of whatever might happen, always use "en-US" as language
        else {
            $XmlLang = $xml.Configuration.$defaultUserCulture
        }
        # Load Toast Notification text
        $PendingRebootUptimeTextValue = $XmlLang.Text | Where-Object {$_.Name -like 'PendingRebootUptimeText'} | Select-Object -ExpandProperty '#text'
        $PendingRebootCheckTextValue = $XmlLang.Text | Where-Object {$_.Name -like 'PendingRebootCheckText'} | Select-Object -ExpandProperty '#text'
        $CustomAudioTextToSpeech = $XmlLang.Text | Where-Object {$_.Name -like 'CustomAudioTextToSpeech'} | Select-Object -ExpandProperty '#text'
        $ActionButton1Content = $XmlLang.Text | Where-Object {$_.Name -like 'ActionButton1'} | Select-Object -ExpandProperty '#text'
        $ActionButton2Content = $XmlLang.Text | Where-Object {$_.Name -like 'ActionButton2'} | Select-Object -ExpandProperty '#text'
        $DismissButtonContent = $XmlLang.Text | Where-Object {$_.Name -like 'DismissButton'} | Select-Object -ExpandProperty '#text'
        $SnoozeButtonContent = $XmlLang.Text | Where-Object {$_.Name -like 'SnoozeButton'} | Select-Object -ExpandProperty '#text'
        $AttributionText = $XmlLang.Text | Where-Object {$_.Name -like 'AttributionText'} | Select-Object -ExpandProperty '#text'
        $HeaderText = $XmlLang.Text | Where-Object {$_.Name -like 'HeaderText'} | Select-Object -ExpandProperty '#text'
        $TitleText = $XmlLang.Text | Where-Object {$_.Name -like 'TitleText'} | Select-Object -ExpandProperty '#text'
        $BodyText1 = $XmlLang.Text | Where-Object {$_.Name -like 'BodyText1'} | Select-Object -ExpandProperty '#text'
        $BodyText2 = $XmlLang.Text | Where-Object {$_.Name -like 'BodyText2'} | Select-Object -ExpandProperty '#text'
        $SnoozeText = $XmlLang.Text | Where-Object {$_.Name -like 'SnoozeText'} | Select-Object -ExpandProperty '#text'
	    $DeadlineText = $XmlLang.Text | Where-Object {$_.Name -like 'DeadlineText'} | Select-Object -ExpandProperty '#text'
	    $GreetMorningText = $XmlLang.Text | Where-Object {$_.Name -like 'GreetMorningText'} | Select-Object -ExpandProperty '#text'
	    $GreetAfternoonText = $XmlLang.Text | Where-Object {$_.Name -like 'GreetAfternoonText'} | Select-Object -ExpandProperty '#text'
	    $GreetEveningText = $XmlLang.Text | Where-Object {$_.Name -like 'GreetEveningText'} | Select-Object -ExpandProperty '#text'
	    $MinutesText = $XmlLang.Text | Where-Object {$_.Name -like 'MinutesText'} | Select-Object -ExpandProperty '#text'
	    $HourText = $XmlLang.Text | Where-Object {$_.Name -like 'HourText'} | Select-Object -ExpandProperty '#text'
        $HoursText = $XmlLang.Text | Where-Object {$_.Name -like 'HoursText'} | Select-Object -ExpandProperty '#text'
	    $ComputerUptimeText = $XmlLang.Text | Where-Object {$_.Name -like 'ComputerUptimeText'} | Select-Object -ExpandProperty '#text'
        $ComputerUptimeDaysText = $XmlLang.Text | Where-Object {$_.Name -like 'ComputerUptimeDaysText'} | Select-Object -ExpandProperty '#text'
        
        # Support for NAP-style direct element configs (without language wrapper)
        if ($xml.Configuration.Text.Title) {
            $TitleText = $xml.Configuration.Text.Title
            Write-Log -Message "Using NAP-style direct Title element"
        }
        if ($xml.Configuration.Text.Body) {
            $BodyText1 = $xml.Configuration.Text.Body
            Write-Log -Message "Using NAP-style direct Body element"
        }
        if ($xml.Configuration.Text.ActionButtonContent) {
            $ActionButton1Content = $xml.Configuration.Text.ActionButtonContent
            Write-Log -Message "Using NAP-style direct ActionButtonContent element"
        }
        if ($xml.Configuration.Text.DismissButtonContent) {
            $DismissButtonContent = $xml.Configuration.Text.DismissButtonContent
            Write-Log -Message "Using NAP-style direct DismissButtonContent element"
        }
        if ($xml.Configuration.Text.SnoozeButtonContent) {
            $SnoozeButtonContent = $xml.Configuration.Text.SnoozeButtonContent
            Write-Log -Message "Using NAP-style direct SnoozeButtonContent element"
        }
        if ($xml.Configuration.Text.SnoozeText) {
            $SnoozeText = $xml.Configuration.Text.SnoozeText
            Write-Log -Message "Using NAP-style direct SnoozeText element"
        }
        if ($xml.Configuration.Text.MinutesText) {
            $MinutesText = $xml.Configuration.Text.MinutesText
        }
        if ($xml.Configuration.Text.HourText) {
            $HourText = $xml.Configuration.Text.HourText
        }
        if ($xml.Configuration.Text.HoursText) {
            $HoursText = $xml.Configuration.Text.HoursText
        }
        if ($xml.Configuration.Text.ComputerUptimeText) {
            $ComputerUptimeText = $xml.Configuration.Text.ComputerUptimeText
        }
        if ($xml.Configuration.Text.ComputerUptimeDaysText) {
            $ComputerUptimeDaysText = $xml.Configuration.Text.ComputerUptimeDaysText
        }
        
        Write-Log -Message "Successfully loaded xml content from $Config"     
    }
    catch {
        Write-Log -Message "Xml content from $Config was not loaded properly"
        Exit 1
    }
}

# Check if toast is enabled in config.xml
if ($ToastEnabled -ne "True") {
    Write-Log -Message "Toast notification is not enabled. Please check $Config file"
    Exit 1
}

# Basic validation for reboot-only functionality
if (($PendingRebootCheck -eq "True") -AND ($PendingRebootUptime -eq "True")) {
    Write-Log -Level Warn -Message "Both PendingRebootCheck and PendingRebootUptime are enabled. Script will check both conditions."
}

if (($PendingRebootCheck -ne "True") -AND ($PendingRebootUptime -ne "True")) {
    Write-Log -Level Warn -Message "Neither PendingRebootCheck nor PendingRebootUptime are enabled. No reboot checks will be performed."
}

if (($PendingRebootUptimeTextEnabled -eq "True") -AND ($PendingRebootCheckTextEnabled -eq "True")) {
    Write-Log -Level Warn -Message "Both reboot text options are enabled. This may cause duplicate text in the notification."
}

if (($PendingRebootCheck -eq "True") -AND ($PendingRebootUptimeTextEnabled -eq "True")) {
    Write-Log -Level Warn -Message "PendingRebootCheck is enabled with PendingRebootUptimeText. Consider using PendingRebootCheckText instead."
}

if (($PendingRebootUptime -eq "True") -AND ($PendingRebootCheckTextEnabled -eq "True")) {
    Write-Log -Level Warn -Message "PendingRebootUptime is enabled with PendingRebootCheckText. Consider using PendingRebootUptimeText instead."
}

# Validate notification app settings
if (($SCAppStatus -eq "True") -AND (-NOT(Get-Service -Name ccmexec -ErrorAction SilentlyContinue))) {
    Write-Log -Level Error -Message "Error. Using Software Center app for the notification requires the ConfigMgr client installed"
    Write-Log -Level Error -Message "Error. Please install the ConfigMgr client or use PowerShell as app doing the notification"
    Exit 1
}

if (($SCAppStatus -ne "True") -AND ($PSAppStatus -ne "True") -AND ($CustomAppEnabled -ne "True")) {
    Write-Log -Level Error -Message "Error. You need to enable at least 1 app in the config doing the notification (SoftwareCenter, PowerShell, or CustomApp)"
    Exit 1
}

Write-Log -Message "Configuration validation completed for reboot-only functionality"

# Toast Notification conflict checking - simplified for reboot-only functionality
# New checks for conflicting selections. Trying to prevent combinations which will make the toast render without buttons
# Added in version 2.1.0
if (($ActionButton2Enabled -eq "True") -AND ($SnoozeButtonEnabled -eq "True")){
    Write-Log -Level Error -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Error -Message "You can't have ActionButton2 enabled and SnoozeButton enabled at the same time"
    Write-Log -Level Error -Message "That will result in too many buttons. Check your config"
    Exit 1
}
if (($SnoozeButtonEnabled -eq "True") -AND ($PendingRebootUptimeTextEnabled -eq "True")){
    Write-Log -Level Error -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Error -Message "You can't have SnoozeButton enabled and have PendingRebootUptimeText enabled at the same time"
    Write-Log -Level Error -Message "That will result in too much text and the toast notification will render without buttons. Check your config"
    Exit 1
}
if (($SnoozeButtonEnabled -eq "True") -AND ($PendingRebootCheckTextEnabled -eq "True")){
    Write-Log -Level Error -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Error -Message "You can't have SnoozeButton enabled and have PendingRebootCheckText enabled at the same time"
    Write-Log -Level Error -Message "That will result in too much text and the toast notification will render without buttons. Check your config"
    Exit 1
}
# Added in 2.3.0
# This option enables you to create a custom app doing the notification. 
# This also completely prevents the user from disabling the toast from within the UI (can be done with registry editing, if one knows how)
if ($CustomAppEnabled -eq "True") {
    # Hardcoding the AppID. Only the display name is interesting, thus this comes from the config.xml
    $App = "Toast.Custom.App"
    Register-CustomNotificationApp -fAppID $App -fAppDisplayName $CustomAppValue
}

# Added in version 2.2.0
# This option is able to prevent multiple toast notification from being displayed in a row
if ($LimitToastToRunEveryMinutesEnabled -eq "True") {
    $LastRunTimeOutput = Get-NotificationLastRunTime
    if (-NOT[string]::IsNullOrEmpty($LastRunTimeOutput)) {
        if ($LastRunTimeOutput -lt $LimitToastToRunEveryMinutesValue) {
            Write-Log -Level Error -Message "Toast notification was displayed too recently"
            Write-Log -Level Error -Message "Toast notification was displayed $LastRunTimeOutput minutes ago and the config.xml is configured to allow $LimitToastToRunEveryMinutesValue minutes intervals"
            Write-Log -Level Error -Message "This is done to prevent ConfigMgr catching up on missed schedules, and thus display multiple toasts of the same appearance in a row"
            break   
        }    
    }
}

# Downloading images into user's temp folder if images are hosted online
if (($LogoImageFileName.StartsWith("https://")) -OR ($LogoImageFileName.StartsWith("http://"))) {
    Write-Log -Message "ToastLogoImage appears to be hosted online. Will need to download the file"
    # Testing to see if image at the provided URL indeed is available
    try { $testOnlineLogoImage = Invoke-WebRequest -Uri $LogoImageFileName -UseBasicParsing } catch { <# nothing to see here. Used to make webrequest silent #> }
    if ($testOnlineLogoImage.StatusDescription -eq "OK") {
        try {
            Invoke-WebRequest -Uri $LogoImageFileName -OutFile $LogoImageTemp
            # Replacing image variable with the image downloaded locally
            $LogoImage = $LogoImageTemp
            Write-Log -Message "Successfully downloaded $LogoImageTemp from $LogoImageFileName"
        }
        catch { 
            Write-Log -Level Error -Message "Failed to download the $LogoImageTemp from $LogoImageFileName"
        }
    }
    else {
        Write-Log -Level Error -Message "The picture supposedly located on $LogoImageFileName is not available"
    }
}
if (($HeroImageFileName.StartsWith("https://")) -OR ($HeroImageFileName.StartsWith("http://"))) {
    Write-Log -Message "ToastHeroImage appears to be hosted online. Will need to download the file"
    # Testing to see if image at the provided URL indeed is available
    try { $testOnlineHeroImage = Invoke-WebRequest -Uri $HeroImageFileName -UseBasicParsing } catch { <# nothing to see here. Used to make webrequest silent #> }
    if ($testOnlineHeroImage.StatusDescription -eq "OK") {
        try {
            Invoke-WebRequest -Uri $HeroImageFileName -OutFile $HeroImageTemp
            # Replacing image variable with the image downloaded locally
            $HeroImage = $HeroImageTemp
            Write-Log -Message "Successfully downloaded $HeroImageTemp from $HeroImageFileName"
        }
        catch { 
            Write-Log -Level Error -Message "Failed to download the $HeroImageTemp from $HeroImageFileName"
        }
    }
    else {
        Write-Log -Level Error -Message "The image supposedly located on $HeroImageFileName is not available"
    }
}

# Creating custom scripts and protocols if enabled in the config
if ($CreateScriptsProtocolsEnabled -eq "True") {
    $RegistryName = "ScriptsAndProtocolsVersion"
    Write-Log -Message "CreateScriptsAndProtocols set to True. Will allow creation of scripts and protocols"
    # Testing to see if the global registry path exist. It should, because it was created earlier
    if (Test-Path -Path $global:RegistryPath) {
        # Creating the registry key used to determine if scripts and protocols should be created
        # If it does not exist already, create the key with a value of '0'
        if (((Get-Item -Path $global:RegistryPath -ErrorAction SilentlyContinue).Property -contains $RegistryName) -ne $true) {
             New-ItemProperty -Path $global:RegistryPath -Name $RegistryName -Value "0" -PropertyType "String" -Force | Out-Null
        }
        if (((Get-Item -Path $global:RegistryPath -ErrorAction SilentlyContinue).Property -contains $RegistryName) -eq $true) {
            # If the registry key exist, but has a value less than the script version, go ahead and create scripts and protocols
            if ((Get-ItemProperty -Path $global:RegistryPath -Name $RegistryName -ErrorAction SilentlyContinue).$RegistryName -lt $global:ScriptVersion) {
                Write-Log -Message "Registry value of $RegistryName does not match Script version: $global:ScriptVersion"
                try {
                    Write-Log -Message "Creating scripts and protocols for the logged on user"
                    Write-CustomActionRegistry -ActionType ToastReboot
                    Write-CustomActionRegistry -ActionType ToastRunApplicationID
                    Write-CustomActionRegistry -ActionType ToastRunPackageID
                    Write-CustomActionRegistry -ActionType ToastRunUpdateID
                    Write-CustomActionScript -Type ToastReboot
                    Write-CustomActionScript -Type ToastRunApplicationID
                    Write-CustomActionScript -Type ToastRunPackageID
                    Write-CustomActionScript -Type ToastRunUpdateID
                    Write-CustomActionScript -Type InvokePSScriptAsUser
                    New-ItemProperty -Path $global:RegistryPath -Name $RegistryName -Value $global:ScriptVersion -PropertyType "String" -Force | Out-Null
                }
                catch { 
                    Write-Log -Level Error -Message "Something failed during creation of custom scripts and protocols"
                }
            }
            elseif ((Get-ItemProperty -Path $global:RegistryPath -Name $RegistryName -ErrorAction SilentlyContinue).$RegistryName -ge $global:ScriptVersion) {
                Write-Log -Message "Script version: $global:ScriptVersion matches value of $RegistryName in registry. Not creating custom scripts and protocols"
            }
        }
    }
}

# Running Pending Reboot Checks
if ($PendingRebootCheck -eq "True") {
    Write-Log -Message "PendingRebootCheck set to True. Checking for pending reboots"
    $TestPendingRebootRegistry = Test-PendingRebootRegistry
    $TestPendingRebootWMI = Test-PendingRebootWMI
}
if ($PendingRebootUptime -eq "True") {
    $Uptime = Get-DeviceUptime
    Write-Log -Message "PendingRebootUptime set to True. Checking for device uptime. Current uptime is: $Uptime days"
}

# Check for required entries in registry for when using Custom App as application for the toast
if ($CustomAppEnabled -eq "True") {
    # Path to the notification app doing the actual toast
    $RegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"
    # For clarity, declaring the App variables once again
    $App =  "Toast.Custom.App"
    # Creating registry entries if they don't exists
    if (-NOT(Test-Path -Path $RegPath\$App)) {
        New-Item -Path $RegPath\$App -Force
        New-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -Value 0 -PropertyType "DWORD"
        New-ItemProperty -Path $RegPath\$App -Name "Enabled" -Value 1 -PropertyType "DWORD" -Force
        New-ItemProperty -Path $RegPath\$App -Name "SoundFile" -PropertyType "STRING" -Force
    }
    # Make sure the app used with the action center is enabled
    if ((Get-ItemProperty -Path $RegPath\$App -Name "Enabled" -ErrorAction SilentlyContinue).Enabled -ne "1") {
        New-ItemProperty -Path $RegPath\$App -Name "Enabled" -Value 1 -PropertyType "DWORD" -Force
    }    
    if ((Get-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -ErrorAction SilentlyContinue).ShowInActionCenter -ne "0") {
        New-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -Value 0 -PropertyType "DWORD" -Force
    }
    # Added to not play any sounds when notification is displayed with scenario: alarm
    if (-NOT(Get-ItemProperty -Path $RegPath\$App -Name "SoundFile" -ErrorAction SilentlyContinue)) {
        New-ItemProperty -Path $RegPath\$App -Name "SoundFile" -PropertyType "STRING" -Force
    }
}

# Check for required entries in registry for when using Software Center as application for the toast
if ($SCAppStatus -eq "True") {
    if (Get-Service -Name ccmexec -ErrorAction SilentlyContinue) {
        # Path to the notification app doing the actual toast
        $RegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"
        $App = "Microsoft.SoftwareCenter.DesktopToasts"
        # Creating registry entries if they don't exists
        if (-NOT(Test-Path -Path $RegPath\$App)) {
            New-Item -Path $RegPath\$App -Force
            New-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -Value 1 -PropertyType "DWORD" -Force
            New-ItemProperty -Path $RegPath\$App -Name "Enabled" -Value 1 -PropertyType "DWORD" -Force
            New-ItemProperty -Path $RegPath\$App -Name "SoundFile" -PropertyType "STRING" -Force
        }
        # Make sure the app used with the action center is enabled
        if ((Get-ItemProperty -Path $RegPath\$App -Name "Enabled" -ErrorAction SilentlyContinue).Enabled -ne "1") {
            New-ItemProperty -Path $RegPath\$App -Name "Enabled" -Value 1 -PropertyType "DWORD" -Force
        }
        if ((Get-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -ErrorAction SilentlyContinue).ShowInActionCenter -ne "1") {
            New-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -Value 1 -PropertyType "DWORD" -Force
        }
        # Added to not play any sounds when notification is displayed with scenario: alarm
        if (-NOT(Get-ItemProperty -Path $RegPath\$App -Name "SoundFile" -ErrorAction SilentlyContinue)) {
            New-ItemProperty -Path $RegPath\$App -Name "SoundFile" -PropertyType "STRING" -Force
        }
    }
    else {
        Write-Log -Message "No ConfigMgr client installed. Cannot use Software Center as notifying app" -Level Error
    }
}

# Check for required entries in registry for when using Powershell as application for the toast
if ($PSAppStatus -eq "True") {
    # Path to the notification app doing the actual toast
    $RegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"
    $App =  "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
    # Creating registry entries if they don't exists
    if (-NOT(Test-Path -Path $RegPath\$App)) {
        New-Item -Path $RegPath\$App -Force
        New-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -Value 1 -PropertyType "DWORD"
        New-ItemProperty -Path $RegPath\$App -Name "Enabled" -Value 1 -PropertyType "DWORD" -Force
        New-ItemProperty -Path $RegPath\$App -Name "SoundFile" -PropertyType "STRING" -Force
    }
    # Make sure the app used with the action center is enabled
    if ((Get-ItemProperty -Path $RegPath\$App -Name "Enabled" -ErrorAction SilentlyContinue).Enabled -ne "1") {
        New-ItemProperty -Path $RegPath\$App -Name "Enabled" -Value 1 -PropertyType "DWORD" -Force
    }    
    if ((Get-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -ErrorAction SilentlyContinue).ShowInActionCenter -ne "1") {
        New-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -Value 1 -PropertyType "DWORD" -Force
    }
    # Added to not play any sounds when notification is displayed with scenario: alarm
    if (-NOT(Get-ItemProperty -Path $RegPath\$App -Name "SoundFile" -ErrorAction SilentlyContinue)) {
        New-ItemProperty -Path $RegPath\$App -Name "SoundFile" -PropertyType "STRING" -Force
    }
}

# Checking if running toast with personal greeting with given name
if ($GreetGivenName -eq "True") {
    Write-Log -Message "Greeting with given name selected. Replacing HeaderText"
    $Hour = (Get-Date).TimeOfDay.Hours
    if (($Hour -ge 0) -AND ($Hour -lt 12)) {
        Write-Log -Message "Greeting with $GreetMorningText"
        $Greeting = $GreetMorningText
    }
    elseif (($Hour -ge 12) -AND ($Hour -lt 16)) {
        Write-Log -Message "Greeting with $GreetAfternoonText"
        $Greeting = $GreetAfternoonText
    }
    else {
        Write-Log -Message "Greeting with personal greeting: $GreetEveningText"
        $Greeting = $GreetEveningText
    }
    $GivenName = Get-GivenName
    $HeaderText = "$Greeting $GivenName"
}

# Formatting the toast notification XML
# Create the default toast notification XML with action button and dismiss button
if (($ActionButton1Enabled -eq "True") -AND ($DismissButtonEnabled -eq "True")) {
    Write-Log -Message "Creating the xml for action button and dismiss button"
[xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true">$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <action activationType="protocol" arguments="$Action1" content="$ActionButton1Content" />
        <action activationType="system" arguments="dismiss" content="$DismissButtonContent"/>
    </actions>
</toast>
"@
}

# NO action button and NO dismiss button
if (($ActionButton1Enabled -ne "True") -AND ($DismissButtonEnabled -ne "True")) {
    Write-Log -Message "Creating the xml for no action button and no dismiss button"
[xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true">$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
    </actions>
</toast>
"@
}

# Action button and NO dismiss button
if (($ActionButton1Enabled -eq "True") -AND ($DismissButtonEnabled -ne "True")) {
    Write-Log -Message "Creating the xml for no dismiss button"
[xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true">$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <action activationType="protocol" arguments="$Action1" content="$ActionButton1Content" />
    </actions>
</toast>
"@
}

# Dismiss button and NO action button
if (($ActionButton1Enabled -ne "True") -AND ($DismissButtonEnabled -eq "True")) {
    Write-Log -Message "Creating the xml for no action button"
[xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true">$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <action activationType="system" arguments="dismiss" content="$DismissButtonContent"/>
    </actions>
</toast>
"@
}

# Action button2 - this option will always enable both actionbutton1, actionbutton2 and dismiss button regardless of config settings
if ($ActionButton2Enabled -eq "True") {
    Write-Log -Message "Creating the xml for displaying the second action button: actionbutton2"
    Write-Log -Message "This will always enable both action buttons and the dismiss button" -Level Warn
    Write-Log -Message "Replacing any previous formatting of the toast xml" -Level Warn
[xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true">$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <action activationType="protocol" arguments="$Action1" content="$ActionButton1Content" />
        <action activationType="protocol" arguments="$Action2" content="$ActionButton2Content" />
        <action activationType="system" arguments="dismiss" content="$DismissButtonContent"/>
    </actions>
</toast>
"@
}

# Snooze button - this option will always enable actionbutton1, snooze button and dismiss button regardless of config settings
if ($SnoozeButtonEnabled -eq "True") {
    Write-Log -Message "Creating the xml for displaying the snooze button"
    Write-Log -Message "This will always enable the action button as well as the dismiss button" -Level Warn
    Write-Log -Message "Replacing any previous formatting of the toast xml" -Level Warn
[xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true">$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <input id="snoozeTime" type="selection" title="$SnoozeText" defaultInput="15">
            <selection id="15" content="15 $MinutesText"/>
            <selection id="30" content="30 $MinutesText"/>
            <selection id="60" content="1 $HourText"/>
            <selection id="240" content="4 $HoursText"/>
            <selection id="480" content="8 $HoursText"/>
        </input>
        <action activationType="protocol" arguments="$Action1" content="$ActionButton1Content" />
        <action activationType="system" arguments="snooze" hint-inputId="snoozeTime" content="$SnoozeButtonContent"/>
        <action activationType="system" arguments="dismiss" content="$DismissButtonContent"/>
    </actions>
</toast>
"@
}

# Add an additional group and text to the toast xml for PendingRebootCheck
if ($PendingRebootCheckTextEnabled -eq "True") {
$PendingRebootGroup = @"
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$PendingRebootCheckTextValue</text>
            </subgroup>
        </group>
"@
    $Toast.toast.visual.binding.InnerXml = $Toast.toast.visual.binding.InnerXml + $PendingRebootGroup
}

# Add an additional group and text to the toast xml used for notifying about computer uptime. Only add this if the computer uptime exceeds MaxUptimeDays.
if (($PendingRebootUptimeTextEnabled -eq "True") -AND ($Uptime -gt $MaxUptimeDays)) {
$UptimeGroup = @"
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$PendingRebootUptimeTextValue</text>
            </subgroup>
        </group>
        <group>
            <subgroup>
                <text hint-style="base" hint-align="left">$ComputerUptimeText $Uptime $ComputerUptimeDaysText</text>
            </subgroup>
        </group>
"@
    $Toast.toast.visual.binding.InnerXml = $Toast.toast.visual.binding.InnerXml + $UptimeGroup
}

# Running the Display-notification function for reboot scenarios only
$ToastDisplayed = $false

# Check if Force parameter is used
if ($Force.IsPresent) {
    Write-Log -Message "Force parameter specified. Displaying toast notification regardless of reboot conditions."
    Display-ToastNotification
    $ToastDisplayed = $true
}

# Toast used for PendingReboot check and considering OS uptime
# Supporting both positive and negative values for MaxUptimeDays (negative means "greater than absolute value")
if ((-NOT $ToastDisplayed) -AND ($PendingRebootUptime -eq "True")) {
    $UptimeThreshold = [math]::Abs($MaxUptimeDays)
    if ($Uptime -gt $UptimeThreshold) {
        Write-Log -Message "Toast notification displayed: Computer uptime ($Uptime days) exceeds maximum allowed ($UptimeThreshold days)"
        Display-ToastNotification
        $ToastDisplayed = $true
    } else {
        Write-Log -Message "Computer uptime ($Uptime days) is within acceptable range (threshold: $UptimeThreshold days)"
    }
}

# Toast used for pendingReboot check and considering checks in registry
if ((-NOT $ToastDisplayed) -AND ($PendingRebootCheck -eq "True") -AND ($TestPendingRebootRegistry -eq $True)) {
    Write-Log -Message "Toast notification displayed: Pending reboot found in registry. TestPendingRebootRegistry returned $TestPendingRebootRegistry"
    Display-ToastNotification
    $ToastDisplayed = $true
}

# Toast used for pendingReboot check and considering checks in WMI
if ((-NOT $ToastDisplayed) -AND ($PendingRebootCheck -eq "True") -AND ($TestPendingRebootWMI -eq $True)) {
    Write-Log -Message "Toast notification displayed: Pending reboot found in WMI. TestPendingRebootWMI returned $TestPendingRebootWMI"
    Display-ToastNotification
    $ToastDisplayed = $true
}

# If no reboot conditions were met, log it
if (-NOT $ToastDisplayed) {
    Write-Log -Message "No reboot conditions met. No toast notification displayed."
    Write-Log -Message "PendingRebootUptime: $PendingRebootUptime, Uptime: $Uptime days, MaxUptimeDays: $MaxUptimeDays (threshold: $([math]::Abs($MaxUptimeDays)))"
    if ($PendingRebootCheck -eq "True") {
        Write-Log -Message "PendingRebootCheck: $PendingRebootCheck, Registry: $TestPendingRebootRegistry, WMI: $TestPendingRebootWMI"
    }
}
#endregion