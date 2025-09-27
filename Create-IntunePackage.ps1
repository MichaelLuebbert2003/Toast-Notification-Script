# Intune Deployment Package Creator
# Creates deployment-ready packages for Intune Proactive Remediation
# Author: Michael Luebbert

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\IntuneDeployment",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Single","Progressive","Both")]
    [string]$DeploymentType = "Both",
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateZip
)

Write-Host "=== Intune Deployment Package Creator ===" -ForegroundColor Cyan
Write-Host "Creating deployment packages for Toast Notification System" -ForegroundColor White
Write-Host ""

# Create output directory
if (Test-Path $OutputPath) {
    Remove-Item $OutputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

# Core files that every deployment needs
$CoreFiles = @(
    "New-ToastNotification.ps1",
    "Detect-RebootRequired.ps1", 
    "Remediate-RebootNotification.ps1",
    "config-toast-reboot.xml"
)

# Progressive config files
$ProgressiveConfigs = @(
    "config-toast-NAP-Day7-8.xml",
    "config-toast-NAP-Day9.xml", 
    "config-toast-NAP-Day10.xml"
)

# Image files
$ImageFiles = @(
    "Images\ToastLogoImageNAP.png",
    "Images\Nap-HeroToast.jpg",
    "Images\ToastHeroImageDefault.jpg",
    "Images\ToastLogoImageDefault.jpg"
)

# Testing and documentation files
$DocFiles = @(
    "Test-ToastConfigurations.ps1",
    "Intune-Deployment-Guide.md",
    "README.md"
)

function Copy-FilesWithCheck {
    param(
        [string[]]$Files,
        [string]$DestinationPath,
        [string]$FileType
    )
    
    $copied = 0
    $missing = 0
    
    Write-Host "Copying $FileType files..." -ForegroundColor Yellow
    
    foreach ($file in $Files) {
        if (Test-Path $file) {
            $destFile = Join-Path $DestinationPath (Split-Path $file -Leaf)
            $destDir = Split-Path $destFile -Parent
            
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            
            Copy-Item $file $destFile -Force
            Write-Host "  ✓ $file" -ForegroundColor Green
            $copied++
        } else {
            Write-Host "  ✗ $file (missing)" -ForegroundColor Red
            $missing++
        }
    }
    
    Write-Host "  $copied copied, $missing missing" -ForegroundColor Gray
    Write-Host ""
}

function Create-DeploymentReadme {
    param([string]$Path, [string]$Type)
    
    $readme = @"
# Toast Notification System - $Type Deployment

## Package Contents
This package contains all files needed for Intune Proactive Remediation deployment.

## Deployment Type: $Type

### Quick Start
1. Upload detection and remediation scripts to Intune Proactive Remediation
2. Deploy image assets using Win32 app or embed in scripts  
3. Configure assignment to target device groups
4. Monitor remediation results

### Files Included
"@

    # List all files in the package
    $files = Get-ChildItem $Path -Recurse | Where-Object { -not $_.PSIsContainer }
    foreach ($file in $files) {
        $relativePath = $file.FullName.Replace($Path, "").TrimStart("\")
        $readme += "`n- $relativePath"
    }
    
    $readme += @"

### Next Steps
1. Review Intune-Deployment-Guide.md for complete instructions
2. Test configurations using Test-ToastConfigurations.ps1
3. Deploy to pilot group first
4. Monitor and adjust as needed

### Support
- Script Author: Michael Luebbert  
- Based on: Original work by Martin Bengtsson
- Documentation: See Intune-Deployment-Guide.md

**WARNING**: Day 10+ configuration will force restart devices automatically!
"@

    $readme | Out-File (Join-Path $Path "README.txt") -Encoding UTF8
}

# Create Single Deployment Package
if ($DeploymentType -eq "Single" -or $DeploymentType -eq "Both") {
    Write-Host "Creating Single Deployment Package..." -ForegroundColor Cyan
    $singlePath = Join-Path $OutputPath "Single-Remediation"
    New-Item -ItemType Directory -Path $singlePath -Force | Out-Null
    
    Copy-FilesWithCheck -Files $CoreFiles -DestinationPath $singlePath -FileType "Core"
    Copy-FilesWithCheck -Files $ImageFiles -DestinationPath (Join-Path $singlePath "Images") -FileType "Image"
    Copy-FilesWithCheck -Files $DocFiles -DestinationPath $singlePath -FileType "Documentation"
    
    Create-DeploymentReadme -Path $singlePath -Type "Single"
    
    if ($CreateZip) {
        $zipPath = "$OutputPath\Toast-Notification-Single-Deployment.zip"
        Compress-Archive -Path "$singlePath\*" -DestinationPath $zipPath -Force
        Write-Host "Created ZIP: $zipPath" -ForegroundColor Green
    }
}

# Create Progressive Deployment Package  
if ($DeploymentType -eq "Progressive" -or $DeploymentType -eq "Both") {
    Write-Host "Creating Progressive Deployment Package..." -ForegroundColor Cyan
    $progressivePath = Join-Path $OutputPath "Progressive-Remediations"
    New-Item -ItemType Directory -Path $progressivePath -Force | Out-Null
    
    Copy-FilesWithCheck -Files $CoreFiles -DestinationPath $progressivePath -FileType "Core"
    Copy-FilesWithCheck -Files $ProgressiveConfigs -DestinationPath $progressivePath -FileType "Progressive Config"
    Copy-FilesWithCheck -Files $ImageFiles -DestinationPath (Join-Path $progressivePath "Images") -FileType "Image"
    Copy-FilesWithCheck -Files $DocFiles -DestinationPath $progressivePath -FileType "Documentation"
    
    # Create stage-specific folders
    $stages = @("Day7-8", "Day9", "Day10")
    foreach ($stage in $stages) {
        $stagePath = Join-Path $progressivePath $stage
        New-Item -ItemType Directory -Path $stagePath -Force | Out-Null
        
        # Copy relevant config to stage folder
        $configFile = "config-toast-NAP-$stage.xml"
        if (Test-Path $configFile) {
            Copy-Item $configFile (Join-Path $stagePath $configFile) -Force
        }
    }
    
    Create-DeploymentReadme -Path $progressivePath -Type "Progressive"
    
    if ($CreateZip) {
        $zipPath = "$OutputPath\Toast-Notification-Progressive-Deployment.zip"  
        Compress-Archive -Path "$progressivePath\*" -DestinationPath $zipPath -Force
        Write-Host "Created ZIP: $zipPath" -ForegroundColor Green
    }
}

Write-Host "=== Deployment Package Creation Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Output Location: $OutputPath" -ForegroundColor Cyan
Write-Host ""

# Show summary
$items = Get-ChildItem $OutputPath -Recurse
$folders = ($items | Where-Object { $_.PSIsContainer }).Count
$files = ($items | Where-Object { -not $_.PSIsContainer }).Count

Write-Host "Package Summary:" -ForegroundColor Yellow  
Write-Host "  Folders: $folders" -ForegroundColor White
Write-Host "  Files: $files" -ForegroundColor White
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Review the deployment packages in: $OutputPath" -ForegroundColor White
Write-Host "2. Test configurations using Test-ToastConfigurations.ps1" -ForegroundColor White  
Write-Host "3. Follow Intune-Deployment-Guide.md for complete deployment steps" -ForegroundColor White
Write-Host "4. Deploy to pilot group first!" -ForegroundColor Red
Write-Host ""
Write-Host "⚠️  WARNING: Day 10+ configuration will force restart devices!" -ForegroundColor Red