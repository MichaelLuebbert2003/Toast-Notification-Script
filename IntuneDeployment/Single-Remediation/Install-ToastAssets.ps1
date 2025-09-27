# Install Toast Notification Supporting Files
# This script installs all supporting files for the Toast Notification System

param(
    [string]$TargetPath = "$env:ProgramFiles\ToastNotificationSystem"
)

# Create logging function
function Write-InstallLog {
    param([string]$Message, [string]$Level = "Info")
    $LogPath = "$env:TEMP\ToastNotificationInstall.log"
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp [$Level] $Message" | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Host "[$Level] $Message"
}

try {
    Write-InstallLog "Starting Toast Notification System installation"
    
    # Create target directory
    if (-not (Test-Path $TargetPath)) {
        New-Item -Path $TargetPath -ItemType Directory -Force
        Write-InstallLog "Created directory: $TargetPath"
    }
    
    # Create subdirectories
    $Subdirs = @("Images", "Config", "Scripts", "Logs")
    foreach ($Subdir in $Subdirs) {
        $SubPath = Join-Path $TargetPath $Subdir
        if (-not (Test-Path $SubPath)) {
            New-Item -Path $SubPath -ItemType Directory -Force
            Write-InstallLog "Created directory: $SubPath"
        }
    }
    
    # Copy PowerShell scripts
    $ScriptFiles = @(
        "New-ToastNotification.ps1",
        "Invoke-ToastHidden.ps1"
    )
    
    foreach ($Script in $ScriptFiles) {
        if (Test-Path $Script) {
            Copy-Item $Script (Join-Path $TargetPath "Scripts") -Force
            Write-InstallLog "Copied script: $Script"
        }
    }
    
    # Copy configuration files
    $ConfigFiles = @(
        "config-toast-NAP-Day7-8.xml",
        "config-toast-NAP-Day9.xml", 
        "config-toast-NAP-Day10.xml",
        "config-toast-reboot.xml"
    )
    
    foreach ($Config in $ConfigFiles) {
        if (Test-Path $Config) {
            Copy-Item $Config (Join-Path $TargetPath "Config") -Force
            Write-InstallLog "Copied config: $Config"
        }
    }
    
    # Copy helper files
    $HelperFiles = @("Hidden.vbs", "RunToastHidden.cmd")
    foreach ($Helper in $HelperFiles) {
        if (Test-Path $Helper) {
            Copy-Item $Helper $TargetPath -Force
            Write-InstallLog "Copied helper: $Helper"
        }
    }
    
    # Copy image files
    if (Test-Path "Images") {
        Copy-Item "Images\*" (Join-Path $TargetPath "Images") -Force -Recurse
        Write-InstallLog "Copied image files"
    }
    
    # Set permissions - SYSTEM and Administrators full control
    $Acl = Get-Acl $TargetPath
    $AccessRule1 = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow")
    $AccessRule2 = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")
    $Acl.SetAccessRule($AccessRule1)
    $Acl.SetAccessRule($AccessRule2)
    Set-Acl -Path $TargetPath -AclObject $Acl
    Write-InstallLog "Set permissions for SYSTEM and Administrators"
    
    # Create registry entry for version tracking
    $RegPath = "HKLM:\SOFTWARE\ToastNotificationSystem"
    if (-not (Test-Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }
    Set-ItemProperty -Path $RegPath -Name "Version" -Value "2.3.0-ML"
    Set-ItemProperty -Path $RegPath -Name "InstallDate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Set-ItemProperty -Path $RegPath -Name "InstallPath" -Value $TargetPath
    Write-InstallLog "Created registry entries"
    
    Write-InstallLog "Toast Notification System installation completed successfully"
    exit 0
    
} catch {
    Write-InstallLog "Installation failed: $($_.Exception.Message)" "Error"
    exit 1
}