[CmdletBinding()]
param(
    [ValidateSet('inspect', 'open-chatgpt', 'open-chat-list', 'open-chat', 'copy-latest', 'send-receive')]
    [string]$Action = 'inspect',
    [string]$TargetTitle = 'Design Studio',
    [string]$ExpectedMarker = '',
    [string]$Prompt = '',
    [string]$PromptPath = '',
    [ValidateRange(15, 900)]
    [int]$TimeoutSeconds = 180,
    [string]$OriginThreadId = $env:CODEX_THREAD_ID,
    [string]$EndpointConfigPath = '',
    [switch]$SmokeTestOverride,
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($EndpointConfigPath)) {
    $EndpointConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'references\design-studio-endpoint.json'
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ChatGptDesktopNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte virtualKey, byte scanCode, uint flags, UIntPtr extraInfo);
}
'@

$script:AsTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1
    } |
    Select-Object -First 1

function Wait-WinRt {
    param($Operation, [Type]$ResultType)

    $method = $script:AsTaskGeneric.MakeGenericMethod($ResultType)
    $task = $method.Invoke($null, @($Operation))
    $task.Wait()
    return $task.Result
}

function Get-ChatGptWindow {
    $windows = @(Get-Process ChatGPT -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -ne 0)
    if ($windows.Count -ne 1) {
        throw "Expected one visible ChatGPT desktop window; found $($windows.Count)."
    }
    return $windows[0]
}

function Get-WindowSnapshot {
    param([System.Diagnostics.Process]$Process)

    $rect = New-Object ChatGptDesktopNative+RECT
    if (-not [ChatGptDesktopNative]::GetWindowRect($Process.MainWindowHandle, [ref]$rect)) {
        throw 'Could not read the ChatGPT desktop window bounds.'
    }

    $width = [int]$rect.Right - [int]$rect.Left
    $height = [int]$rect.Bottom - [int]$rect.Top
    if ($width -lt 800 -or $height -lt 500) {
        throw "ChatGPT desktop window is too small for a verified route: ${width}x${height}."
    }

    $path = if ($OutputPath) {
        [IO.Path]::GetFullPath($OutputPath)
    } else {
        Join-Path $env:TEMP ("chatgpt-desktop-{0}.png" -f [guid]::NewGuid().ToString('N'))
    }
    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
        $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    $file = Wait-WinRt ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
    $stream = Wait-WinRt ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    try {
        $decoder = Wait-WinRt ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $softwareBitmap = Wait-WinRt ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
        if ($null -eq $engine) {
            throw 'Windows OCR is unavailable.'
        }
        $ocr = Wait-WinRt ($engine.RecognizeAsync($softwareBitmap)) ([Windows.Media.Ocr.OcrResult])
    } finally {
        $stream.Dispose()
    }

    return [pscustomobject]@{
        Path = $path
        WindowLeft = [int]$rect.Left
        WindowTop = [int]$rect.Top
        Width = $width
        Height = $height
        Ocr = $ocr
    }
}

function Get-OcrWordMatches {
    param(
        $Snapshot,
        [string]$Text,
        [int]$MaximumX = [int]::MaxValue,
        [int]$MaximumY = [int]::MaxValue
    )

    $matches = @(
        foreach ($line in $Snapshot.Ocr.Lines) {
            foreach ($word in $line.Words) {
                if ($word.Text.Equals($Text, [StringComparison]::OrdinalIgnoreCase) -and
                    $word.BoundingRect.X -lt $MaximumX -and
                    $word.BoundingRect.Y -lt $MaximumY) {
                    $word
                }
            }
        }
    )
    return $matches
}

function Find-OcrWord {
    param(
        $Snapshot,
        [string]$Text,
        [int]$MaximumX = [int]::MaxValue,
        [int]$MaximumY = [int]::MaxValue
    )

    $matches = @(Get-OcrWordMatches $Snapshot $Text $MaximumX $MaximumY)
    if ($matches.Count -ne 1) {
        throw "Expected one OCR word '$Text' before x=$MaximumX and y=$MaximumY; found $($matches.Count)."
    }
    return $matches[0]
}

