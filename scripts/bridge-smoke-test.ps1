param(
    [string] $CodexHome = "",
    [string] $Project = "Bridge Smoke Test",
    [int] $Iterations = 2,
    [int] $ProviderReadyTimeoutSeconds = 30,
    [switch] $RequireBrowserRuntime,
    [switch] $Json
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$CodexHome = (Resolve-Path -LiteralPath $CodexHome).Path
$scriptDir = Join-Path $CodexHome "scripts"
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Warnings = New-Object System.Collections.Generic.List[string]
$script:Checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param(
        [string] $Name,
        [string] $Status,
        [string] $Detail = "",
        [object] $Data = $null
    )
    $row = [ordered]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
        Data = $Data
    }
    $script:Checks.Add([pscustomobject]$row)
    if ($Status -eq "fail") { $script:Failures.Add("$Name - $Detail") }
    if ($Status -eq "warn") { $script:Warnings.Add("$Name - $Detail") }
    if (-not $Json) {
        $label = $Status.ToUpperInvariant()
        if ($Detail) { Write-Host "$label $Name - $Detail" } else { Write-Host "$label $Name" }
    }
}

function Invoke-Captured {
    param(
        [scriptblock] $Script,
        [string] $Name
    )
    try {
        $output = & $Script 2>&1 | Out-String
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = $output
            Error = ""
        }
    } catch {
        return [pscustomobject]@{
            ExitCode = 999
            Output = ""
            Error = "$($_.Exception.Message)"
        }
    }
}

