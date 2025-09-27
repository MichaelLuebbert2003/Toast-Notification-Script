# Intune Proactive Remediation Deployment Guide
# Complete guide for deploying Toast Notification Reboot System
# Author: Michael Luebbert

## Overview
This guide covers deploying the progressive reboot notification system to Microsoft Intune using Proactive Remediations (also known as Remediation Scripts).

## System Architecture

The notification system uses a 3-stage progressive approach with **completely silent execution** (no PowerShell windows visible to users):

### Stage 1: Day 7-8 (Gentle Reminder)
- **Config**: `config-toast-NAP-Day7-8.xml`
- **Behavior**: Friendly reminder with restart and dismiss options only
- **Target**: Devices with 7+ days uptime
- **User Control**: Restart or Dismiss (no snooze - runs every 24 hours)
- **Execution**: Completely silent background process
- **Schedule**: Every 24 hours (no need for snooze)

### Stage 2: Day 9 (Urgent Warning)  
- **Config**: `config-toast-NAP-Day9.xml`
- **Behavior**: Urgent warning, no dismiss but snooze available
- **Target**: Devices with 9+ days uptime
- **User Control**: Limited (snooze only)
- **Execution**: Completely silent background process

### Stage 3: Day 10+ (Mandatory Restart)
- **Config**: `config-toast-NAP-Day10.xml` 
- **Behavior**: Forced restart with 60-minute countdown timer
- **Target**: Devices with 10+ days uptime
- **User Control**: None (mandatory restart)
- **Execution**: Silent background process + **visible countdown window** (intentional)

## Files Required for Deployment

### Core Script Files
1. `New-ToastNotification.ps1` - Main notification script
2. `Detect-RebootRequired.ps1` - Detection script for Intune
3. `Remediate-RebootNotification.ps1` - Remediation script for Intune

### Configuration Files (Choose your approach)
**Option A: Single Config (Dynamic)**
- `config-toast-reboot.xml` - Single config with dynamic logic

**Option B: Progressive Configs (Separate Remediations)**
- `config-toast-NAP-Day7-8.xml` - Stage 1 configuration
- `config-toast-NAP-Day9.xml` - Stage 2 configuration  
- `config-toast-NAP-Day10.xml` - Stage 3 configuration

### Image Assets
- `ToastLogoImageNAP.png` - Company logo
- `Nap-HeroToast.jpg` - Hero image for notifications

### Silent Execution Components
- `Invoke-ToastHidden.ps1` - Silent launcher ensuring no PowerShell windows
- `Hidden.vbs` - VBScript wrapper for completely invisible execution
- `RunToastHidden.cmd` - Updated batch file with silent parameters

## 🔕 Silent Execution Features

### No PowerShell Windows Visible
The system is designed to run completely silently without showing any PowerShell console windows to users:

- **Intune Remediation Scripts**: Execute with `-WindowStyle Hidden`
- **Main Script Execution**: Uses `StartProcessAsCurrentUser` with `visible = false`
- **Background Processes**: All PowerShell processes run with `-WindowStyle Hidden`
- **VBS Wrapper**: `Hidden.vbs` provides additional invisibility layer

### What Users See
- **Toast notifications only** - No console windows or script dialogs
- **Day 10+ countdown timer** - Intentionally visible Windows Form for urgency
- **System tray notifications** - Standard Windows notification behavior

### What Users DON'T See
- ❌ PowerShell console windows
- ❌ Command prompt windows  
- ❌ Script execution dialogs
- ❌ Background process indicators

## Intune Deployment Methods

### Method 1: Single Proactive Remediation (Recommended)
Deploy one remediation that handles all stages dynamically.

#### Detection Script Content:
```powershell
# Use the existing Detect-RebootRequired.ps1
# This script checks uptime and determines notification stage needed
```

#### Remediation Script Content:
```powershell  
# Use the existing Remediate-RebootNotification.ps1
# This script determines the appropriate config and runs the notification
```

### Method 2: Separate Remediations per Stage
Deploy three separate remediations for different uptime thresholds.

#### Remediation 1: Day 7-8 Notifications
- **Target**: Devices 7-8 days uptime
- **Config**: `config-toast-NAP-Day7-8.xml`
- **Schedule**: Run every 4 hours

#### Remediation 2: Day 9 Notifications  
- **Target**: Devices 9 days uptime
- **Config**: `config-toast-NAP-Day9.xml`
- **Schedule**: Run every 2 hours

#### Remediation 3: Day 10+ Force Restart
- **Target**: Devices 10+ days uptime
- **Config**: `config-toast-NAP-Day10.xml` 
- **Schedule**: Run every hour

## Step-by-Step Intune Deployment

### Step 1: Prepare Files
1. Ensure all script files are in a single folder
2. Test configurations using `Test-ToastConfigurations.ps1`
3. Verify image assets are present and correctly named
4. Update company branding in config files

### Step 2: Create Proactive Remediation in Intune

