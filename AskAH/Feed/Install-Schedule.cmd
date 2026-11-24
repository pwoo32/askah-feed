@echo off
rem Run the AskAH fetcher every 20 minutes in the background (Windows Task Scheduler).
rem Blizzard updates about once an hour; runs in between only ask "anything new?".
rem It starts through Run-Hidden.vbs so no PowerShell window pops up.
schtasks /create /tn "AskAH Feed" /sc minute /mo 20 /f /tr "wscript.exe //B \"%~dp0Run-Hidden.vbs\""
if errorlevel 1 (echo Could not create the task.) else (echo Done: "AskAH Feed" runs every 20 minutes. Remove it with Remove-Schedule.cmd.)
echo.
pause
