# Quick Testing & Deployment Reference
# Toast Notification System - Configuration Testing and Intune Deployment
# Author: Michael Luebbert

## ✅ Configuration Files Created

All XML configuration files have been created and validated for **completely silent execution**:

- ✅ `config-toast-NAP-Day7-8.xml` - Initial gentle reminder (Days 7-8)
- ✅ `config-toast-NAP-Day9.xml` - Urgent warning (Day 9) 
- ✅ `config-toast-NAP-Day10.xml` - Mandatory restart (Day 10+)
- ✅ `config-toast-reboot.xml` - Default configuration

### 🔕 Silent Execution Features
- **No PowerShell windows** - All scripts run completely hidden
- **Toast notifications only** - Users see notifications, not console windows
- **Background processing** - All detection and remediation runs silently
- **VBS wrapper available** - `Hidden.vbs` for additional invisibility
- **Day 10+ countdown** - Only visible element (intentionally shown for urgency)

## 🧪 Testing Your Configurations

### Quick PowerShell Testing Commands

**Test individual configurations:**
```powershell
# Test Day 7-8 (gentle reminder)
.\New-ToastNotification.ps1 -Config "config-toast-NAP-Day7-8.xml" -Force

# Test Day 9 (urgent warning)  
.\New-ToastNotification.ps1 -Config "config-toast-NAP-Day9.xml" -Force

# Test Day 10+ (mandatory restart - BE CAREFUL!)
.\New-ToastNotification.ps1 -Config "config-toast-NAP-Day10.xml" -Force
```

**Use the comprehensive tester:**
```powershell
# Interactive testing menu
.\Test-ToastConfigurations.ps1 -TestScenario "Interactive"

# Test all configs automatically
.\Test-ToastConfigurations.ps1 -TestScenario "All"

# Test specific scenario
.\Test-ToastConfigurations.ps1 -TestScenario "Day7-8" -Force
```

### Testing Scenarios

#### 🟢 Day 7-8 Testing
- **Expected**: Friendly notification with restart and dismiss buttons (no snooze)
- **User Control**: Restart or Dismiss only (remediation runs every 24 hours)
- **Branding**: "NewAmsterdam Pharma Notification"
- **Safe to test**: ✅ Yes
- **Text**: Centered and uniformly formatted

#### 🟡 Day 9 Testing  
- **Expected**: Urgent warning, no dismiss button, snooze available
- **User Control**: Limited (snooze only)
- **Branding**: "NewAmsterdam Pharma IT Notification"  
- **Safe to test**: ✅ Yes
- **Text**: Centered with warning emojis

#### 🔴 Day 10+ Testing
- **Expected**: Forced restart countdown (60 minutes)
- **User Control**: None (mandatory restart)
- **Branding**: "NewAmsterdam Pharma System Administrator"
- **Safe to test**: ⚠️ CAUTION - Will restart computer!
- **Text**: Centered with urgent formatting

## 🚀 Intune Deployment Options

### Option 1: Single Proactive Remediation (Recommended)

**Benefits:**
- Simpler management
- Dynamic configuration selection
- Single deployment to maintain

**Setup:**
1. Create one Proactive Remediation in Intune
2. Upload `Detect-RebootRequired.ps1` as detection script
3. Upload `Remediate-RebootNotification.ps1` as remediation script
4. Deploy supporting files via Win32 app

**Target:** All Windows devices
**Schedule:** Every 2 hours

### Option 2: Separate Remediations per Stage

**Benefits:**
- Granular control per stage
- Different scheduling per urgency level
- Easier troubleshooting

**Setup:**
Create 3 separate Proactive Remediations:

#### Remediation 1: Day 7-8 Notifications
- **Config**: `config-toast-NAP-Day7-8.xml`
- **Schedule**: Every 4 hours
- **Target**: Devices with 7+ days uptime

#### Remediation 2: Day 9 Notifications
- **Config**: `config-toast-NAP-Day9.xml` 
- **Schedule**: Every 2 hours
- **Target**: Devices with 9+ days uptime

