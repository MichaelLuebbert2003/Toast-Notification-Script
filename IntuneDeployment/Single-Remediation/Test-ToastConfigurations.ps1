# Toast Notification Configuration Tester
# Test all configuration scenarios for the reboot notification system
# Author: Michael Luebbert

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Day7-8","Day9","Day10","All","Interactive")]
    [string]$TestScenario = "Interactive",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = $PSScriptRoot
)

Write-Host "=== Toast Notification Configuration Tester ===" -ForegroundColor Cyan
Write-Host "Testing scenarios for enterprise reboot notifications" -ForegroundColor White
Write-Host ""

# Available configurations
$Configs = @{
    "Day7-8" = @{
        File = "config-toast-NAP-Day7-8.xml"
        Description = "Day 7-8: Initial gentle reminder with dismiss/snooze options"
        UptimeDays = 7
    }
    "Day9" = @{
        File = "config-toast-NAP-Day9.xml" 
        Description = "Day 9: Urgent warning, no dismiss but snooze available"
        UptimeDays = 9
    }
    "Day10" = @{
        File = "config-toast-NAP-Day10.xml"
        Description = "Day 10+: Mandatory restart with 60-minute countdown"
        UptimeDays = 10
    }
    "Default" = @{
        File = "config-toast-reboot.xml"
        Description = "Default configuration for testing"
        UptimeDays = 0
    }
}

function Test-Configuration {
    param(
        [string]$ConfigName,
        [hashtable]$ConfigInfo
    )
    
    $configFile = Join-Path $ConfigPath $ConfigInfo.File
    
    if (-not (Test-Path $configFile)) {
        Write-Warning "Configuration file not found: $configFile"
        return $false
    }
    
    Write-Host "Testing: $ConfigName" -ForegroundColor Yellow
    Write-Host "Description: $($ConfigInfo.Description)" -ForegroundColor Gray
    Write-Host "Config File: $($ConfigInfo.File)" -ForegroundColor Gray
    Write-Host ""
    
    try {
        # Test XML validity
        $xml = [xml](Get-Content $configFile)
        Write-Host "✓ XML syntax is valid" -ForegroundColor Green
        
        # Check required elements
        $features = $xml.Configuration.Feature
        $options = $xml.Configuration.Option
        $text = $xml.Configuration.Text
        
        if ($features) { Write-Host "✓ Features section found" -ForegroundColor Green }
        if ($options) { Write-Host "✓ Options section found" -ForegroundColor Green }
        if ($text) { Write-Host "✓ Text section found" -ForegroundColor Green }
        
        # Run actual toast notification test
        if ($Force) {
            Write-Host "Running toast notification..." -ForegroundColor Cyan
            $scriptPath = Join-Path $ConfigPath "New-ToastNotification.ps1"
            if (Test-Path $scriptPath) {
                & $scriptPath -Config $configFile -Force
                Write-Host "✓ Toast notification executed successfully" -ForegroundColor Green
            } else {
                Write-Warning "Main script not found: $scriptPath"
            }
        }
        
        Write-Host ""
        return $true
        
    } catch {
        Write-Host "✗ Error testing configuration: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return $false
    }
}

function Show-InteractiveMenu {
    Write-Host "Select a test scenario:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Day 7-8 Configuration (Gentle reminder)" -ForegroundColor White
    Write-Host "2. Day 9 Configuration (Urgent warning)" -ForegroundColor Yellow  
    Write-Host "3. Day 10+ Configuration (Mandatory restart)" -ForegroundColor Red
    Write-Host "4. Default Configuration" -ForegroundColor Gray
    Write-Host "5. Test All Configurations" -ForegroundColor Cyan
    Write-Host "6. Run Live Test (with -Force)" -ForegroundColor Magenta
    Write-Host "Q. Quit" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "Enter your choice (1-6, Q)"
    
    switch ($choice.ToUpper()) {
        "1" { return "Day7-8" }
        "2" { return "Day9" }
        "3" { return "Day10" }
        "4" { return "Default" }
        "5" { return "All" }
        "6" { return "Live" }
        "Q" { return "Quit" }
        default { 
            Write-Host "Invalid choice. Please try again." -ForegroundColor Red
            Start-Sleep 2
            return Show-InteractiveMenu
        }
    }
}

# Main execution logic
if ($TestScenario -eq "Interactive") {
    do {
        Clear-Host
        Write-Host "=== Toast Notification Configuration Tester ===" -ForegroundColor Cyan
        Write-Host ""
        
        $choice = Show-InteractiveMenu
        
        if ($choice -eq "Quit") {
            Write-Host "Exiting..." -ForegroundColor Gray
            break
        }
        
        if ($choice -eq "Live") {
            $liveChoice = Show-InteractiveMenu
            if ($liveChoice -ne "Quit" -and $liveChoice -ne "Live") {
                if ($liveChoice -eq "All") {
                    foreach ($config in $Configs.Keys) {
                        Test-Configuration -ConfigName $config -ConfigInfo $Configs[$config]
                        if ($config -ne "Default") {
                            Read-Host "Press Enter to continue to next configuration..."
                        }
                    }
                } else {
                    Test-Configuration -ConfigName $liveChoice -ConfigInfo $Configs[$liveChoice]
                }
            }
        } elseif ($choice -eq "All") {
            foreach ($config in $Configs.Keys) {
                Test-Configuration -ConfigName $config -ConfigInfo $Configs[$config]
            }
        } else {
            Test-Configuration -ConfigName $choice -ConfigInfo $Configs[$choice]
        }
        
        if ($choice -ne "All") {
            Read-Host "Press Enter to continue..."
        }
        
    } while ($true)
} else {
    # Non-interactive mode
    if ($TestScenario -eq "All") {
        $results = @{}
        foreach ($config in $Configs.Keys) {
            $results[$config] = Test-Configuration -ConfigName $config -ConfigInfo $Configs[$config]
        }
        
        Write-Host "=== Test Results Summary ===" -ForegroundColor Cyan
        foreach ($result in $results.Keys) {
            $status = if ($results[$result]) { "PASS" } else { "FAIL" }
            $color = if ($results[$result]) { "Green" } else { "Red" }
            Write-Host "$result : $status" -ForegroundColor $color
        }
    } else {
        if ($Configs.ContainsKey($TestScenario)) {
            Test-Configuration -ConfigName $TestScenario -ConfigInfo $Configs[$TestScenario]
        } else {
            Write-Error "Unknown test scenario: $TestScenario"
        }
    }
}