# Uninstall Toast Notification Supporting Files
# This script removes all supporting files for the Toast Notification System

param(
    [string]$TargetPath = "$env:ProgramFiles\ToastNotificationSystem"
)

# Create logging function
function Write-UninstallLog {
    param([string]$Message, [string]$Level = "Info")
    $LogPath = "$env:TEMP\ToastNotificationUninstall.log"
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp [$Level] $Message" | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Host "[$Level] $Message"
}

try {
    Write-UninstallLog "Starting Toast Notification System uninstallation"
    
    # Stop any running processes
    $ToastProcesses = Get-Process | Where-Object {$_.ProcessName -like "*toast*" -or $_.CommandLine -like "*ToastNotification*"}
    if ($ToastProcesses) {
        $ToastProcesses | Stop-Process -Force
        Write-UninstallLog "Stopped running toast notification processes"
    }
    
    # Remove installation directory
    if (Test-Path $TargetPath) {
        Remove-Item -Path $TargetPath -Recurse -Force
        Write-UninstallLog "Removed directory: $TargetPath"
    }
    
    # Remove registry entries
    $RegPath = "HKLM:\SOFTWARE\ToastNotificationSystem"
    if (Test-Path $RegPath) {
        Remove-Item -Path $RegPath -Recurse -Force
        Write-UninstallLog "Removed registry entries"
    }
    
    # Clean up user-specific log directories
    $UserLogPath = "$env:APPDATA\ToastNotificationScript"
    if (Test-Path $UserLogPath) {
        Remove-Item -Path $UserLogPath -Recurse -Force
        Write-UninstallLog "Removed user log directory: $UserLogPath"
    }
    
    # Remove temp files
    $TempFiles = Get-ChildItem "$env:TEMP" -Filter "*ToastNotification*" -ErrorAction SilentlyContinue
    if ($TempFiles) {
        $TempFiles | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-UninstallLog "Removed temporary files"
    }
    
    Write-UninstallLog "Toast Notification System uninstallation completed successfully"
    exit 0
    
} catch {
    Write-UninstallLog "Uninstallation failed: $($_.Exception.Message)" "Error"
    exit 1
}