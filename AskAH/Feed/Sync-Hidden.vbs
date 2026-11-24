' Runs Sync.ps1 with no window at all (Task Scheduler uses this).
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "\Sync.ps1"""
CreateObject("WScript.Shell").Run cmd, 0, False
