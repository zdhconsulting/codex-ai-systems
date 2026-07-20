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

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class ChatGptUnifiedDesktopNative {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int command);
}
'@

function Get-ChatGptProcess {
    $windows = @(Get-Process ChatGPT -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -ne 0)
    if ($windows.Count -ne 1) {
        throw "Expected one visible unified ChatGPT desktop window; found $($windows.Count)."
    }
    return $windows[0]
}

function Get-AppRoot {
    param([System.Diagnostics.Process]$Process)

    $root = [System.Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
    if ($null -eq $root) {
        throw 'The unified ChatGPT desktop window did not expose a UI Automation root.'
    }
    return $root
}

function Get-Descendants {
    param([System.Windows.Automation.AutomationElement]$Element)

    return @($Element.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition
    ))
}

function Invoke-UiaElement {
    param([System.Windows.Automation.AutomationElement]$Element, [string]$Description)

    $pattern = $null
    if (-not $Element.TryGetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern,
        [ref]$pattern
    )) {
        throw "$Description does not expose InvokePattern."
    }
    $pattern.Invoke()
}

function Test-SameUiaElement {
    param(
        [System.Windows.Automation.AutomationElement]$Left,
        [System.Windows.Automation.AutomationElement]$Right
    )

    if ($null -eq $Left -or $null -eq $Right) { return $false }
    return [System.Windows.Automation.Automation]::Compare($Left, $Right)
}

function Get-AncestorWindow {
    param([System.Windows.Automation.AutomationElement]$Element)

    $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
    $current = $Element
    for ($depth = 0; $depth -lt 20 -and $null -ne $current; $depth++) {
        if ($current.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window) {
            return $current
        }
        $current = $walker.GetParent($current)
    }
    throw 'The active ChatGPT conversation did not expose a containing desktop window.'
}

function Get-ElementText {
    param([System.Windows.Automation.AutomationElement]$Element)

    $pattern = $null
    if ($Element.TryGetCurrentPattern(
        [System.Windows.Automation.TextPattern]::Pattern,
        [ref]$pattern
    )) {
        return [string]$pattern.DocumentRange.GetText(-1)
    }
    return [string]$Element.Current.Name
}

function Test-ComposerEmpty {
    param([string]$Text)

    $normalized = (($Text -replace '[\r\n\u200B]', ' ') -replace '\s+', ' ').Trim()
    return [string]::IsNullOrWhiteSpace($normalized) -or $normalized -eq 'Message ChatGPT'
}

function Get-ActiveConversationState {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Title,
        [switch]$RequireSendButton
    )

    $root = Get-AppRoot $Process
    $all = Get-Descendants $root
    $expectedTitle = "View chat history, current chat: $Title"
    $titleElements = @($all | Where-Object {
        $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and
        $_.Current.Name -eq $expectedTitle
    })
    if ($titleElements.Count -ne 1) {
        throw "Expected one active ChatGPT title '$Title'; found $($titleElements.Count)."
    }

    $conversationWindow = Get-AncestorWindow $titleElements[0]
    $windowBounds = $conversationWindow.Current.BoundingRectangle
    $descendants = Get-Descendants $conversationWindow
    $composerFloor = $windowBounds.Bottom - 180
    $composers = @($descendants | Where-Object {
        $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Group -and
        $_.Current.ClassName -match '(^|\s)ProseMirror(\s|$)' -and
        $_.Current.IsKeyboardFocusable -and
        $_.Current.BoundingRectangle.Width -gt 100 -and
        $_.Current.BoundingRectangle.Height -gt 0 -and
        $_.Current.BoundingRectangle.Bottom -ge $composerFloor
    })
    if ($composers.Count -ne 1) {
        throw "Expected one visible '$Title' composer; found $($composers.Count)."
    }

    $sendButtons = @($descendants | Where-Object {
        $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and
        $_.Current.Name -eq 'Send' -and
        $_.Current.BoundingRectangle.Width -gt 0 -and
        $_.Current.BoundingRectangle.Y -ge $composerFloor
    })
    if ($sendButtons.Count -gt 1 -or ($RequireSendButton -and $sendButtons.Count -ne 1)) {
        throw "Expected one '$Title' Send button; found $($sendButtons.Count)."
    }

    $busyButtons = @($descendants | Where-Object {
        $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and
        $_.Current.Name -match '^Stop\b' -and
        $_.Current.IsEnabled
    })
    $copyButtons = @($descendants | Where-Object {
        $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and
        $_.Current.Name -eq 'Copy'
    })

    return [pscustomobject]@{
        Root = $root
        Window = $conversationWindow
        TitleElement = $titleElements[0]
        Composer = $composers[0]
        ComposerText = Get-ElementText $composers[0]
        SendButton = if ($sendButtons.Count -eq 1) { $sendButtons[0] } else { $null }
        BusyButtons = $busyButtons
        CopyButtons = $copyButtons
        Descendants = $descendants
    }
}

