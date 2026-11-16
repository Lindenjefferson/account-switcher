@echo off
rem cc [account] [args]: opens Claude Code as the chosen account (see %USERPROFILE%\.claude-accounts\accounts.json).
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\cc.ps1" %*
