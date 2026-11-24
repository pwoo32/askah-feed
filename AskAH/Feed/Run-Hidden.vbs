' Runs AskAHFeed.ps1 with no window at all (Task Scheduler uses this).
' powershell -WindowStyle Hidden still flashes a window for a moment; wscript does not.
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "\AskAHFeed.ps1"""
CreateObject("WScript.Shell").Run cmd, 0, False