function Open-CommandMenu {
    param([System.Diagnostics.Process]$Process)

    $root = Get-AppRoot $Process
    $all = Get-Descendants $root
    $combos = @($all | Where-Object {
        $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::ComboBox -and
        $_.Current.Name -eq 'Command menu'
    })
    if ($combos.Count -eq 1) { return $combos[0] }
    if ($combos.Count -gt 1) { throw "Found $($combos.Count) Command menu inputs." }

    $searchButtons = @($all | Where-Object {
        $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and
        $_.Current.Name -eq 'Search' -and
        $_.Current.IsEnabled
    })
    if ($searchButtons.Count -ne 1) {
        throw "Expected one named Search button; found $($searchButtons.Count)."
    }
    Invoke-UiaElement $searchButtons[0] 'The unified desktop Search button'

    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        Start-Sleep -Milliseconds 150
        $root = Get-AppRoot $Process
        $combos = @(Get-Descendants $root | Where-Object {
            $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::ComboBox -and
            $_.Current.Name -eq 'Command menu'
        })
        if ($combos.Count -eq 1) { return $combos[0] }
        if ($combos.Count -gt 1) { throw "Found $($combos.Count) Command menu inputs." }
    }
    throw 'The named Search button did not open the Command menu.'
}

function Search-ExactConversation {
    param([System.Diagnostics.Process]$Process, [string]$Title)

    $combo = Open-CommandMenu $Process
    $valuePattern = $null
    if (-not $combo.TryGetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern,
        [ref]$valuePattern
    )) {
        throw 'The Command menu input does not expose ValuePattern.'
    }
    $valuePattern.SetValue($Title)

    $resultPattern = ('^{0}\s+ChatGPT(?:\s+Ctrl\+\d+)?$' -f [regex]::Escape($Title))
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 150
        $root = Get-AppRoot $Process
        $matches = @(Get-Descendants $root | Where-Object {
            $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::ListItem -and
            $_.Current.Name -match $resultPattern -and
            $_.Current.IsEnabled
        })
        if ($matches.Count -eq 1) {
            return [pscustomobject]@{
                Combo = $combo
                Item = $matches[0]
                ItemName = $matches[0].Current.Name
            }
        }
        if ($matches.Count -gt 1) {
            throw "Search returned $($matches.Count) exact existing ChatGPT conversations named '$Title'."
        }
    }
    throw "Search did not find the exact existing ChatGPT conversation '$Title'."
}

function Open-ExactConversation {
    param([System.Diagnostics.Process]$Process, [string]$Title)

    $root = Get-AppRoot $Process
    $openCommandMenus = @(Get-Descendants $root | Where-Object {
        $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::ComboBox -and
        $_.Current.Name -eq 'Command menu'
    })
    if ($openCommandMenus.Count -eq 0) {
        try {
            return Get-ActiveConversationState $Process $Title -RequireSendButton
        } catch {
            # Search is the only supported navigation path in the unified desktop app.
        }
    } elseif ($openCommandMenus.Count -gt 1) {
        throw "Found $($openCommandMenus.Count) Command menu inputs."
    }

    $search = Search-ExactConversation $Process $Title
    Invoke-UiaElement $search.Item "The exact '$Title' ChatGPT result"

    $lastError = $null
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        Start-Sleep -Milliseconds 200
        try {
            return Get-ActiveConversationState $Process $Title -RequireSendButton
        } catch {
            $lastError = $_.Exception.Message
        }
    }
    throw "The exact ChatGPT conversation '$Title' did not become active. Last check: $lastError"
}

