Option Explicit

Dim shell, args, command, index

Set shell = CreateObject("WScript.Shell")
Set args = WScript.Arguments

If args.Count < 1 Then
    WScript.Quit 2
End If

command = "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & QuoteArg(args.Item(0))

For index = 1 To args.Count - 1
    command = command & " " & QuoteArg(args.Item(index))
Next

shell.Run command, 0, False

Function QuoteArg(value)
    QuoteArg = """" & CStr(value) & """"
End Function
