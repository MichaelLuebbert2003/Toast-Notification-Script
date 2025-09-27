# Toast Notification Script - Reboot-Only Edition

## Current version: 2.3.0-ML

**Customized by Michael Luebbert** - Based on original work by Martin Bengtsson  
**Focus**: Progressive reboot notifications for enterprise environments

This customized version focuses solely on reboot-related functionality with enhanced auto-reboot capabilities and progressive notification system.

## What's New

- 2.3.0 – Added the Register-CustomNotificationApp function
   - This function retrieves the value of the CustomNotificationApp option from the config.xml
      - The function then uses this name, to create a custom app for doing the notification
      - This will reflect in the shown toast notification, instead of Software Center or PowerShell
   - This also creates the custom notifcation app with a prevention from disabling the toast notifications via the UI