function Get-LineBounds {
    param($Line)

    $words = @($Line.Words)
    $left = ($words | ForEach-Object BoundingRect | Measure-Object X -Minimum).Minimum
    $top = ($words | ForEach-Object BoundingRect | Measure-Object Y -Minimum).Minimum
    $right = ($words | ForEach-Object { $_.BoundingRect.X + $_.BoundingRect.Width } | Measure-Object -Maximum).Maximum
    $bottom = ($words | ForEach-Object { $_.BoundingRect.Y + $_.BoundingRect.Height } | Measure-Object -Maximum).Maximum
    return [pscustomobject]@{ X = $left; Y = $top; Width = $right - $left; Height = $bottom - $top }
}

function Get-OcrLineMatches {
    param(
        $Snapshot,
        [string]$Text,
        [int]$MinimumX = 0,
        [int]$MaximumX = [int]::MaxValue
    )

    $matches = @(
        foreach ($line in $Snapshot.Ocr.Lines) {
            $normalized = ($line.Text -replace '\s+', ' ').Trim()
            if ($normalized.Equals($Text, [StringComparison]::OrdinalIgnoreCase)) {
                $bounds = Get-LineBounds $line
                if ($bounds.X -ge $MinimumX -and $bounds.X -lt $MaximumX) {
                    [pscustomobject]@{ Line = $line; Bounds = $bounds }
                }
            }
        }
    )
    return $matches
}

function Find-OcrLine {
    param(
        $Snapshot,
        [string]$Text,
        [int]$MinimumX = 0,
        [int]$MaximumX = [int]::MaxValue
    )

    $matches = @(Get-OcrLineMatches $Snapshot $Text $MinimumX $MaximumX)
    if ($matches.Count -ne 1) {
        throw "Expected one OCR line '$Text' from x=$MinimumX to x=$MaximumX; found $($matches.Count)."
    }
    return $matches[0]
}

function Invoke-VerifiedClick {
    param($Snapshot, $Bounds)

    $screenX = [int]($Snapshot.WindowLeft + $Bounds.X + ($Bounds.Width / 2))
    $screenY = [int]($Snapshot.WindowTop + $Bounds.Y + ($Bounds.Height / 2))
    [ChatGptDesktopNative]::SetCursorPos($screenX, $screenY) | Out-Null
    [ChatGptDesktopNative]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
    [ChatGptDesktopNative]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
}

function Invoke-Hotkey {
    param([byte[]]$Keys)

    foreach ($key in $Keys) {
        [ChatGptDesktopNative]::keybd_event($key, 0, 0, [UIntPtr]::Zero)
    }
    for ($index = $Keys.Length - 1; $index -ge 0; $index--) {
        [ChatGptDesktopNative]::keybd_event($Keys[$index], 0, 2, [UIntPtr]::Zero)
    }
}

function Invoke-Key {
    param([byte]$Key)

    [ChatGptDesktopNative]::keybd_event($Key, 0, 0, [UIntPtr]::Zero)
    [ChatGptDesktopNative]::keybd_event($Key, 0, 2, [UIntPtr]::Zero)
}

function Invoke-VerifiedPoint {
    param($Snapshot, [double]$X, [double]$Y)

    if ($X -lt 0 -or $Y -lt 0 -or $X -ge $Snapshot.Width -or $Y -ge $Snapshot.Height) {
        throw "Refusing click outside verified ChatGPT window bounds: x=$X y=$Y."
    }
    $screenX = [int]($Snapshot.WindowLeft + $X)
    $screenY = [int]($Snapshot.WindowTop + $Y)
    [ChatGptDesktopNative]::SetCursorPos($screenX, $screenY) | Out-Null
    [ChatGptDesktopNative]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
    [ChatGptDesktopNative]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
}

function Get-OcrLinePatternMatches {
    param(
        $Snapshot,
        [string]$Pattern,
        [int]$MinimumX = 0,
        [int]$MaximumX = [int]::MaxValue,
        [int]$MinimumY = 0,
        [int]$MaximumY = [int]::MaxValue
    )

    return @(
        foreach ($line in $Snapshot.Ocr.Lines) {
            $bounds = Get-LineBounds $line
            $normalized = ($line.Text -replace '\s+', ' ').Trim()
            if ($normalized -match $Pattern -and
                $bounds.X -ge $MinimumX -and $bounds.X -lt $MaximumX -and
                $bounds.Y -ge $MinimumY -and $bounds.Y -lt $MaximumY) {
                [pscustomobject]@{ Line = $line; Bounds = $bounds }
            }
        }
    )
}