function Set-AppForeground {
    param([System.Diagnostics.Process]$Process)

    [ChatGptUnifiedDesktopNative]::ShowWindowAsync($Process.MainWindowHandle, 9) | Out-Null
    [ChatGptUnifiedDesktopNative]::SetForegroundWindow($Process.MainWindowHandle) | Out-Null
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        if ([ChatGptUnifiedDesktopNative]::GetForegroundWindow() -eq $Process.MainWindowHandle) {
            return
        }
        Start-Sleep -Milliseconds 100
    }
    throw 'The unified ChatGPT desktop app could not be verified as the foreground window.'
}

function Get-ClipboardSnapshot {
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try { return [System.Windows.Forms.Clipboard]::GetDataObject() } catch { Start-Sleep -Milliseconds 100 }
    }
    throw 'Could not preserve the current clipboard before desktop bridge use.'
}

function Set-ClipboardTextSafe {
    param([string]$Text)

    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try {
            [System.Windows.Forms.Clipboard]::SetText($Text)
            return
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
    throw 'Could not place bridge text on the clipboard.'
}

function Get-ClipboardTextSafe {
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try {
            if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                return [System.Windows.Forms.Clipboard]::GetText()
            }
        } catch {}
        Start-Sleep -Milliseconds 100
    }
    return ''
}

function Restore-ClipboardSnapshot {
    param($Snapshot)

    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try {
            if ($null -eq $Snapshot) {
                [System.Windows.Forms.Clipboard]::Clear()
            } else {
                [System.Windows.Forms.Clipboard]::SetDataObject($Snapshot, $true)
            }
            return
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
    throw 'The bridge finished, but the original clipboard could not be restored.'
}

function Set-ComposerPrompt {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Title,
        [string]$Text,
        [string]$RequestToken
    )

    $state = Get-ActiveConversationState $Process $Title -RequireSendButton
    if ($state.BusyButtons.Count -gt 0) {
        throw "$Title is busy. The bridge will not interrupt or stack another request."
    }
    if (-not (Test-ComposerEmpty $state.ComposerText)) {
        throw "$Title has an unsent draft. The bridge will not overwrite or clear it."
    }

    Set-AppForeground $Process
    $state = Get-ActiveConversationState $Process $Title -RequireSendButton
    if ($state.BusyButtons.Count -gt 0) {
        throw "$Title became busy before focus. The bridge will not stack another request."
    }
    if (-not (Test-ComposerEmpty $state.ComposerText)) {
        throw "$Title gained an unsent draft before focus. The bridge will not overwrite or clear it."
    }
    $state.Composer.SetFocus()
    Start-Sleep -Milliseconds 150
    $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
    if (-not (Test-SameUiaElement $focused $state.Composer)) {
        throw "The exact '$Title' composer did not receive keyboard focus. Nothing was pasted."
    }
    if ([ChatGptUnifiedDesktopNative]::GetForegroundWindow() -ne $Process.MainWindowHandle) {
        throw 'Desktop focus changed before the prompt could be pasted. Nothing was pasted.'
    }

    $clipboard = Get-ClipboardSnapshot
    try {
        Set-ClipboardTextSafe $Text
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 450
    } finally {
        Restore-ClipboardSnapshot $clipboard
    }

    $verified = Get-ActiveConversationState $Process $Title -RequireSendButton
    if ($verified.ComposerText -notmatch [regex]::Escape($RequestToken)) {
        throw "The prompt token '$RequestToken' was not verified inside the exact '$Title' composer. Nothing was sent."
    }
    return $verified
}

function Invoke-SendOnce {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Title,
        [string]$RequestToken
    )

    $state = Get-ActiveConversationState $Process $Title -RequireSendButton
    if ($state.BusyButtons.Count -gt 0) {
        throw "$Title became busy before send. The bridge will not stack another request."
    }
    if ($state.ComposerText -notmatch [regex]::Escape($RequestToken)) {
        throw "The exact '$Title' composer no longer contains '$RequestToken'. Nothing was sent."
    }
    if (-not $state.SendButton.Current.IsEnabled) {
        throw "The exact '$Title' Send button is disabled. Nothing was sent."
    }

    Set-AppForeground $Process
    Invoke-UiaElement $state.SendButton "The exact '$Title' Send button"

    $lastError = $null
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 200
        try {
            $sentState = Get-ActiveConversationState $Process $Title
            if (Test-ComposerEmpty $sentState.ComposerText) {
                return $sentState
            }
        } catch {
            $lastError = $_.Exception.Message
        }
    }
    throw "Send was invoked exactly once, but the cleared composer was not verified. The bridge will not retry. Last check: $lastError"
}

