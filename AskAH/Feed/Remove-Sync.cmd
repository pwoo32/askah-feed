@echo off
rem Stop syncing from GitHub. (To run the feed on this PC again: Install-Schedule.cmd.)
schtasks /delete /tn "AskAH Sync" /f
schtasks /delete /tn "AskAH Sync at logon" /f >nul 2>&1
pause