function Dismiss-CommandOverlay {
    param([System.Diagnostics.Process]$Process, $Snapshot)

    $matches = @(Get-OcrLinePatternMatches $Snapshot '(?i)(search tasks|run a command)' 500 1400 150 500)
    if ($matches.Count -gt 0) {
        Invoke-Key 0x1B
        Start-Sleep -Milliseconds 500
        return Get-WindowSnapshot $Process
    }
    return $Snapshot
}

function Get-WorkView {
    param([System.Diagnostics.Process]$Process, $Snapshot)

    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $chatNavMatches = @(Get-OcrWordMatches $Snapshot 'Chat' 250 320)
        if ($chatNavMatches.Count -eq 1) {
            return $Snapshot
        }
        if ($attempt -lt 2) {
            Start-Sleep -Milliseconds 350
            $Snapshot = Get-WindowSnapshot $Process
        }
    }

    $workMatches = @(Get-OcrWordMatches $Snapshot 'Work' 250 220)
    if ($workMatches.Count -eq 1) {
        Invoke-VerifiedClick $Snapshot $workMatches[0].BoundingRect
    } elseif ($workMatches.Count -eq 0) {
        $chatGptWord = Find-OcrWord $Snapshot 'ChatGPT' 200 120
        Invoke-VerifiedClick $Snapshot $chatGptWord.BoundingRect
        Start-Sleep -Milliseconds 500
        $modeMenu = Get-WindowSnapshot $Process
        $workWord = Find-OcrWord $modeMenu 'Work' 250 220
        Invoke-VerifiedClick $modeMenu $workWord.BoundingRect
    } else {
        throw "Expected zero or one ChatGPT Work menu entry; found $($workMatches.Count)."
    }

    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        Start-Sleep -Milliseconds 600
        $candidate = Get-WindowSnapshot $Process
        $chatMatches = @(Get-OcrWordMatches $candidate 'Chat' 250 320)
        if ($chatMatches.Count -eq 1) {
            return $candidate
        }
    }
    throw 'ChatGPT Work navigation did not become ready.'
}

function Get-ChatPanelState {
    param($Snapshot, [string]$Title)

    $minimumPanelX = [int]($Snapshot.Width * 0.68)
    $minimumComposerY = [int]($Snapshot.Height * 0.70)
    $minimumHeaderY = [int]($Snapshot.Height * 0.30)
    $maximumHeaderY = [int]($Snapshot.Height * 0.55)
    return [pscustomobject]@{
        Composer = @(Get-OcrLinePatternMatches $Snapshot '(?i)essage.*Cha' $minimumPanelX $Snapshot.Width $minimumComposerY $Snapshot.Height)
        Busy = @(Get-OcrLinePatternMatches $Snapshot '(?i)^Thinking\b' $minimumPanelX $Snapshot.Width 0 $Snapshot.Height)
        History = @(Get-OcrLinePatternMatches $Snapshot '(?i)history$' $minimumPanelX $Snapshot.Width $minimumHeaderY $maximumHeaderY)
        Title = @(Get-OcrLinePatternMatches $Snapshot ("(?i)^{0}$" -f [regex]::Escape($Title)) $minimumPanelX $Snapshot.Width $minimumHeaderY $maximumHeaderY)
        AddToTask = @(Get-OcrLinePatternMatches $Snapshot '(?i)a[d\s]*d\s+to\s+task' $minimumPanelX $Snapshot.Width $minimumHeaderY $maximumHeaderY)
    }
}

