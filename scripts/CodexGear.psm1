function Get-CodexGearMatrix {
    $matrix = [ordered]@{
        fast = [pscustomobject]@{
            Profile = "fast"
            Gear = "low"
            Model = "gpt-5.3-codex-spark"
            Effort = "low"
            ServiceTier = ""
            Command = "exec"
            Purpose = "Ultra-fast simple coding, status checks, typos, copy, links, and obvious one-file fixes."
        }
        balanced = [pscustomobject]@{
            Profile = "balanced"
            Gear = "medium"
            Model = "gpt-5.4"
            Effort = "medium"
            ServiceTier = "fast"
            Command = "exec"
            Purpose = "Normal implementation work: components, pages, forms, docs, and ordinary bug fixes."
        }
        deep = [pscustomobject]@{
            Profile = "deep"
            Gear = "high"
            Model = "gpt-5.5"
            Effort = "high"
            ServiceTier = "fast"
            Command = "exec"
            Purpose = "Debugging, CI/test failures, regressions, multi-file work, deploy problems, and verification-heavy tasks."
        }
        max = [pscustomobject]@{
            Profile = "max"
            Gear = "xhigh"
            Model = "gpt-5.5"
            Effort = "xhigh"
            ServiceTier = "fast"
            Command = "exec"
            Purpose = "Architecture, auth, security, billing, database, permissions, production-risk, or ambiguous complex failures."
        }
        review = [pscustomobject]@{
            Profile = "review"
            Gear = "review"
            Model = "codex-auto-review"
            Effort = "medium"
            ServiceTier = ""
            Command = "review"
            Purpose = "Explicit code review, PR review, diff review, or commit review."
        }
    }
    return $matrix
}

function Get-CodexGear {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Profile
    )

    $matrix = Get-CodexGearMatrix
    if (-not $matrix.Contains($Profile)) {
        throw "Unknown Codex gear profile: $Profile"
    }
    return $matrix[$Profile]
}

function Select-CodexGear {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text
    )

    $normalized = $Text.ToLowerInvariant()

    if ($normalized -match "\[(low|fast)\]" -or $normalized -match "\b--(low|fast)\b") {
        return "fast"
    }
    if ($normalized -match "\[(medium|balanced)\]" -or $normalized -match "\b--(medium|balanced)\b") {
        return "balanced"
    }
    if ($normalized -match "\[(high|deep)\]" -or $normalized -match "\b--(high|deep)\b") {
        return "deep"
    }
    if ($normalized -match "\[(xhigh|max)\]" -or $normalized -match "\b--(xhigh|max)\b") {
        return "max"
    }
    if ($normalized -match "\[(review)\]" -or $normalized -match "\b--review\b") {
        return "review"
    }

    $explicitReview =
        $normalized -match "\b(code|pr|pull request|diff|commit)\s+review\b" -or
        $normalized -match "\breview\s+(the\s+|this\s+)?(code|pr|pull request|diff|commit|changes)\b"
    if ($explicitReview) {
        return "review"
    }

    $score = 0

    $lowPatterns = @(
        "\btypo\b", "\bcopy\b", "\btext change\b", "\blink\b", "\bbutton\b",
        "\bcolor\b", "\bspacing\b", "\brename\b", "\bstatus\b", "\bquick\b",
        "\bshow me\b", "\blist\b", "\bdoes .* exist\b", "\bcheck whether\b"
    )
    foreach ($pattern in $lowPatterns) {
        if ($normalized -match $pattern) { $score -= 1 }
    }

    $mediumPatterns = @(
        "\badd\b", "\bbuild\b", "\bcreate\b", "\bfix\b", "\bform\b",
        "\bpage\b", "\bcomponent\b", "\bstyle\b", "\bmobile\b", "\bresponsive\b",
        "\bscript\b", "\bhelper\b", "\bintegrate\b", "\bwire\b"
    )
    foreach ($pattern in $mediumPatterns) {
        if ($normalized -match $pattern) { $score += 1 }
    }

    $highHits = 0
    $highPatterns = @(
        "\bdebug\b", "\bfailing\b", "\btest\b", "\bci\b", "\breview\b",
        "\bregression\b", "\bperformance\b", "\brefactor\b", "\bmigration\b",
        "\bmulti[- ]file\b", "\bacross the site\b", "\bproduction\b", "\bdeploy\b",
        "\bruntime crash\b", "\berror popup\b", "\bverify\b"
    )
    foreach ($pattern in $highPatterns) {
        if ($normalized -match $pattern) {
            $score += 2
            $highHits += 1
        }
    }

    $maxHits = 0
    $maxPatterns = @(
        "\barchitecture\b", "\bsecurity\b", "\bauth\b", "\bbilling\b",
        "\bpayments?\b", "\bdatabase\b", "\bdata loss\b", "\bpermissions?\b",
        "\bstrategy\b", "\bcomplex\b", "\brace condition\b", "\bthreading\b",
        "\bsecrets?\b", "\btokens?\b", "\bwebhooks?\b", "\bproduction-risk\b"
    )
    foreach ($pattern in $maxPatterns) {
        if ($normalized -match $pattern) {
            $score += 3
            $maxHits += 1
        }
    }

    if ($maxHits -gt 0) { return "max" }
    if ($highHits -gt 0) { return "deep" }
    if ($score -le 0) { return "fast" }
    if ($score -le 4) { return "balanced" }
    return "deep"
}

