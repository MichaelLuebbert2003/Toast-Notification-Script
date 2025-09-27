# Single Proactive Remediation Deployment Guide
## Toast Notification System - Recommended Approach

### 📋 Overview
This package contains everything needed to deploy the toast notification system as a single Proactive Remediation in Microsoft Intune.

### 🎯 What This Package Includes
- **Detect-RebootRequired.ps1** - Detection script for Intune
- **Remediate-RebootNotification.ps1** - Remediation script for Intune
- **New-ToastNotification.ps1** - Main toast notification engine
- **Invoke-ToastHidden.ps1** - Silent launcher
- **Config Files** - All 4 XML configurations (Day 7-8, Day 9, Day 10+, Default)
- **Image Assets** - NAP branded logos and hero images
- **Helper Files** - VBS and CMD wrappers for silent execution

### 🚀 Quick Deployment Steps

#### Step 1: Create Proactive Remediation
1. Sign in to [Microsoft Intune admin center](https://intune.microsoft.com)
2. Go to **Reports** → **Endpoint analytics** → **Proactive remediations**
3. Click **Create script package**

#### Step 2: Basic Information
- **Name**: `Reboot Notification System - Progressive Alerts`
- **Description**: `Progressive reboot notifications with automatic restart enforcement (Day 7-8 → Day 9 → Day 10+)`
- **Publisher**: `Your Organization IT`

#### Step 3: Settings
- **Detection script file**: Upload `Detect-RebootRequired.ps1`
- **Remediation script file**: Upload `Remediate-RebootNotification.ps1`
- **Run this script using the logged on credentials**: **No** (Run as System)
- **Enforce script signature check**: **No**
- **Run script in 64 bit PowerShell Host**: **Yes**

#### Step 4: Assignment
- **Target**: All Windows devices or specific device groups
- **Assignment type**: **Required**
- **Schedule**: Every 4-6 hours (recommended for responsive notifications)

#### Step 5: Deploy Supporting Files
Create a Win32 app to deploy the supporting files:

##### Win32 App Package Contents:
```
Supporting-Files/
├── New-ToastNotification.ps1
├── Invoke-ToastHidden.ps1
├── config-toast-NAP-Day7-8.xml
├── config-toast-NAP-Day9.xml
├── config-toast-NAP-Day10.xml
├── config-toast-reboot.xml
├── Hidden.vbs
├── RunToastHidden.cmd
└── Images/
    ├── ToastLogoImageNAP.png
    ├── Nap-HeroToast.jpg
    ├── ToastLogoImageDefault.jpg
    └── ToastHeroImageDefault.jpg
```

##### Win32 App Settings:
- **Install command**: `powershell.exe -ExecutionPolicy Bypass -File "Install-ToastAssets.ps1"`
- **Uninstall command**: `powershell.exe -ExecutionPolicy Bypass -File "Uninstall-ToastAssets.ps1"`
- **Install behavior**: System
- **Assignment**: Required to All Devices

### 🔄 How It Works

1. **Proactive Remediation runs every 4-6 hours**
2. **Detection script** checks:
   - System uptime (days)
   - Pending reboots in registry
   - Pending reboots in WMI (ConfigMgr)
3. **If remediation needed**:
   - Remediation script determines uptime stage
   - Selects appropriate config (Day 7-8, Day 9, or Day 10+)
   - Launches toast notification silently
   - Day 10+ triggers 60-minute countdown timer

### 📊 Monitoring & Reporting

#### View Results:
1. Go to **Reports** → **Endpoint analytics** → **Proactive remediations**
2. Select your remediation package
3. Monitor:
   - **Device status**: Success/failure rates
   - **Detection results**: Devices requiring reboot
   - **Remediation results**: Notifications sent successfully

#### Key Metrics:
- **Devices detected**: Number of devices needing reboot
- **Successful remediations**: Notifications displayed successfully
- **Failed remediations**: Devices with errors
- **Compliance trend**: Reduction in devices requiring reboot over time

### ⚡ Benefits of Single Remediation Approach

- ✅ **Simpler management** - One remediation to maintain
- ✅ **Dynamic logic** - Automatically selects correct notification stage
- ✅ **Unified reporting** - All metrics in one place
- ✅ **Easier troubleshooting** - Single point of failure analysis
- ✅ **Cost effective** - Less Intune overhead

### 🧪 Testing Before Production

1. **Create test device group** with 5-10 devices
2. **Deploy to test group first**
3. **Test scenarios**:
   ```powershell
   # Force Day 7-8 notification
   .\New-ToastNotification.ps1 -Config "config-toast-NAP-Day7-8.xml" -Force
   
   # Force Day 9 notification
   .\New-ToastNotification.ps1 -Config "config-toast-NAP-Day9.xml" -Force
   
   # Force Day 10+ notification (BE CAREFUL - will restart!)
   .\New-ToastNotification.ps1 -Config "config-toast-NAP-Day10.xml" -Force
   ```

### 🛠️ Troubleshooting

#### Common Issues:
1. **Notifications not appearing**:
   - Check Windows notification settings
   - Verify script runs as SYSTEM
   - Check Focus Assist settings

2. **Images not loading**:
   - Verify Win32 app deployed successfully
   - Check file paths in configurations
   - Ensure SYSTEM has read access to image files

3. **Forced restart not working**:
   - Confirm script runs with SYSTEM privileges
   - Check for Group Policy conflicts
   - Verify shutdown.exe permissions

#### Log Locations:
- **Script logs**: `%APPDATA%\ToastNotificationScript\Logs`
- **Intune logs**: Device management portal
- **Windows Event Log**: Application log, source "IntuneRebootRemediation"

### 📞 Support Information

- **Script Author**: Michael Luebbert
- **Based on**: Original work by Martin Bengtsson
- **Version**: 2.3.0-ML
- **Support**: Your IT Helpdesk

---

## ⚠️ IMPORTANT REMINDERS

- **Test in pilot environment first**
- **Day 10+ configuration will force restart devices**
- **Ensure helpdesk is prepared for user questions**
- **Monitor compliance trends to measure effectiveness**

**Your enterprise toast notification system is ready for deployment!** 🎉