function Open-ExactChatPanel {
    param([System.Diagnostics.Process]$Process, $WorkView, [string]$Title)

    $snapshot = $WorkView
    $state = Get-ChatPanelState $snapshot $Title
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        if ($state.Composer.Count -eq 1 -or $state.AddToTask.Count -gt 0 -or $state.History.Count -gt 0) {
            break
        }
        Start-Sleep -Milliseconds 400
        $snapshot = Get-WindowSnapshot $Process
        $state = Get-ChatPanelState $snapshot $Title
    }
    if ($state.Composer.Count -eq 0 -and $state.AddToTask.Count -eq 0 -and $state.History.Count -eq 0) {
        $chatWord = Find-OcrWord $snapshot 'Chat' 250 320
        $chatBounds = $chatWord.BoundingRect
        Invoke-VerifiedPoint $snapshot ($chatBounds.X - 18) ($chatBounds.Y + ($chatBounds.Height / 2))
        for ($attempt = 0; $attempt -lt 6; $attempt++) {
            Start-Sleep -Milliseconds 600
            $snapshot = Get-WindowSnapshot $Process
            $state = Get-ChatPanelState $snapshot $Title
            if ($state.Composer.Count -gt 0 -or $state.AddToTask.Count -gt 0 -or $state.History.Count -gt 0) {
                break
            }
        }
        if ($state.Composer.Count -eq 0 -and $state.AddToTask.Count -eq 0 -and $state.History.Count -eq 0) {
            $recentMatches = @(Get-OcrLinePatternMatches $snapshot ("(?i)^{0}$" -f [regex]::Escape($Title)) 180 650 80 600)
            if ($recentMatches.Count -eq 1) {
                Invoke-VerifiedClick $snapshot $recentMatches[0].Bounds
                for ($attempt = 0; $attempt -lt 7; $attempt++) {
                    Start-Sleep -Milliseconds 600
                    $snapshot = Get-WindowSnapshot $Process
                    $state = Get-ChatPanelState $snapshot $Title
                    if ($state.Composer.Count -gt 0 -or $state.AddToTask.Count -gt 0 -or $state.History.Count -gt 0) {
                        break
                    }
                }
            } elseif ($recentMatches.Count -gt 1) {
                throw "Recent Chat list contains more than one exact '$Title' entry."
            }
        }
    }
    if ($state.Composer.Count -eq 0 -and $state.AddToTask.Count -eq 0 -and $state.History.Count -eq 0) {
        throw "Chat panel did not expose a verified header control, history header, or composer. Last screenshot: $($snapshot.Path)"
    }

    if ($state.History.Count -eq 0 -and $state.Title.Count -eq 1 -and $state.AddToTask.Count -eq 1) {
        return $snapshot
    }

    if ($state.History.Count -eq 0) {
        if ($state.AddToTask.Count -ne 1) {
            throw "Cannot open Chat history safely: expected one 'Add to task' header anchor; found $($state.AddToTask.Count)."
        }
        $headerBounds = $state.AddToTask[0].Bounds
        Invoke-VerifiedPoint $snapshot ($headerBounds.X - 300) ($headerBounds.Y + ($headerBounds.Height / 2))
        for ($attempt = 0; $attempt -lt 5; $attempt++) {
            Start-Sleep -Milliseconds 500
            $snapshot = Get-WindowSnapshot $Process
            $state = Get-ChatPanelState $snapshot $Title
            if ($state.History.Count -eq 1) { break }
        }
    }
    if ($state.History.Count -ne 1) {
        throw "Chat history did not open uniquely; found $($state.History.Count) History headers."
    }
    if ($state.Title.Count -ne 1) {
        throw "Expected exact existing Chat history entry '$Title'; found $($state.Title.Count)."
    }

    Invoke-VerifiedClick $snapshot $state.Title[0].Bounds
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        Start-Sleep -Milliseconds 600
        $snapshot = Get-WindowSnapshot $Process
        $state = Get-ChatPanelState $snapshot $Title
        if ($state.History.Count -eq 0 -and $state.Title.Count -eq 1 -and $state.AddToTask.Count -eq 1) {
            return $snapshot
        }
        if ($state.History.Count -eq 1) {
            Invoke-VerifiedClick $snapshot $state.History[0].Bounds
        }
    }
    throw "Exact ChatGPT conversation '$Title' did not become active after selection."
}

