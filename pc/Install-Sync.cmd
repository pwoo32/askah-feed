@echo off
rem Switch this PC from running the AH feed to syncing it from GitHub.
rem Stops the old "AskAH Feed" task, then keeps your addon files up to date
rem from GitHub every 20 minutes and when you log in. No windows pop up.
schtasks /delete /tn "AskAH Feed" /f >nul 2>&1
if not exist "%~dp0sync.json" (
  echo Make sync.json first: copy sync.example.json, put in your repo and token.
  pause
  exit /b 1
)
schtasks /create /tn "AskAH Sync" /sc minute /mo 20 /f /tr "wscript.exe //B \"%~dp0Sync-Hidden.vbs\"" >nul
if errorlevel 1 (echo Could not create the 20-minute task.) else (echo "AskAH Sync" runs every 20 minutes.)
schtasks /create /tn "AskAH Sync at logon" /sc onlogon /f /tr "wscript.exe //B \"%~dp0Sync-Hidden.vbs\"" >nul 2>&1
if errorlevel 1 (echo The at-logon task needs admin rights; skipped. The 20-minute task covers it.) else (echo It also runs when you log in to Windows.)
echo.
echo Syncing once now...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync.ps1"
echo.
echo Done. Remove-Sync.cmd undoes this.
pause
