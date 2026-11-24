@echo off
rem Fetch WoW Forever auction data once, now.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AskAHFeed.ps1" %*
echo.
pause