function Copy-ResponseAtMarker {
    param($Snapshot, $TitleMatch, [string]$Marker)

    if ([string]::IsNullOrWhiteSpace($Marker)) {
        throw 'ExpectedMarker is required for copy-latest.'
    }
    $minimumPanelX = [int]($Snapshot.Width * 0.68)
    $markerMatches = @(Get-OcrLinePatternMatches $Snapshot ([regex]::Escape($Marker)) $minimumPanelX $Snapshot.Width)
    if ($markerMatches.Count -ne 1) {
        throw "Expected one visible response marker '$Marker'; found $($markerMatches.Count)."
    }

    $markerBounds = $markerMatches[0].Bounds
    $copyX = [double]$TitleMatch.Bounds.X - 35
    $copyY = [double]$markerBounds.Y + $markerBounds.Height + 22
    $sentinel = "CHATGPT_COPY_SENTINEL_$([guid]::NewGuid().ToString('N'))"
    $originalClipboard = $null
    $hadClipboardText = $false
    try {
        $originalClipboard = Get-Clipboard -Raw -ErrorAction Stop
        $hadClipboardText = $true
    } catch {
        $originalClipboard = ''
    }

    try {
        Set-Clipboard -Value $sentinel
        Invoke-VerifiedPoint $Snapshot $copyX $copyY
        Start-Sleep -Milliseconds 700
        $copied = Get-Clipboard -Raw
        if ([string]::IsNullOrWhiteSpace($copied) -or $copied -eq $sentinel) {
            throw 'The ChatGPT response copy control did not place text on the clipboard.'
        }
        return $copied
    } finally {
        if ($hadClipboardText) {
            Set-Clipboard -Value $originalClipboard
        } else {
            Set-Clipboard -Value ''
        }
    }
}

function Set-ComposerPrompt {
    param($Snapshot, $ComposerMatch, [string]$Text, [string]$RequestToken)

    $originalClipboard = $null
    $hadClipboardText = $false
    try {
        $originalClipboard = Get-Clipboard -Raw -ErrorAction Stop
        $hadClipboardText = $true
    } catch {
        $originalClipboard = ''
    }

    $pastedView = $null
    try {
        Invoke-VerifiedClick $Snapshot $ComposerMatch.Bounds
        Start-Sleep -Milliseconds 200
        Set-Clipboard -Value $Text
        Invoke-Hotkey ([byte[]](0x11, 0x56))
        for ($attempt = 0; $attempt -lt 6; $attempt++) {
            Start-Sleep -Milliseconds 650
            $candidate = Get-WindowSnapshot (Get-ChatGptWindow)
            $minimumPanelX = [int]($candidate.Width * 0.68)
            $minimumComposerY = [int]($candidate.Height * 0.60)
            $tokenMatches = @(Get-OcrLinePatternMatches $candidate ([regex]::Escape($RequestToken)) $minimumPanelX $candidate.Width $minimumComposerY $candidate.Height)
            if ($tokenMatches.Count -gt 0) {
                $pastedView = $candidate
                break
            }
        }
    } finally {
        if ($hadClipboardText) {
            Set-Clipboard -Value $originalClipboard
        } else {
            Set-Clipboard -Value ''
        }
    }

    if ($null -eq $pastedView) {
        throw "Prompt was not sent: request token '$RequestToken' was not visible in the verified empty ChatGPT composer after six frames."
    }
    return $pastedView
}

function Return-ToOriginThread {
    param([string]$ThreadId)

    if ([string]::IsNullOrWhiteSpace($ThreadId)) {
        return
    }
    if ($ThreadId -notmatch '^[0-9a-fA-F-]{20,}$') {
        throw "Refusing invalid Codex origin thread ID '$ThreadId'."
    }
    Start-Process ("codex://threads/{0}" -f $ThreadId) -WindowStyle Hidden
}

$endpoint = $null
if ($Action -eq 'send-receive') {
    try {
        if (-not (Test-Path -LiteralPath $EndpointConfigPath -PathType Leaf)) {
            throw "Endpoint config does not exist: $EndpointConfigPath"
        }
        $endpoint = Get-Content -Raw -LiteralPath $EndpointConfigPath | ConvertFrom-Json
        if ($endpoint.alias -ne 'chatgpt-design-studio' -or
            $endpoint.mode -ne 'Work' -or
            $endpoint.target_title -ne $TargetTitle -or
            $endpoint.existing_only -ne $true -or
            $endpoint.create_if_missing -ne $false) {
            throw 'Endpoint config does not match the fixed existing Design Studio contract.'
        }
        if ($endpoint.live_send_enabled -ne $true -and -not $SmokeTestOverride) {
            throw 'Live Design Studio sending is gated pending a successful bounded smoke test.'
        }
    } catch {
        [pscustomobject]@{
            ok = $false
            action = $Action
            target = $TargetTitle
            error = $_.Exception.Message
        } | ConvertTo-Json -Depth 4
        exit 1
    }
}

