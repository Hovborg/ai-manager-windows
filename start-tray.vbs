' Silent launcher. The scheduled task starts PowerShell directly.
Option Explicit
Dim fso, shell, root, pwsh, args, command
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
root = fso.GetParentFolderName(WScript.ScriptFullName)
pwsh = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Microsoft\WindowsApps\pwsh.exe"
If Not fso.FileExists(pwsh) Then pwsh = shell.ExpandEnvironmentStrings("%ProgramFiles%") & "\PowerShell\7\pwsh.exe"
If Not fso.FileExists(pwsh) Then
    MsgBox "PowerShell 7 blev ikke fundet. AI Manager kunne ikke starte.", 16, "AI Manager"
    WScript.Quit 1
End If
args = ""
If WScript.Arguments.Count > 0 Then
    If LCase(WScript.Arguments(0)) = "minimized" Then args = " -StartMinimized"
End If
shell.CurrentDirectory = root
command = Chr(34) & pwsh & Chr(34) & " -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & root & "\ai-tray-updater.ps1" & Chr(34) & args
shell.Run command, 0, False
