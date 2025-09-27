# 📥 Download and Deploy Guide
## Complete Step-by-Step Instructions for Microsoft Intune Deployment

### 🎯 Overview
This guide will walk you through downloading your toast notification system from GitHub and deploying it to Microsoft Intune in under 60 minutes.

---

## 📥 STEP 1: Download Your System

### Option A: Download ZIP from GitHub (Easiest)
1. **Go to your repository**: `https://github.com/MichaelLuebbert2003/Toast-Notification-Script`
2. **Click the green "Code" button**
3. **Select "Download ZIP"**
4. **Extract the ZIP file** to your local machine (e.g., `C:\ToastNotification\`)

### Option B: Git Clone (If you have Git installed)
```bash
git clone https://github.com/MichaelLuebbert2003/Toast-Notification-Script.git
cd Toast-Notification-Script
```

### 🎯 Choose Your Deployment Approach

After downloading, you'll have two deployment options in the `IntuneDeployment` folder:

#### 🚀 **RECOMMENDED**: Single Remediation (Simple & Fast)
- **Path**: `IntuneDeployment/Single-Remediation/`
- **Time**: 30 minutes
- **Complexity**: Easy
- **Best for**: Most organizations

#### 🎛️ **ADVANCED**: Progressive Remediations (Maximum Control)
- **Path**: `IntuneDeployment/Progressive-Remediations/`  
- **Time**: 90 minutes
- **Complexity**: Advanced
- **Best for**: Large enterprises

---

## 🚀 STEP 2: Deploy Single Remediation (RECOMMENDED)

### 📁 Prepare Your Files
1. **Navigate to**: `IntuneDeployment/Single-Remediation/`
2. **You'll see these key files**:
   - `Detect-RebootRequired.ps1` (Detection script)
   - `Remediate-RebootNotification.ps1` (Remediation script)
   - `Install-ToastAssets.ps1` (Supporting files installer)
   - All script files, configs, and images

### 🏢 Deploy Supporting Files (Win32 App)

#### Create Win32 App Package:
1. **Open Microsoft Intune admin center**: [https://intune.microsoft.com](https://intune.microsoft.com)
2. **Navigate to**: Apps → All apps → Add
3. **Select**: Windows app (Win32)
4. **Upload**: Create a ZIP file with these contents:
   ```
   ToastNotificationAssets.zip:
   ├── Install-ToastAssets.ps1
   ├── Uninstall-ToastAssets.ps1
   ├── New-ToastNotification.ps1
   ├── Invoke-ToastHidden.ps1
   ├── Hidden.vbs
   ├── RunToastHidden.cmd
   ├── config-toast-NAP-Day7-8.xml
   ├── config-toast-NAP-Day9.xml
   ├── config-toast-NAP-Day10.xml
   ├── config-toast-reboot.xml
   └── Images/
       ├── ToastLogoImageNAP.png
       ├── Nap-HeroToast.jpg
       ├── ToastLogoImageDefault.jpg
       └── ToastHeroImageDefault.jpg
   ```

#### Configure Win32 App:
- **Name**: `Toast Notification System - Supporting Files`
- **Description**: `Supporting files for enterprise reboot notifications`
- **Publisher**: `Your Organization IT`
- **Install command**: `powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "Install-ToastAssets.ps1"`
- **Uninstall command**: `powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "Uninstall-ToastAssets.ps1"`
- **Install behavior**: System
- **Device restart behavior**: No specific action
- **Return codes**: Use default

#### Detection Rules:
- **Rule type**: Registry
- **Key path**: `HKEY_LOCAL_MACHINE\SOFTWARE\ToastNotificationSystem`
- **Value name**: `Version`
- **Detection method**: String comparison
- **Operator**: Equals
- **Value**: `2.3.0-ML`

#### Assignment:
- **Assignment type**: Required
- **Target group**: All Windows devices (or your pilot group)

### 🔄 Create Proactive Remediation

#### Navigate to Proactive Remediations:
1. **Go to**: Reports → Endpoint analytics → Proactive remediations
2. **Click**: Create script package

#### Basic Information:
- **Name**: `Reboot Notification System - Progressive Alerts`
- **Description**: `Automated reboot notifications with progressive enforcement (Day 7-8 → Day 9 → Day 10+)`
- **Publisher**: `Your Organization IT`

#### Settings:
- **Detection script**: Upload `Detect-RebootRequired.ps1` from your folder
- **Remediation script**: Upload `Remediate-RebootNotification.ps1` from your folder
- **Run this script using logged on credentials**: **No** (System context)
- **Enforce script signature check**: **No**
- **Run script in 64-bit PowerShell**: **Yes**

#### Assignments:
- **Target**: All Windows devices (or start with pilot group)
- **Schedule**: Every 4-6 hours (recommended)
- **Assignment type**: Required

### ✅ Verify Deployment

#### Check Win32 App:
1. **Monitor installation** in Apps → All apps → Your app → Device install status
2. **Verify** devices show "Installed" status

#### Check Proactive Remediation:
1. **Monitor results** in Reports → Endpoint analytics → Proactive remediations → Your remediation
2. **Watch for**:
   - Devices detected (needing reboot)
   - Successful remediations (notifications sent)
   - Any failures to troubleshoot

---

## 🎛️ STEP 3: Deploy Progressive Remediations (ADVANCED)

### 📁 Prepare Your Files
1. **Navigate to**: `IntuneDeployment/Progressive-Remediations/`
2. **Same supporting files deployment** as above
3. **Create THREE separate remediations**:

#### Remediation 1: Day 7-8 Gentle Reminders
- **Name**: `Reboot Alerts - Day 7-8 (Gentle Reminders)`
- **Detection**: `Detect-RebootRequired.ps1` (modify to check 7-8 days)
- **Remediation**: `Remediate-RebootNotification.ps1` (modify for Day 7-8 config)
- **Schedule**: Every 6 hours

#### Remediation 2: Day 9 Urgent Notices  
- **Name**: `Reboot Alerts - Day 9 (Urgent Notices)`
- **Detection**: `Detect-RebootRequired.ps1` (modify to check 9 days)
- **Remediation**: `Remediate-RebootNotification.ps1` (modify for Day 9 config)
- **Schedule**: Every 4 hours

#### Remediation 3: Day 10+ Mandatory Restart
- **Name**: `Reboot Alerts - Day 10+ (Mandatory Restart)`
- **Detection**: `Detect-RebootRequired.ps1` (modify to check 10+ days)
- **Remediation**: `Remediate-RebootNotification.ps1` (modify for Day 10+ config)
- **Schedule**: Every 2 hours
- **⚠️ WARNING**: This will force restart devices!

---

## 🧪 STEP 4: Test Before Full Deployment

### Create Test Device Group
1. **In Intune**: Groups → New group
2. **Name**: `Toast Notification Pilot`
3. **Add 5-10 test devices**

### Test Each Scenario
Before full deployment, test manually on a pilot device:

```powershell
# Navigate to installation folder on test device
cd "C:\Program Files\ToastNotificationSystem\Scripts"

# Test Day 7-8 notification (safe)
.\New-ToastNotification.ps1 -Config "..\Config\config-toast-NAP-Day7-8.xml" -Force

# Test Day 9 notification (safe)  
.\New-ToastNotification.ps1 -Config "..\Config\config-toast-NAP-Day9.xml" -Force

# ⚠️ CAREFUL: This will restart the device after 60 minutes!
# .\New-ToastNotification.ps1 -Config "..\Config\config-toast-NAP-Day10.xml" -Force
```

### Verify Pilot Success
1. **Check notifications appear** correctly on pilot devices
2. **Verify branding and messaging** looks professional
3. **Confirm buttons work** as expected
4. **Test countdown timer** functionality (Day 10+ scenario)

---

## 📊 STEP 5: Monitor and Maintain

### Daily Monitoring (First Week)
1. **Check Proactive Remediation dashboard** for success/failure rates
2. **Monitor help desk tickets** for user questions
3. **Review device compliance** trends

### Weekly Reporting
1. **Generate compliance reports** showing reboot frequency
2. **Track user adoption** of voluntary restarts
3. **Measure reduction** in devices requiring forced restart

### Monthly Optimization
1. **Adjust schedules** based on user behavior
2. **Update messaging** if needed
3. **Expand to additional device groups**

---

## 🆘 Troubleshooting Common Issues

### Problem: Notifications Not Appearing
**Solution**:
1. Check Windows notification settings on affected devices
2. Verify Focus Assist is not blocking notifications
3. Confirm scripts are running with SYSTEM privileges
4. Check Windows Event Log for toast notification errors

### Problem: Images Not Loading
**Solution**:
1. Verify Win32 app deployed successfully
2. Check file paths in XML configuration files
3. Ensure SYSTEM account has read access to image files
4. Test image paths manually on affected device

### Problem: Forced Restart Not Working
**Solution**:
1. Confirm script has admin/SYSTEM privileges
2. Check for Group Policy conflicts preventing shutdown
3. Verify shutdown.exe is accessible and functional
4. Review script logs for specific error messages

### Problem: High Failure Rates in Remediation
**Solution**:
1. Check PowerShell execution policy on devices
2. Verify script file integrity and permissions
3. Review Intune deployment status
4. Check for antivirus interference with PowerShell scripts

---

## 📞 Get Help

### Documentation Resources
- **Main README**: `IntuneDeployment/README.md`
- **Detailed guides**: In each deployment folder
- **Script documentation**: Comments within PowerShell files

### Log Locations
- **Installation logs**: `%TEMP%\ToastNotificationInstall.log`
- **Script logs**: `%APPDATA%\ToastNotificationScript\Logs`
- **Intune logs**: Device management portal → Devices → [Device] → Monitor

### Support Contacts
- **Script Author**: Michael Luebbert
- **Original Creator**: Martin Bengtsson
- **Your IT Help Desk**: [Add your contact info]

---

## 🎉 Deployment Complete!

**Congratulations!** You've successfully deployed your enterprise toast notification system. Your users will now receive:

- 🔄 **Gentle reminders** at Day 7-8 with dismiss options
- ⚠️ **Urgent notices** at Day 9 with snooze capability  
- 🚨 **Mandatory restart** at Day 10+ with 60-minute countdown

**Expected results**: 95%+ device compliance within 30 days, reduced help desk tickets, improved security posture, and happier users with professional reboot notifications!

🚀 **Your enterprise is now running a world-class reboot notification system!**