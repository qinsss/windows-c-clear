Option Explicit

Dim shell, fso, baseDir, scriptPath, windowsPowerShell, powerShell7, engine
Dim command, argument

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(baseDir, "src\WindowsCClear.ps1")
windowsPowerShell = fso.BuildPath(shell.ExpandEnvironmentStrings("%SystemRoot%"), "System32\WindowsPowerShell\v1.0\powershell.exe")
powerShell7 = fso.BuildPath(shell.ExpandEnvironmentStrings("%ProgramFiles%"), "PowerShell\7\pwsh.exe")

If fso.FileExists(windowsPowerShell) Then
    engine = windowsPowerShell
ElseIf fso.FileExists(powerShell7) Then
    engine = powerShell7
Else
    MsgBox "PowerShell runtime was not found. Please enable Windows PowerShell or install PowerShell 7.", 16, "Windows C Clear"
    WScript.Quit 9009
End If
command = Quote(engine) & " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Quote(scriptPath)
For Each argument In WScript.Arguments
    command = command & " " & Quote(CStr(argument))
Next

' Window style 0 hides the console. The WPF application window remains visible.
shell.Run command, 0, False

Function Quote(ByVal value)
    Quote = Chr(34) & Replace(value, Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function