function Read-JsonFile {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Assert-FileContains {
    param(
        [string] $Path,
        [string] $Pattern,
        [string] $CheckName
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Check $CheckName "fail" "Missing file: $Path"
        return
    }
    $text = Get-Content -LiteralPath $Path -Raw
    if ($text -match $Pattern) {
        Add-Check $CheckName "pass" $Path
    } else {
        Add-Check $CheckName "fail" "Pattern '$Pattern' not found in $Path"
    }
}

if ($Iterations -lt 1) { $Iterations = 1 }
if ($ProviderReadyTimeoutSeconds -lt 5) { $ProviderReadyTimeoutSeconds = 5 }

$requiredScripts = @(
    "ai-provider-gateway.cmd",
    "chatgpt-auto-route.cmd",
    "chatgpt-chrome-bridge.mjs",
    "chatgpt-return.cmd",
    "deepseek-route.cmd",
    "codex-gateway-tally.cmd"
)

foreach ($scriptName in $requiredScripts) {
    $path = Join-Path $scriptDir $scriptName
    Add-Check "script exists: $scriptName" ($(if (Test-Path -LiteralPath $path) { "pass" } else { "fail" })) $path
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeProject = ($Project -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
if ([string]::IsNullOrWhiteSpace($safeProject)) { $safeProject = "Bridge-Smoke-Test" }
$bridgeOutDir = Join-Path $CodexHome "tmp\bridge-smoke\$stamp"
New-Item -ItemType Directory -Path $bridgeOutDir -Force | Out-Null

$chatDry = Invoke-Captured -Name "provider gateway ChatGPT dry-run" -Script {
    & (Join-Path $scriptDir "ai-provider-gateway.cmd") -DryRun -Project $Project "draft a concise client update email and return a CODEX_RETURN_PACKET"
}
Add-Check "provider gateway routes ChatGPT" ($(if ($chatDry.Output -match "Route:\s+chatgpt" -and $chatDry.Output -match "Provider:\s+chatgpt") { "pass" } else { "fail" })) (($chatDry.Output -replace "\s+", " ").Trim())

$deepDry = Invoke-Captured -Name "provider gateway DeepSeek dry-run" -Script {
    & (Join-Path $scriptDir "ai-provider-gateway.cmd") -DryRun -Project $Project "draft 6 low-cost SEO article first-pass outlines for Mr.SEO and return CODEX_RETURN_PACKET"
}
Add-Check "provider gateway routes DeepSeek" ($(if ($deepDry.Output -match "Route:\s+deepseek" -and $deepDry.Output -match "Provider:\s+deepseek") { "pass" } else { "fail" })) (($deepDry.Output -replace "\s+", " ").Trim())

$chatSessions = @()
$deepSessions = @()
for ($i = 1; $i -le $Iterations; $i++) {
    $token = "CGPT-$stamp-$i"
    $task = "[chatgpt] Draft a tiny client update smoke packet $i. Return only CODEX_RETURN_PACKET. Include token $token in Deliverable."
    $jsonText = Invoke-Captured -Name "ChatGPT prep $i" -Script {
        & (Join-Path $scriptDir "chatgpt-auto-route.cmd") -NoOpen -NoCopy -PacketOnly -Json -Project $Project -OutDir $bridgeOutDir -ProviderReadyTimeoutSeconds $ProviderReadyTimeoutSeconds $task
    }
    $obj = $null
    try { $obj = $jsonText.Output | ConvertFrom-Json } catch { $obj = $null }
    $ok = $obj -and $obj.Status -eq "prepared" -and $obj.Route.Route -eq "chatgpt" -and (Test-Path -LiteralPath $obj.SessionPath) -and (Test-Path -LiteralPath $obj.PromptPath)
    Add-Check "ChatGPT prep $i" ($(if ($ok) { "pass" } else { "fail" })) ($(if ($ok) { $obj.SessionPath } else { ($jsonText.Output + $jsonText.Error).Trim() }))
    if ($ok) {
        $chatSessions += $obj
        Assert-FileContains -Path $obj.PromptPath -Pattern "CODEX_RETURN_PACKET" -CheckName "ChatGPT prompt $i requires packet"
        Assert-FileContains -Path $obj.PromptPath -Pattern ([regex]::Escape($token)) -CheckName "ChatGPT prompt $i keeps token"
        $sessionObj = Read-JsonFile -Path $obj.SessionPath
        $hasRunner = $sessionObj -and $sessionObj.RunnerSnippet -match "runChatGptChromeBridge"
        Add-Check "ChatGPT session $i has runner snippet" ($(if ($hasRunner) { "pass" } else { "fail" })) $obj.SessionPath
    }

    $deepToken = "DSEEK-$stamp-$i"
    $deepTask = "[deepseek] Make a short low-cost SEO outline smoke packet $i. Return CODEX_RETURN_PACKET only. Include token $deepToken."
    $deepOut = Invoke-Captured -Name "DeepSeek prep $i" -Script {
        & (Join-Path $scriptDir "deepseek-route.cmd") -NoOpen -NoCopy -PacketOnly -Project $Project -ProviderReadyTimeoutSeconds $ProviderReadyTimeoutSeconds $deepTask
    }
    $sessionPath = ($deepOut.Output -split "\r?\n" | Where-Object { $_ -match "^Session:" } | Select-Object -First 1) -replace "^Session:\s*", ""
    $promptPath = ($deepOut.Output -split "\r?\n" | Where-Object { $_ -match "^Prompt:" } | Select-Object -First 1) -replace "^Prompt:\s*", ""
    $deepOk = $sessionPath -and $promptPath -and (Test-Path -LiteralPath $sessionPath) -and (Test-Path -LiteralPath $promptPath)
    Add-Check "DeepSeek prep $i" ($(if ($deepOk) { "pass" } else { "fail" })) ($(if ($deepOk) { $sessionPath } else { ($deepOut.Output + $deepOut.Error).Trim() }))
    if ($deepOk) {
        $deepSessions += [pscustomobject]@{ SessionPath = $sessionPath; PromptPath = $promptPath }
        Assert-FileContains -Path $promptPath -Pattern "CODEX_RETURN_PACKET" -CheckName "DeepSeek prompt $i requires packet"
        Assert-FileContains -Path $promptPath -Pattern ([regex]::Escape($deepToken)) -CheckName "DeepSeek prompt $i keeps token"
        $sessionObj = Read-JsonFile -Path $sessionPath
        $hasNext = $sessionObj -and $sessionObj.NextManualAction -match "CODEX_RETURN_PACKET"
        Add-Check "DeepSeek session $i has return instruction" ($(if ($hasNext) { "pass" } else { "fail" })) $sessionPath
    }
}

for ($i = 1; $i -le $Iterations; $i++) {
    $packetPath = Join-Path $bridgeOutDir "return-packet-$i.txt"
    @"
CODEX_RETURN_PACKET
Summary: Bridge return smoke $i succeeded.
Decisions: No decision needed.
Deliverable: Return packet token IMPORT-$stamp-$i.
Codex next action: Record bridge return import as usable.
Files/assets needed: None.
Owner buttons needed: None.
Confidence: high
Go back to Codex?: yes
END_CODEX_RETURN_PACKET
"@ | Set-Content -LiteralPath $packetPath -Encoding UTF8
    $importJson = Invoke-Captured -Name "return import $i" -Script {
        & (Join-Path $scriptDir "chatgpt-return.cmd") -InputFile $packetPath -Project $Project -RequirePacket -Json
    }
    $importObj = $null
    try { $importObj = $importJson.Output | ConvertFrom-Json } catch { $importObj = $null }
    $importOk = $importObj -and $importObj.HasPacket -eq $true -and (Test-Path -LiteralPath $importObj.Saved)
    Add-Check "return import $i" ($(if ($importOk) { "pass" } else { "fail" })) ($(if ($importOk) { $importObj.Saved } else { ($importJson.Output + $importJson.Error).Trim() }))
}

$browserBridgePath = Join-Path $scriptDir "chatgpt-chrome-bridge.mjs"
$bridgeText = if (Test-Path -LiteralPath $browserBridgePath) { Get-Content -LiteralPath $browserBridgePath -Raw } else { "" }
$hasProbe = $bridgeText -match "probeChatGptChromeBridgeRuntime"
$browserDetail = "PowerShell can verify prep/import only. Run probeChatGptChromeBridgeRuntime from a Codex Desktop Node runtime to verify agent.browsers."
if ($hasProbe) {
    Add-Check "Chrome runtime probe export exists" "pass" $browserBridgePath
} else {
    Add-Check "Chrome runtime probe export exists" "warn" $browserDetail
}
if ($RequireBrowserRuntime) {
    Add-Check "Chrome runtime live verification" "fail" "Not available to PowerShell; run the emitted RunnerSnippet or probe from Codex Desktop Node REPL."
} else {
    Add-Check "Chrome runtime live verification" "warn" $browserDetail
}

$chatSessionPaths = @()
foreach ($session in $chatSessions) {
    $chatSessionPaths += "$($session.SessionPath)"
}
$deepSessionPaths = @()
foreach ($session in $deepSessions) {
    $deepSessionPaths += "$($session.SessionPath)"
}

$summaryStatus = if ($script:Failures.Count -eq 0) { "pass" } else { "fail" }
$failureList = @()
foreach ($failure in $script:Failures) { $failureList += "$failure" }
$warningList = @()
foreach ($warning in $script:Warnings) { $warningList += "$warning" }
$checkList = @()
foreach ($check in $script:Checks) { $checkList += $check }

$summary = [pscustomobject]::new()
$summary | Add-Member -NotePropertyName "Status" -NotePropertyValue $summaryStatus
$summary | Add-Member -NotePropertyName "Project" -NotePropertyValue $Project
$summary | Add-Member -NotePropertyName "Iterations" -NotePropertyValue $Iterations
$summary | Add-Member -NotePropertyName "CodexHome" -NotePropertyValue $CodexHome
$summary | Add-Member -NotePropertyName "OutputDir" -NotePropertyValue $bridgeOutDir
$summary | Add-Member -NotePropertyName "Failures" -NotePropertyValue $failureList
$summary | Add-Member -NotePropertyName "Warnings" -NotePropertyValue $warningList
$summary | Add-Member -NotePropertyName "ChatGPTSessions" -NotePropertyValue $chatSessionPaths
$summary | Add-Member -NotePropertyName "DeepSeekSessions" -NotePropertyValue $deepSessionPaths
$summary | Add-Member -NotePropertyName "Checks" -NotePropertyValue $checkList

if ($Json) {
    [pscustomobject]$summary | ConvertTo-Json -Depth 8
} else {
    Write-Host ""
    Write-Host "Bridge smoke test summary"
    Write-Host "Status: $($summary.Status)"
    Write-Host "Failures: $($script:Failures.Count)"
    Write-Host "Warnings: $($script:Warnings.Count)"
    Write-Host "Output: $bridgeOutDir"
}

if ($script:Failures.Count -gt 0) { exit 1 }
exit 0