$process = Get-ChatGptWindow
[ChatGptDesktopNative]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 350
$initial = Get-WindowSnapshot $process

if ($Action -eq 'inspect') {
    [pscustomobject]@{
        ok = $true
        action = $Action
        screenshot = $initial.Path
        lines = @($initial.Ocr.Lines | ForEach-Object Text)
    } | ConvertTo-Json -Depth 5
    exit 0
}

$initial = Dismiss-CommandOverlay $process $initial
$chatView = Get-WorkView $process $initial

if ($Action -eq 'open-chatgpt') {
    [pscustomobject]@{
        ok = $true
        action = $Action
        screenshot = $chatView.Path
        lines = @($chatView.Ocr.Lines | ForEach-Object Text)
    } | ConvertTo-Json -Depth 5
    exit 0
}

$chatList = Open-ExactChatPanel $process $chatView $TargetTitle
$state = Get-ChatPanelState $chatList $TargetTitle
$verified = $state.Title[0]

if ($Action -eq 'open-chat-list') {
    [pscustomobject]@{
        ok = $true
        action = $Action
        target = $TargetTitle
        screenshot = $chatList.Path
        verified_title = $verified.Line.Text
        lines = @($chatList.Ocr.Lines | ForEach-Object Text)
    } | ConvertTo-Json -Depth 5
    exit 0
}

if ($Action -eq 'copy-latest') {
    $copied = Copy-ResponseAtMarker $chatList $verified $ExpectedMarker
    [pscustomobject]@{
        ok = $true
        action = $Action
        target = $TargetTitle
        screenshot = $chatList.Path
        response = $copied
    } | ConvertTo-Json -Depth 5
    exit 0
}