function Select-AiWorkRoute {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,
        [switch] $ForceCodex,
        [switch] $ForceChatGPT
    )

    $normalized = $Text.ToLowerInvariant()
    $signals = New-Object System.Collections.Generic.List[string]

    $forceCodexTag = $normalized -match "\[(codex|force-codex)\]" -or $normalized -match "\s--(codex|force-codex)\b"
    $forceChatGptTag = $normalized -match "\[(chatgpt|gpt|force-chatgpt)\]" -or $normalized -match "\s--(chatgpt|gpt|force-chatgpt)\b"

    if ($ForceCodex -or $forceCodexTag) {
        $signals.Add("explicit Codex override")
        return [pscustomobject]@{
            Route = "codex"
            Reason = "Explicit Codex override was provided."
            Confidence = "high"
            Signals = $signals.ToArray()
        }
    }

    if ($ForceChatGPT -or $forceChatGptTag) {
        $signals.Add("explicit ChatGPT override")
        return [pscustomobject]@{
            Route = "chatgpt"
            Reason = "Explicit ChatGPT override was provided."
            Confidence = "high"
            Signals = $signals.ToArray()
        }
    }

    $gearOverride = $normalized -match "\[(low|fast|medium|balanced|high|deep|xhigh|max|review)\]" -or
        $normalized -match "\s--(low|fast|medium|balanced|high|deep|xhigh|max|review)\b"
    if ($gearOverride) {
        $signals.Add("explicit Codex gear override")
        return [pscustomobject]@{
            Route = "codex"
            Reason = "A Codex gear override was provided, so the optimizer will not divert it."
            Confidence = "high"
            Signals = $signals.ToArray()
        }
    }

    $codexSignals = [ordered]@{
        "local files or repo context" = "(\b(repo|repository|codebase|workspace|local files?|filesystem|folder|directory|path|cwd)\b|[a-z]:\\|\.codex|agents\.md)"
        "code/build/test/git work" = "\b(code|codebase|implement|implementation|component|page|route|api|endpoint|database|migration|schema|script|fix|bug|debug|test|tests|build|lint|typecheck|git|commit|branch|push|pull request|pr|ci|github actions|deploy|deployment|logs?|stack trace|crash|terminal|shell|powershell|cmd|npm|pnpm|yarn|python|node)\b"
        "browser or app verification" = "\b(browser|chrome|screenshot|playwright|localhost|127\.0\.0\.1|app verification|responsive|mobile|desktop qa)\b"
        "sensitive or production risk" = "\b(auth|oauth|security|secret|token|permissions?|billing|payments?|production|prod|owner button|env vars?|api key)\b"
        "specific file path or extension" = "\b[\w.-]+\.(ts|tsx|js|jsx|py|ps1|cmd|md|json|yml|yaml|toml|css|html|sql|sh|bat|cs|go|rs|java|php|rb)\b"
    }
    foreach ($entry in $codexSignals.GetEnumerator()) {
        if ($normalized -match $entry.Value) {
            $signals.Add($entry.Key)
        }
    }

    if ($signals.Count -gt 0) {
        return [pscustomobject]@{
            Route = "codex"
            Reason = "The task appears to need Codex-local context, tools, verification, or sensitive handling."
            Confidence = "high"
            Signals = $signals.ToArray()
        }
    }

    $chatGptSignals = [ordered]@{
        "writing or copy" = "\b(write|rewrite|draft|polish|edit|improve|email|message|post|copy|tone|headline|tagline|slogan)\b"
        "ideas or strategy" = "\b(brainstorm|ideate|ideas?|naming|name ideas|domain names?|strategy|plan|critique|second opinion|options?|pros and cons)\b"
        "summary or explanation" = "\b(summarize|summary|outline|explain|teach|learn|notes?|meeting notes|synthesis|classify)\b"
        "design direction" = "\b(moodboard|layout concept|design direction|ad concept|poster concept|social concept|image prompt|color palette|typography)\b"
    }
    foreach ($entry in $chatGptSignals.GetEnumerator()) {
        if ($normalized -match $entry.Value) {
            $signals.Add($entry.Key)
        }
    }

    if ($signals.Count -gt 0) {
        return [pscustomobject]@{
            Route = "chatgpt"
            Reason = "The task is a high-confidence non-repo handoff that can preserve Codex usage."
            Confidence = "high"
            Signals = $signals.ToArray()
        }
    }

    return [pscustomobject]@{
        Route = "codex"
        Reason = "No high-confidence ChatGPT handoff signal was found."
        Confidence = "low"
        Signals = @()
    }
}

function Get-CodexExecutable {
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($env:CODEX_CLI_PATH) {
        $candidates.Add($env:CODEX_CLI_PATH)
    }

    $binRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"
    if (Test-Path -LiteralPath $binRoot) {
        Get-ChildItem -LiteralPath $binRoot -Recurse -Filter "codex.exe" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object { $candidates.Add($_.FullName) }
    }

    foreach ($name in @("codex.exe", "codex")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command -and $command.Source) {
            $candidates.Add($command.Source)
        }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Could not find codex.exe. Install or sign into Codex Desktop, then retry."
}

function New-CodexConfigArgs {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Gear
    )

    $args = @(
        "-c", "model=`"$($Gear.Model)`"",
        "-c", "model_reasoning_effort=`"$($Gear.Effort)`""
    )
    if ($null -ne $Gear.ServiceTier) {
        $args += @("-c", "service_tier=`"$($Gear.ServiceTier)`"")
    }
    return $args
}

Export-ModuleMember -Function Get-CodexGearMatrix, Get-CodexGear, Select-CodexGear, Select-AiWorkRoute, Get-CodexExecutable, New-CodexConfigArgs
