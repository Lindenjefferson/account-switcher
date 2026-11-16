@echo off
rem Called when the shortcut (e.g. "cc" or "cc account") is typed in the Explorer address bar, through App Paths.
rem Opens PowerShell in the Explorer folder, already running Claude; when Claude exits, you stay in PowerShell.
powershell.exe -NoLogo -NoExit -ExecutionPolicy Bypass -File "%~dp0claude-here.ps1" %*
