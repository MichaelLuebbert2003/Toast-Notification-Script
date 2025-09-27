REM This file runs the toast notification script completely hidden from the user
REM Updated to ensure no PowerShell window is visible
powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -NonInteractive -file "C:\ProgramData\ToastNotificationScript\PendingReboot\New-ToastNotification.ps1" -Config "\\YourNetworkPath\ToastNotificationScript\Configs\config-toast-pendingreboot.xml"