#### Remediation 3: Day 10+ Force Restart
- **Config**: `config-toast-NAP-Day10.xml`
- **Schedule**: Every hour
- **Target**: Devices with 10+ days uptime

## 📦 Deployment Package Creation

Run the package creator to prepare files for Intune:

```powershell
# Create both single and progressive deployment packages
.\Create-IntunePackage.ps1 -DeploymentType "Both" -CreateZip

# Create only single deployment package
.\Create-IntunePackage.ps1 -DeploymentType "Single" -CreateZip

# Create only progressive deployment packages
.\Create-IntunePackage.ps1 -DeploymentType "Progressive" -CreateZip
```

This creates organized folders with all necessary files for Intune deployment.

## 🔧 Intune Configuration Steps

### 1. Navigate to Proactive Remediations
1. Go to [Microsoft Intune admin center](https://intune.microsoft.com)
2. **Reports** → **Endpoint analytics** → **Proactive remediations**
3. Click **Create script package**

### 2. Basic Information
- **Name**: `Reboot Notification System - Progressive Alerts`
- **Description**: `Progressive reboot notifications with automatic restart enforcement`
- **Publisher**: `Your Organization IT`

### 3. Settings
- **Detection script**: Upload `Detect-RebootRequired.ps1`
- **Remediation script**: Upload `Remediate-RebootNotification.ps1`
- **Run using logged on credentials**: **No** (System)
- **Enforce script signature check**: **No**
- **Run in 64-bit PowerShell**: **Yes**

### 4. Assignments
- **Target**: All Windows devices
- **Assignment type**: Required
- **Schedule**: Every 2 hours

### 5. Deploy Support Files
Create Win32 app containing:
- All XML configuration files
- Image assets (PNG/JPG files)
- Main PowerShell script

## 📊 Monitoring & Reporting

### Key Metrics to Watch
- **Devices detected**: Number requiring reboot
- **Successful remediations**: Notifications sent successfully
- **Failed remediations**: Check for errors
- **Compliance improvement**: Reduction in long-uptime devices

### Common Issues & Solutions

#### Notifications Not Appearing
- Check Windows notification settings
- Verify Focus Assist is off
- Ensure script runs as SYSTEM

#### Images Not Loading  
- Verify image files are deployed correctly
- Check file paths in configuration
- Ensure proper permissions on image folder

#### Forced Restart Not Working
- Confirm script runs with SYSTEM privileges
- Check for Group Policy conflicts
- Test manually: `shutdown /r /t 0 /f`

## ⚠️ Important Warnings

### Before Deployment
1. **Test in pilot environment first**
2. **Verify all image assets are available** 
3. **Confirm company branding is correct**
4. **Train helpdesk on new notification system**

### Day 10+ Configuration
🚨 **CRITICAL**: The Day 10+ configuration will automatically restart computers after 60 minutes!

- Always test on isolated systems first
- Ensure users understand the escalation policy
- Have helpdesk ready for support calls
- Consider exclusions for critical systems

## 📞 Support Information

**Script Author**: Michael Luebbert  
**Based on**: Original work by Martin Bengtsson  
**Documentation**: See `Intune-Deployment-Guide.md` for complete details  
**Version**: 2.3.0-ML

## 🎯 Quick Deployment Checklist

- [ ] Test all configurations using `Test-ToastConfigurations.ps1`
- [ ] Verify image assets are present and correctly named
- [ ] Update company branding in config files  
- [ ] Create deployment package using `Create-IntunePackage.ps1`
- [ ] Deploy to pilot group first
- [ ] Create Proactive Remediation in Intune
- [ ] Upload detection and remediation scripts
- [ ] Configure assignment to target devices
- [ ] Deploy supporting files via Win32 app
- [ ] Monitor initial results
- [ ] Roll out to full environment
- [ ] Train support staff on new system

---

**Ready to deploy your progressive reboot notification system! 🚀**