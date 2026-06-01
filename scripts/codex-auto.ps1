param(
    [switch] $DryRun,
    [string] $Cwd = (Get-Location).Path,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $PromptParts
)

$prompt = ($PromptParts -join " ").Trim()
if (-not $prompt) {
    Write-Error "Usage: codex-auto.ps1 [-DryRun] [-Cwd PATH] <task prompt>"
    exit 2
}

$normalized = $prompt.ToLowerInvariant()

function Select-CodexProfile {
    param([string] $Text)

    if ($Text -match "\[(low|fast)\]" -or $Text -match "\b--(low|fast)\b") {
        return "fast"
    }
    if ($Text -match "\[(medium|balanced)\]" -or $Text -match "\b--(medium|balanced)\b") {
        return "balanced"
    }
    if ($Text -match "\[(high|deep)\]" -or $Text -match "\b--(high|deep)\b") {
        return "deep"
    }
    if ($Text -match "\[(xhigh|max)\]" -or $Text -match "\b--(xhigh|max)\b") {
        return "max"
    }

    $score = 0

    $lowPatterns = @(
        "\btypo\b", "\bcopy\b", "\btext change\b", "\blink\b", "\bbutton\b",
        "\bcolor\b", "\bspacing\b", "\brename\b", "\bstatus\b", "\bquick\b",
        "\bcommit\b", "\bpush\b", "\bshow me\b"
    )
    foreach ($pattern in $lowPatterns) {
        if ($Text -match $pattern) { $score -= 1 }
    }

    $mediumPatterns = @(
        "\badd\b", "\bbuild\b", "\bcreate\b", "\bfix\b", "\bform\b",
        "\bpage\b", "\bcomponent\b", "\bstyle\b", "\bmobile\b", "\bresponsive\b"
    )
    foreach ($pattern in $mediumPatterns) {
        if ($Text -match $pattern) { $score += 1 }
    }

    $highPatterns = @(
        "\bdebug\b", "\bfailing\b", "\btest\b", "\bci\b", "\breview\b",
        "\bregression\b", "\bperformance\b", "\brefactor\b", "\bmigration\b",
        "\bmulti[- ]file\b", "\bacross the site\b", "\bproduction\b", "\bdeploy\b"
    )
    foreach ($pattern in $highPatterns) {
        if ($Text -match $pattern) { $score += 2 }
    }

    $maxHits = 0
    $maxPatterns = @(
        "\barchitecture\b", "\bsecurity\b", "\bauth\b", "\bbilling\b",
        "\bpayments?\b", "\bdatabase\b", "\bdata loss\b", "\bpermissions?\b",
        "\bstrategy\b", "\bcomplex\b", "\brace condition\b", "\bthreading\b"
    )
    foreach ($pattern in $maxPatterns) {
        if ($Text -match $pattern) {
            $score += 3
            $maxHits += 1
        }
    }

    if ($maxHits -gt 0) { return "max" }
    if ($score -le 0) { return "fast" }
    if ($score -le 4) { return "balanced" }
    return "deep"
}

$profile = Select-CodexProfile -Text $normalized
$effortByProfile = @{
    fast = "low"
    balanced = "medium"
    deep = "high"
    max = "xhigh"
}

Write-Host "Codex auto gear: $profile ($($effortByProfile[$profile]))"
Write-Host "Workspace: $Cwd"

$logDir = Join-Path $env:USERPROFILE ".codex\logs"
$logPath = Join-Path $logDir "reasoning-gear.log"
New-Item -ItemType Directory -Force $logDir | Out-Null
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[$timestamp] $profile/$($effortByProfile[$profile]) | $Cwd | $prompt" | Add-Content -Path $logPath

if ($DryRun) {
    Write-Host "Dry run only. Prompt: $prompt"
    Write-Host "Logged to: $logPath"
    exit 0
}

$codex = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin\7dea4a003bc76627\codex.exe"
& $codex exec -C $Cwd -p $profile $prompt
