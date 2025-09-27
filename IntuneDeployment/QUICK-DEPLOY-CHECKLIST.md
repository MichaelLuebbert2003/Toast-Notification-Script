# 🎯 Quick Deploy Checklist
## 30-Minute Deployment to Microsoft Intune

### ✅ Pre-Deployment Checklist
- [ ] Downloaded files from GitHub repository
- [ ] Extracted to local folder (e.g., `C:\ToastNotification\`)
- [ ] Have Intune admin access with Proactive Remediation licensing
- [ ] Identified pilot device group (5-10 devices recommended)

---

## 📥 Phase 1: Download (5 minutes)

### GitHub Download:
1. **Go to**: https://github.com/MichaelLuebbert2003/Toast-Notification-Script
2. **Click**: Green "Code" button → "Download ZIP"  
3. **Extract**: ZIP file to `C:\ToastNotification\`
4. **Navigate**: to `C:\ToastNotification\IntuneDeployment\Single-Remediation\`

✅ **Ready**: You now have all 23 deployment files locally

---

## 🏢 Phase 2: Deploy Supporting Files (10 minutes)

### Create Win32 App in Intune:
1. **Open**: [intune.microsoft.com](https://intune.microsoft.com)
2. **Navigate**: Apps → All apps → **Add**
3. **Select**: Windows app (Win32)

### Package Configuration:
```
Package name: ToastNotificationSystem-SupportingFiles
Install command: powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "Install-ToastAssets.ps1"
Uninstall command: powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "Uninstall-ToastAssets.ps1"
Install behavior: System
```

### Detection Rule:
```
Type: Registry
Path: HKLM\SOFTWARE\ToastNotificationSystem
Value: Version
Method: String comparison
Operator: Equals
Value: 2.3.0-ML
```

### Assignment:
- **Target**: All Windows devices (or pilot group)
- **Intent**: Required

✅ **Deploy**: Click "Create" and assign to devices

---

## 🔄 Phase 3: Create Proactive Remediation (10 minutes)

### Navigate to Proactive Remediations:
1. **Go to**: Reports → Endpoint analytics → **Proactive remediations**
2. **Click**: **Create script package**

### Basic Information:
```
Name: Reboot Notification System - Progressive Alerts
Description: Automated reboot notifications with progressive enforcement
Publisher: Your Organization IT
```

### Script Settings:
```
Detection script: Upload "Detect-RebootRequired.ps1"
Remediation script: Upload "Remediate-RebootNotification.ps1"
Run using logged on credentials: NO (use System)
Enforce script signature check: NO
Run in 64-bit PowerShell: YES
```

### Schedule & Assignment:
```
Schedule: Every 4-6 hours
Assignment: All Windows devices (or pilot group)
Assignment type: Required
```

✅ **Create**: Your remediation is now deployed

---

## 🧪 Phase 4: Test & Verify (5 minutes)

### Manual Test (On pilot device):
```powershell
# Open PowerShell as Administrator on test device
cd "C:\Program Files\ToastNotificationSystem\Scripts"

# Test gentle notification (safe to run)
.\New-ToastNotification.ps1 -Config "..\Config\config-toast-NAP-Day7-8.xml" -Force
```

### Monitor in Intune:
1. **Win32 App**: Apps → Your app → Device install status
2. **Remediation**: Reports → Endpoint analytics → Your remediation → Device status

✅ **Success**: You should see notifications appearing and devices reporting success

---

## 📊 Expected Timeline & Results

### **Week 1**: System Learning
- Install on pilot devices
- Users see first notifications
- Monitor compliance baseline

### **Week 2-3**: Progressive Improvement
- Day 7-8: 40-60% voluntary restarts
- Day 9: 70-80% compliance
- Day 10+: 95%+ forced compliance

### **Month 1**: Full Production
- Deploy to all devices
- Average uptime < 7 days
- Reduced help desk tickets

---

## 🆘 Quick Troubleshooting

### No Notifications Appearing?
```powershell
# Check on affected device:
Get-Service -Name "WpnUserService*"  # Notification service
Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name "NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND"
```

### Scripts Not Running?
```powershell
# Check execution policy:
Get-ExecutionPolicy -List

# Check if files installed:
Test-Path "C:\Program Files\ToastNotificationSystem\Scripts\New-ToastNotification.ps1"
```

### Remediation Failures?
1. **Check**: Device compliance in Intune portal
2. **Review**: PowerShell event logs on affected devices  
3. **Verify**: SYSTEM account permissions

---

## 🎉 Deployment Success!

When successful, you'll see:
- ✅ **Win32 app**: Installed on all target devices
- ✅ **Remediation**: Running every 4-6 hours with success results
- ✅ **Notifications**: Appearing on devices with professional NAP branding
- ✅ **Compliance**: Increasing daily as users respond to notifications

### **Your enterprise now has**:
- Professional reboot notifications with custom branding
- Progressive enforcement (gentle → urgent → mandatory)  
- 60-minute countdown timer for forced restarts
- Complete Intune integration and monitoring
- Automated compliance management

🚀 **Congratulations! Your toast notification system is deployed and protecting your enterprise!**

---

## 📞 Need Help?

- **Review**: Full documentation in `DOWNLOAD-AND-DEPLOY.md`
- **Check**: Individual deployment guides in each folder
- **Contact**: Your IT Help Desk or script author Michael Luebbert

**You're now running an enterprise-grade reboot notification system!** 🎯