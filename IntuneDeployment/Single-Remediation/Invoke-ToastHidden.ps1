# Silent Toast Notification Launcher
# Ensures toast notifications run completely hidden from user view
# Author: Michael Luebbert

param(
    [Parameter(Mandatory=$false)]
    [string]$Config,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [int]$UptimeThreshold = 7
)

# Ensure this script itself runs hidden
if (-not $env:HIDE_POWERSHELL_WINDOW) {
    $env:HIDE_POWERSHELL_WINDOW = "1"
    $arguments = @()
    
    # Rebuild arguments for hidden execution
    if ($Config) { $arguments += "-Config `"$Config`"" }
    if ($Force) { $arguments += "-Force" }
    if ($UptimeThreshold -ne 7) { $arguments += "-UptimeThreshold $UptimeThreshold" }
    
    $argumentString = $arguments -join " "
    
    # Relaunch this script completely hidden
    Start-Process -FilePath "powershell.exe" -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -NonInteractive -NoLogo -File `"$($MyInvocation.MyCommand.Path)`" $argumentString" -WindowStyle Hidden -Wait
    exit
}

# Function to write to event log (hidden logging)
function Write-SilentLog {
    param(
        [string]$Message,
        [string]$Level = "Information"
    )
    
    try {
        $SourceName = "ToastNotificationHidden"
        if (-not [System.Diagnostics.EventLog]::SourceExists($SourceName)) {
            [System.Diagnostics.EventLog]::CreateEventSource($SourceName, "Application")
        }
        
        $EventType = switch ($Level) {
            "Error" { "Error" }
            "Warning" { "Warning" }
            default { "Information" }
        }
        
        Write-EventLog -LogName Application -Source $SourceName -EventId 1001 -EntryType $EventType -Message $Message
    }
    catch {
        # Silently fail if we can't write to event log
    }
}

try {
    Write-SilentLog "Starting silent toast notification execution"
    
    # Determine script location
    $ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $MainScript = Join-Path $ScriptDirectory "New-ToastNotification.ps1"
    
    if (-not (Test-Path $MainScript)) {
        Write-SilentLog "Main script not found: $MainScript" -Level "Error"
        exit 1
    }
    
    # Auto-select config based on uptime if not specified
    if (-not $Config) {
        # Get system uptime
        $Uptime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
        $UptimeDays = ((Get-Date) - $Uptime).Days
        
        Write-SilentLog "System uptime: $UptimeDays days"
        
        # Select appropriate config based on uptime
        $ConfigFile = switch ($UptimeDays) {
            { $_ -ge 10 } { "config-toast-NAP-Day10.xml" }
            { $_ -ge 9 } { "config-toast-NAP-Day9.xml" }
            { $_ -ge 7 } { "config-toast-NAP-Day7-8.xml" }
            default { "config-toast-reboot.xml" }
        }
        
        $Config = Join-Path $ScriptDirectory $ConfigFile
        Write-SilentLog "Auto-selected config: $ConfigFile for $UptimeDays days uptime"
    }
    
    if (-not (Test-Path $Config)) {
        Write-SilentLog "Configuration file not found: $Config" -Level "Warning"
        # Fall back to default config
        $Config = Join-Path $ScriptDirectory "config-toast-reboot.xml"
    }
    
    # Prepare arguments for main script
    $Arguments = @(
        "-ExecutionPolicy", "Bypass"
        "-WindowStyle", "Hidden"
        "-NoProfile"
        "-NonInteractive"
        "-NoLogo"
        "-File", "`"$MainScript`""
        "-Config", "`"$Config`""
    )
    
    if ($Force) {
        $Arguments += "-Force"
    }
    
    Write-SilentLog "Executing main script with config: $(Split-Path $Config -Leaf)"
    
    # Execute main script completely hidden
    $Process = Start-Process -FilePath "powershell.exe" -ArgumentList $Arguments -WindowStyle Hidden -PassThru -Wait
    
    $ExitCode = $Process.ExitCode
    if ($ExitCode -eq 0) {
        Write-SilentLog "Toast notification executed successfully"
    } else {
        Write-SilentLog "Toast notification script returned exit code: $ExitCode" -Level "Warning"
    }
    
    exit $ExitCode
    
} catch {
    Write-SilentLog "Error in silent launcher: $($_.Exception.Message)" -Level "Error"
    exit 1
}