function Copy-AssistantResponse {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Title,
        [int]$MinimumCopyCount = 0
    )

    $state = Get-ActiveConversationState $Process $Title
    if ($state.CopyButtons.Count -le $MinimumCopyCount) {
        throw "No new assistant response is available in '$Title'."
    }
    $copyButton = $state.CopyButtons[$state.CopyButtons.Count - 1]
    $scrollPattern = $null
    if ($copyButton.TryGetCurrentPattern(
        [System.Windows.Automation.ScrollItemPattern]::Pattern,
        [ref]$scrollPattern
    )) {
        $scrollPattern.ScrollIntoView()
        Start-Sleep -Milliseconds 150
    }

    $clipboard = Get-ClipboardSnapshot
    $sentinel = "CHATGPT_COPY_SENTINEL_$([guid]::NewGuid().ToString('N'))"
    try {
        Set-ClipboardTextSafe $sentinel
        Invoke-UiaElement $copyButton 'The newest ChatGPT assistant Copy button'
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            Start-Sleep -Milliseconds 100
            $copied = Get-ClipboardTextSafe
            if (-not [string]::IsNullOrWhiteSpace($copied) -and $copied -ne $sentinel) {
                return $copied
            }
        }
        throw 'The newest assistant Copy button did not return text.'
    } finally {
        Restore-ClipboardSnapshot $clipboard
    }
}

function Wait-ForAssistantResponse {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Title,
        [int]$BaselineCopyCount,
        [DateTime]$Deadline
    )

    while ([DateTime]::UtcNow -lt $Deadline) {
        Start-Sleep -Milliseconds 750
        $state = Get-ActiveConversationState $Process $Title
        if ($state.BusyButtons.Count -eq 0 -and $state.CopyButtons.Count -gt $BaselineCopyCount) {
            Start-Sleep -Milliseconds 300
            return Copy-AssistantResponse $Process $Title $BaselineCopyCount
        }
    }
    throw "Timed out waiting for one new assistant response in '$Title'. The request was sent once and will not be duplicated."
}

function Return-ToOriginThread {
    param([string]$ThreadId)

    if ([string]::IsNullOrWhiteSpace($ThreadId)) { return }
    if ($ThreadId -notmatch '^[0-9a-fA-F-]{20,}$') {
        throw "Refusing invalid Codex origin task ID '$ThreadId'."
    }
    Start-Process ("codex://threads/{0}" -f $ThreadId) -WindowStyle Hidden
}

function Write-BridgeResult {
    param($Result)

    $json = $Result | ConvertTo-Json -Depth 7
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
    }
    $json
}

$endpoint = $null
$process = $null
$bridgeMutex = $null
$mutexAcquired = $false