#### Navigate to Intune
1. Sign in to [Microsoft Intune admin center](https://intune.microsoft.com)
2. Go to **Reports** > **Endpoint analytics** > **Proactive remediations**
3. Click **Create script package**

#### Basic Information
- **Name**: `Reboot Notification System - Progressive Alerts`
- **Description**: `Progressive reboot notifications with automatic restart enforcement`
- **Publisher**: `Your Organization IT`

#### Settings Configuration
- **Detection script file**: Upload `Detect-RebootRequired.ps1`
- **Remediation script file**: Upload `Remediate-RebootNotification.ps1`  
- **Run this script using the logged on credentials**: **No** (Run as System)
- **Enforce script signature check**: **No**
- **Run script in 64 bit PowerShell Host**: **Yes**

### Step 3: Deploy Required Files

#### Option A: Package Files in Scripts
Embed config files and images as base64 strings within the remediation script.

#### Option B: Use Intune Win32 App (Recommended)
1. Create Win32 app package containing:
   - All config files
   - Image assets  
   - Main script files
2. Deploy to **All Devices** with **Required** assignment
3. Set install command: `powershell.exe -ExecutionPolicy Bypass -File "Install-ToastAssets.ps1"`

### Step 4: Assignment and Scheduling

#### Device Groups
- **Target**: All Windows devices or specific device groups
- **Assignment type**: **Required**

#### Schedule Settings  
- **Frequency**: Every 2 hours (for responsive notifications)
- **Start date/time**: Immediate
- **End date**: None (ongoing)

#### Notifications
- **Show all toast notifications**: **Yes**
- **Restart grace period**: **No grace period** (for Day 10+ enforcement)

### Step 5: Monitoring and Reporting

#### View Reports
1. Go to **Reports** > **Endpoint analytics** > **Proactive remediations**
2. Select your remediation package
3. Monitor:
   - **Device status**: Success/failure rates
   - **Detection results**: Devices requiring reboot
   - **Remediation results**: Notifications sent/restarts completed

#### Key Metrics to Monitor
- **Devices detected**: Number of devices requiring reboot
- **Successful remediations**: Notifications successfully displayed
- **Failed remediations**: Devices with errors
- **Compliance trend**: Reduction in devices needing reboot

## Testing Procedures

### Pre-Deployment Testing
1. Run `Test-ToastConfigurations.ps1` to validate all configs
2. Test on pilot group of devices
3. Verify image loading and branding
4. Test forced reboot countdown functionality

### Testing Commands
```powershell
# Test Day 7-8 configuration
.\Test-ToastConfigurations.ps1 -TestScenario "Day7-8" -Force

# Test Day 9 configuration  
.\Test-ToastConfigurations.ps1 -TestScenario "Day9" -Force

# Test Day 10+ forced restart (BE CAREFUL!)
.\Test-ToastConfigurations.ps1 -TestScenario "Day10" -Force

# Test all configurations
.\Test-ToastConfigurations.ps1 -TestScenario "All"

# Interactive testing menu
.\Test-ToastConfigurations.ps1 -TestScenario "Interactive"
```

### Manual Testing
```powershell
# Force run with specific config
.\New-ToastNotification.ps1 -Config "config-toast-NAP-Day7-8.xml" -Force

# Test detection logic
.\Detect-RebootRequired.ps1

# Test remediation logic  
.\Remediate-RebootNotification.ps1
```

## Troubleshooting Common Issues

### Issue: Notifications Not Appearing
**Causes**: 
- Focus Assist enabled
- Notification settings disabled
- Script execution policy

**Solutions**:
- Check Windows notification settings
- Verify script runs as SYSTEM
- Test with `-Force` parameter

### Issue: Images Not Loading
**Causes**:
- Missing image files
- Incorrect file paths
- Insufficient permissions

**Solutions**:
- Verify image files in correct location
- Check file names match config exactly
- Ensure SYSTEM account has read access

### Issue: Forced Restart Not Working
**Causes**:
- User has admin rights to cancel
- Group policy blocking restarts
- Script not running as SYSTEM

**Solutions**:
- Ensure script runs as SYSTEM
- Check for conflicting group policies
- Test with `shutdown /r /t 0 /f`

### Issue: Detection Script Fails
**Causes**:
- WMI/Registry access issues
- PowerShell execution policy
- Missing required modules

**Solutions**:
- Check WMI service status
- Verify PowerShell execution policy
- Test detection logic manually

## Security Considerations

### Permissions Required
- **SYSTEM** account execution for enforcement
- **Read** access to registry keys
- **Write** access for logging
- **Restart** privileges for forced reboot

### Security Best Practices
1. Sign PowerShell scripts if possible
2. Use least privilege principles
3. Monitor script execution logs
4. Regular security review of code
5. Test in isolated environment first

## Maintenance and Updates

### Regular Tasks
- Monitor remediation success rates
- Review device compliance trends  
- Update company branding as needed
- Test new Windows versions compatibility

### Version Control
- Maintain version numbers in scripts
- Document configuration changes
- Test updates in pilot group first
- Rollback plan for issues

## Support and Documentation

### Log Locations
- **Script logs**: `%APPDATA%\ToastNotificationScript\Logs`
- **Intune logs**: Device management portal
- **Windows logs**: Event Viewer > Applications and Services

### Contact Information
- **Script Author**: Michael Luebbert
- **Based on**: Original work by Martin Bengtsson  
- **Support**: Your IT Helpdesk

---

**IMPORTANT**: Always test in a non-production environment first. The Day 10+ configuration will force restart devices automatically!