if ($Action -eq 'send-receive') {
    $result = $null
    $requestId = ([guid]::NewGuid().ToString('N').Substring(0, 12)).ToUpperInvariant()
    $requestToken = "DSREQ-$requestId"
    $completionMarker = "DSDONE-$requestId"
    try {
        if (-not [string]::IsNullOrWhiteSpace($Prompt) -and -not [string]::IsNullOrWhiteSpace($PromptPath)) {
            throw 'Use Prompt or PromptPath, not both.'
        }
        $taskText = if (-not [string]::IsNullOrWhiteSpace($PromptPath)) {
            if (-not (Test-Path -LiteralPath $PromptPath -PathType Leaf)) {
                throw "PromptPath does not exist: $PromptPath"
            }
            Get-Content -Raw -LiteralPath $PromptPath
        } else {
            $Prompt
        }
        if ([string]::IsNullOrWhiteSpace($taskText)) {
            throw 'A non-empty Prompt or PromptPath is required for send-receive.'
        }
        if ($taskText.Length -gt 30000) {
            throw "Prompt is too large for the bounded desktop bridge: $($taskText.Length) characters."
        }

        $wrappedPrompt = @"
$requestToken

Use this existing conversation as ChatGPT Design Studio. Do not create, fork, rename, or switch conversations.
Complete only the bounded task below. Do not request local filesystem access unless the task explicitly requires it.

TASK
$taskText

Return a concise final response ending with this exact receipt:
CHATGPT_RETURN_PACKET
request_id: $requestId
status: complete|blocked
summary: <what you produced>
artifacts: <links or none>
next_action: <what Codex should do next>
END_CHATGPT_RETURN_PACKET
$completionMarker

$requestToken
"@

        $composerView = $chatList
        $composerState = $state
        if ($composerState.Busy.Count -gt 0) {
            throw "Design Studio is busy with an existing request. The bridge will not interrupt or stack another prompt."
        }
        for ($attempt = 0; $composerState.Composer.Count -ne 1 -and $attempt -lt 8; $attempt++) {
            Start-Sleep -Milliseconds 450
            $composerView = Get-WindowSnapshot $process
            $composerState = Get-ChatPanelState $composerView $TargetTitle
            if ($composerState.History.Count -gt 0 -or $composerState.Title.Count -ne 1) {
                throw "The verified '$TargetTitle' panel changed while checking its composer."
            }
            if ($composerState.Busy.Count -gt 0) {
                throw "Design Studio became busy with an existing request. The bridge will not interrupt or stack another prompt."
            }
        }
        if ($composerState.Composer.Count -ne 1) {
            throw "Design Studio composer is not provably empty. Clear any unsent draft manually; the bridge will not overwrite it."
        }

        $pastedView = Set-ComposerPrompt $composerView $composerState.Composer[0] $wrappedPrompt $requestToken
        Invoke-Key 0x0D

        $sentVerified = $false
        for ($attempt = 0; $attempt -lt 4; $attempt++) {
            Start-Sleep -Milliseconds 700
            $sentView = Get-WindowSnapshot $process
            $minimumPanelX = [int]($sentView.Width * 0.68)
            $sentMatches = @(Get-OcrLinePatternMatches $sentView ([regex]::Escape($requestToken)) $minimumPanelX $sentView.Width)
            if ($sentMatches.Count -gt 0) {
                $sentVerified = $true
                break
            }
        }
        if (-not $sentVerified) {
            throw "Enter was pressed once, but the sent request token '$requestToken' was not visually verified. The bridge will not retry or duplicate the request."
        }

        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $response = $null
        $receiptScreenshot = ''
        while ([DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 1800
            $candidate = Get-WindowSnapshot $process
            $candidateState = Get-ChatPanelState $candidate $TargetTitle
            if ($candidateState.History.Count -gt 0 -or $candidateState.Title.Count -ne 1) {
                throw "ChatGPT left the verified '$TargetTitle' conversation while awaiting the response."
            }
            $minimumPanelX = [int]($candidate.Width * 0.68)
            $doneMatches = @(Get-OcrLinePatternMatches $candidate ([regex]::Escape($completionMarker)) $minimumPanelX $candidate.Width)
            if ($doneMatches.Count -eq 1) {
                $response = Copy-ResponseAtMarker $candidate $candidateState.Title[0] $completionMarker
                $receiptScreenshot = $candidate.Path
                break
            }
            if ($doneMatches.Count -gt 1) {
                throw "Completion marker '$completionMarker' appeared more than once."
            }
        }
        if ([string]::IsNullOrWhiteSpace($response)) {
            throw "Timed out after $TimeoutSeconds seconds waiting for '$completionMarker'. The request was sent once and will not be duplicated."
        }
        if ($response -notmatch [regex]::Escape($completionMarker) -or
            $response -notmatch '(?i)CHATGPT_RETURN_PACKET' -or
            $response -notmatch ("(?i)request_id:\s*{0}" -f [regex]::Escape($requestId))) {
            throw 'The copied response did not contain the matching typed receipt.'
        }

        $result = [pscustomobject]@{
            ok = $true
            action = $Action
            target = $TargetTitle
            request_id = $requestId
            request_token = $requestToken
            completion_marker = $completionMarker
            screenshot = $receiptScreenshot
            response = $response
        }
    } catch {
        $result = [pscustomobject]@{
            ok = $false
            action = $Action
            target = $TargetTitle
            request_id = $requestId
            request_token = $requestToken
            completion_marker = $completionMarker
            error = $_.Exception.Message
        }
    } finally {
        try {
            Return-ToOriginThread $OriginThreadId
        } catch {
            if ($null -eq $result) {
                $result = [pscustomobject]@{ ok = $false; action = $Action; error = $_.Exception.Message }
            } else {
                $result | Add-Member -NotePropertyName return_error -NotePropertyValue $_.Exception.Message -Force
            }
        }
    }

    $result | ConvertTo-Json -Depth 6
    if (-not $result.ok) { exit 1 }
    exit 0
}

[pscustomobject]@{
    ok = $true
    action = $Action
    target = $TargetTitle
    screenshot = $chatList.Path
    verified_title = $verified.Line.Text
} | ConvertTo-Json -Depth 5