try {
    if ($Action -eq 'send-receive') {
        if (-not (Test-Path -LiteralPath $EndpointConfigPath -PathType Leaf)) {
            throw "Endpoint config does not exist: $EndpointConfigPath"
        }
        $endpoint = Get-Content -Raw -LiteralPath $EndpointConfigPath | ConvertFrom-Json
        if ($endpoint.alias -ne 'chatgpt-design-studio' -or
            $endpoint.mode -ne 'Work' -or
            $endpoint.target_title -ne $TargetTitle -or
            $endpoint.transport -ne 'unified_desktop_uia' -or
            $endpoint.existing_only -ne $true -or
            $endpoint.create_if_missing -ne $false -or
            $endpoint.maximum_rounds -ne 1) {
            throw 'Endpoint config does not match the fixed existing Design Studio contract.'
        }
        if ($endpoint.live_send_enabled -ne $true -and -not $SmokeTestOverride) {
            throw 'Live Design Studio sending is gated pending a successful bounded smoke test.'
        }
        $bridgeMutex = New-Object System.Threading.Mutex($false, 'Local\ZevChatGptDesignStudioBridge')
        try {
            $mutexAcquired = $bridgeMutex.WaitOne(0)
        } catch [System.Threading.AbandonedMutexException] {
            $mutexAcquired = $true
        }
        if (-not $mutexAcquired) {
            throw 'Another Design Studio bridge request is already active. The bridge will not stack work.'
        }
    }

    $process = Get-ChatGptProcess

    if ($Action -eq 'inspect' -or $Action -eq 'open-chatgpt') {
        $root = Get-AppRoot $process
        $all = Get-Descendants $root
        $modeButtons = @($all | Where-Object {
            $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and
            $_.Current.Name -match '^Switch mode, current mode:'
        })
        $searchButtons = @($all | Where-Object {
            $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and
            $_.Current.Name -eq 'Search'
        })
        Write-BridgeResult ([pscustomobject]@{
            ok = $true
            action = $Action
            transport = 'unified_desktop_uia'
            process_id = $process.Id
            window_title = $process.MainWindowTitle
            mode = @($modeButtons | ForEach-Object Current | ForEach-Object Name)
            named_search_controls = $searchButtons.Count
        })
        exit 0
    }

    if ($Action -eq 'open-chat-list') {
        $search = Search-ExactConversation $process $TargetTitle
        Write-BridgeResult ([pscustomobject]@{
            ok = $true
            action = $Action
            target = $TargetTitle
            transport = 'unified_desktop_uia'
            unique_existing_result = $search.ItemName
        })
        exit 0
    }

    $state = Open-ExactConversation $process $TargetTitle

    if ($Action -eq 'open-chat') {
        Write-BridgeResult ([pscustomobject]@{
            ok = $true
            action = $Action
            target = $TargetTitle
            transport = 'unified_desktop_uia'
            verified_title = $state.TitleElement.Current.Name
            composer_empty = Test-ComposerEmpty $state.ComposerText
            busy = ($state.BusyButtons.Count -gt 0)
            assistant_message_count = $state.CopyButtons.Count
        })
        exit 0
    }

    if ($Action -eq 'copy-latest') {
        if ([string]::IsNullOrWhiteSpace($ExpectedMarker)) {
            throw 'ExpectedMarker is required for copy-latest.'
        }
        $response = Copy-AssistantResponse $process $TargetTitle -1
        if ($response -notmatch [regex]::Escape($ExpectedMarker)) {
            throw "The newest assistant response did not contain '$ExpectedMarker'."
        }
        Write-BridgeResult ([pscustomobject]@{
            ok = $true
            action = $Action
            target = $TargetTitle
            transport = 'unified_desktop_uia'
            response = $response
        })
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

            $state = Get-ActiveConversationState $process $TargetTitle -RequireSendButton
            if ($state.BusyButtons.Count -gt 0) {
                throw "$TargetTitle is busy. The bridge will not interrupt or stack another request."
            }
            if (-not (Test-ComposerEmpty $state.ComposerText)) {
                throw "$TargetTitle has an unsent draft. The bridge will not overwrite or clear it."
            }
            $baselineCopyCount = $state.CopyButtons.Count
            Set-ComposerPrompt $process $TargetTitle $wrappedPrompt $requestToken | Out-Null
            Invoke-SendOnce $process $TargetTitle $requestToken | Out-Null
            $response = Wait-ForAssistantResponse `
                $process `
                $TargetTitle `
                $baselineCopyCount `
                ([DateTime]::UtcNow.AddSeconds($TimeoutSeconds))

            if ($response -notmatch [regex]::Escape($completionMarker) -or
                $response -notmatch '(?i)CHATGPT_RETURN_PACKET' -or
                $response -notmatch '(?i)END_CHATGPT_RETURN_PACKET' -or
                $response -notmatch ("(?i)request_id:\s*{0}" -f [regex]::Escape($requestId))) {
                throw 'The copied assistant response did not contain the matching typed receipt.'
            }

            $result = [pscustomobject]@{
                ok = $true
                action = $Action
                target = $TargetTitle
                transport = 'unified_desktop_uia'
                request_id = $requestId
                request_token = $requestToken
                completion_marker = $completionMarker
                response = $response
            }
        } catch {
            $result = [pscustomobject]@{
                ok = $false
                action = $Action
                target = $TargetTitle
                transport = 'unified_desktop_uia'
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

        Write-BridgeResult $result
        if (-not $result.ok) { exit 1 }
        exit 0
    }

    throw "Unsupported action '$Action'."
} catch {
    Write-BridgeResult ([pscustomobject]@{
        ok = $false
        action = $Action
        target = $TargetTitle
        transport = 'unified_desktop_uia'
        error = $_.Exception.Message
    })
    exit 1
} finally {
    if ($mutexAcquired -and $null -ne $bridgeMutex) {
        try { $bridgeMutex.ReleaseMutex() } catch {}
    }
    if ($null -ne $bridgeMutex) { $bridgeMutex.Dispose() }
}
