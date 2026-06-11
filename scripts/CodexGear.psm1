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

function ConvertTo-ChatGatewayTaskText {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text
    )

    return (($Text -replace "\s+", " ").Trim().ToLowerInvariant())
}

function Get-ChatGatewayTaskKey {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,
        [string] $Project = "Gateway"
    )

    $normalizedTask = ConvertTo-ChatGatewayTaskText -Text $Text
    $normalizedProject = ConvertTo-ChatGatewayTaskText -Text $Project
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$normalizedProject`n$normalizedTask")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
        return (($hashBytes | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha.Dispose()
    }
}

function Test-ChatGatewayFreshnessSensitive {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text
    )

    $normalized = ConvertTo-ChatGatewayTaskText -Text $Text
    return ($normalized -match "\b(today|tonight|tomorrow|yesterday|latest|current|recent|newest|news|live|now|as of|this week|this month|this quarter|price|pricing|stock|market|weather|schedule|score|standings|exchange rate|rate limit)\b")
}

function Get-ChatGatewayCacheEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string] $CodexHome,
        [Parameter(Mandatory = $true)]
        [string] $Task,
        [string] $Project = "Gateway",
        [int] $TtlDays = 14,
        [switch] $IgnoreFreshness
    )

    $key = Get-ChatGatewayTaskKey -Text $Task -Project $Project
    $cachePath = Join-Path $CodexHome "cache\chatgpt-bridge\$key.json"

    if (-not $IgnoreFreshness -and (Test-ChatGatewayFreshnessSensitive -Text $Task)) {
        return [pscustomobject]@{
            Hit = $false
            Status = "freshness-bypass"
            Reason = "Task appears time-sensitive; cache reuse is disabled."
            Key = $key
            Path = $cachePath
            Entry = $null
        }
    }

    if (-not (Test-Path -LiteralPath $cachePath)) {
        return [pscustomobject]@{
            Hit = $false
            Status = "miss"
            Reason = "No exact completed ChatGPT result is cached for this project/task."
            Key = $key
            Path = $cachePath
            Entry = $null
        }
    }

    try {
        $entry = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{
            Hit = $false
            Status = "invalid"
            Reason = "Cache entry could not be parsed: $($_.Exception.Message)"
            Key = $key
            Path = $cachePath
            Entry = $null
        }
    }

    $completedAt = $null
    if ($entry.CompletedAt) {
        try { $completedAt = [datetime]::Parse($entry.CompletedAt) } catch { $completedAt = $null }
    }
    if ($completedAt -and $TtlDays -gt 0 -and $completedAt -lt (Get-Date).AddDays(-1 * $TtlDays)) {
        return [pscustomobject]@{
            Hit = $false
            Status = "stale"
            Reason = "Cached result is older than $TtlDays day(s)."
            Key = $key
            Path = $cachePath
            Entry = $entry
        }
    }

    $handoffPath = if ($entry.HandoffPath) { $entry.HandoffPath } else { "" }
    $responsePath = if ($entry.ResponsePath) { $entry.ResponsePath } else { "" }
    $hasUsableText = ($handoffPath -and (Test-Path -LiteralPath $handoffPath)) -or
        ($responsePath -and (Test-Path -LiteralPath $responsePath))
    if (-not $hasUsableText) {
        return [pscustomobject]@{
            Hit = $false
            Status = "missing-artifact"
            Reason = "Cache metadata exists, but the handoff/response file is missing."
            Key = $key
            Path = $cachePath
            Entry = $entry
        }
    }

    return [pscustomobject]@{
        Hit = $true
        Status = "hit"
        Reason = "Exact completed ChatGPT result found."
        Key = $key
        Path = $cachePath
        Entry = $entry
    }
}

function Get-ChatGatewaySavingsEstimate {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,
        [string] $Route = "codex",
        [object[]] $ChatGPTSignals = @(),
        [string] $CodexFallbackProfile = "fast",
        [switch] $CacheHit
    )

    $wordCount = [regex]::Matches($Text, "\S+").Count
    $signalText = (($ChatGPTSignals | ForEach-Object { "$_" }) -join " ").ToLowerInvariant()
    $turns = 0
    $tokens = 0

    if ($Route -eq "chatgpt") {
        $turns = 1
        $tokens = 9000 + ([math]::Min($wordCount, 800) * 25)
        if ($signalText -match "research|strategy|ideas") { $tokens += 5000 }
        if ($signalText -match "design|creative|logo|image") { $tokens += 9000; $turns = 2 }
        if ($signalText -match "summary|explanation") { $tokens += 3000 }
    } elseif ($Route -eq "hybrid") {
        $turns = 1
        $tokens = 6000 + ([math]::Min($wordCount, 600) * 18)
    }

    if ($CodexFallbackProfile -eq "deep") { $tokens += 6000 }
    if ($CodexFallbackProfile -eq "max") { $tokens += 12000 }
    if ($CacheHit) { $tokens += 3000 }

    return [pscustomobject]@{
        Basis = "heuristic"
        AvoidedCodexTurns = $turns
        EstimatedAvoidedCodexTokens = [int]$tokens
        Note = "Not billing data; this is a routing pressure estimate for comparing gateway savings."
    }
}

function New-ChatGatewayHybridSplit {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text
    )

    $codexTarget = "the local project"
    $fileMatch = [regex]::Match($Text, "\b[\w.-]+\.(ts|tsx|js|jsx|py|ps1|cmd|md|json|yml|yaml|toml|css|html|sql|sh|bat|cs|go|rs|java|php|rb)\b")
    if ($fileMatch.Success) {
        $codexTarget = $fileMatch.Value
    } elseif ($Text -match "(?i)\b(this project|project folder|site|app|repo|repository|workspace)\b") {
        $codexTarget = $Matches[1]
    }

    $chatTask = @"
Original hybrid request:
$Text

Do only the detachable ChatGPT-safe part: writing, brainstorming, strategy, summary, or design direction/generation. Do not inspect or claim access to local files, repo state, accounts, secrets, logs, tests, builds, git, deployment, or browser verification.

Return the useful deliverable and a CODEX_RETURN_PACKET. In "Codex next action", tell Codex exactly how to apply or verify the result locally in $codexTarget.
"@.Trim()

    $codexTask = "After importing the ChatGPT return packet, apply or verify the result locally in $codexTarget. Inspect files before editing and run the relevant local checks."

    return [pscustomobject]@{
        ChatGPTTask = $chatTask
        CodexTask = $codexTask
        LocalTarget = $codexTarget
        WillDispatchChatGPT = $true
        RequiresCodexAfterReturn = $true
    }
}

function Get-CodexLatestTokenSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string] $CodexHome,
        [int] $MaxFiles = 8,
        [int] $Tail = 250
    )

    $sessionsDir = Join-Path $CodexHome "sessions"
    if (-not (Test-Path -LiteralPath $sessionsDir)) {
        return $null
    }

    $files = Get-ChildItem -LiteralPath $sessionsDir -Recurse -Filter "*.jsonl" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $MaxFiles

    foreach ($file in $files) {
        try {
            $lines = Get-Content -LiteralPath $file.FullName -Tail $Tail -ErrorAction Stop
        } catch {
            continue
        }

        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $line = $lines[$i]
            if ($line -notmatch '"token_count"') { continue }
            try {
                $record = $line | ConvertFrom-Json
                if ($record.payload.type -ne "token_count") { continue }
                $usage = $record.payload.info.total_token_usage
                $lastUsage = $record.payload.info.last_token_usage
                $limits = if ($record.rate_limits) { $record.rate_limits } elseif ($record.payload.rate_limits) { $record.payload.rate_limits } else { $null }
                return [pscustomobject]@{
                    SessionPath = $file.FullName
                    Timestamp = $record.timestamp
                    TotalTokens = $usage.total_tokens
                    InputTokens = $usage.input_tokens
                    CachedInputTokens = $usage.cached_input_tokens
                    OutputTokens = $usage.output_tokens
                    ReasoningOutputTokens = $usage.reasoning_output_tokens
                    LastTurnTokens = $lastUsage.total_tokens
                    ModelContextWindow = $record.payload.info.model_context_window
                    PlanType = if ($limits) { $limits.plan_type } else { $null }
                    PrimaryUsedPercent = if ($limits -and $limits.primary) { $limits.primary.used_percent } else { $null }
                    PrimaryWindowMinutes = if ($limits -and $limits.primary) { $limits.primary.window_minutes } else { $null }
                    PrimaryResetsAt = if ($limits -and $limits.primary) { $limits.primary.resets_at } else { $null }
                    SecondaryUsedPercent = if ($limits -and $limits.secondary) { $limits.secondary.used_percent } else { $null }
                    SecondaryWindowMinutes = if ($limits -and $limits.secondary) { $limits.secondary.window_minutes } else { $null }
                    SecondaryResetsAt = if ($limits -and $limits.secondary) { $limits.secondary.resets_at } else { $null }
                }
            } catch {
                continue
            }
        }
    }

    return $null
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
        "code/build/test/git work" = "(\b(code|codebase|implement|implementation|component|page|route|api|endpoint|database|migration|schema|script|fix|bug|debug|tests|build|lint|typecheck|git|commit|branch|push|pull request|pr|ci|github actions|deploy|deployment|logs?|stack trace|crash|terminal|shell|powershell|cmd|npm|pnpm|yarn|python|node)\b|\b(failing|broken|unit|integration|e2e|smoke|regression)\s+tests?\b|\b(run|rerun|execute|write|add)\s+tests?\b)"
        "browser or app verification" = "\b(browser|chrome|screenshot|playwright|localhost|127\.0\.0\.1|app verification|responsive|mobile|desktop qa)\b"
        "connected apps or private account state" = "\b(gmail|email inbox|inbox|slack|notion|linear|jira|github|vercel|supabase|stripe|datadog|sentry|google analytics|search console|cloudflare|zapier|make\.com|connector|mcp|app session)\b"
        "local asset generation or export" = "(\b(save|export|download|render)\b.*\b(logos?|images?|assets?|png|jpe?g|svg|webp|pdf)\b|\b(logos?|images?|assets?|png|jpe?g|svg|webp|pdf)\b.*\b(save|export|download|render)\b)"
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
        "ideas or strategy" = "\b(brainstorm|ideate|ideas?|naming|name ideas|domain names?|strategy|plan|critique|second opinion|options?|pros and cons|positioning|offer|angle|campaign|go-to-market|gtm)\b"
        "summary or explanation" = "\b(summarize|summary|outline|explain|teach|learn|notes?|meeting notes|synthesis|classify)\b"
        "research or comparison without local execution" = "\b(research|compare|competitor|market scan|best practices|examples?|sources?|literature|overview)\b"
        "translation or transformation" = "\b(translate|transcribe cleanup|condense|expand|turn .* into|convert .* into)\b"
        "design direction" = "\b(moodboard|layout concept|design direction|ad concept|poster concept|social concept|image prompt|color palette|typography|logos?|logo concepts?|brand identity|visual identity|wordmark|brand mark)\b"
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

function Select-ChatGatewayRoute {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,
        [switch] $ForceCodex,
        [switch] $ForceChatGPT
    )

    $normalized = $Text.ToLowerInvariant()
    $codexSignals = New-Object System.Collections.Generic.List[string]
    $chatGptSignals = New-Object System.Collections.Generic.List[string]

    $forceCodexTag = $normalized -match "\[(codex|force-codex)\]" -or $normalized -match "\s--(codex|force-codex)\b"
    $forceChatGptTag = $normalized -match "\[(chatgpt|gpt|force-chatgpt)\]" -or $normalized -match "\s--(chatgpt|gpt|force-chatgpt)\b"

    if ($ForceCodex -or $forceCodexTag) {
        $codexSignals.Add("explicit Codex override")
        return [pscustomobject]@{
            Route = "codex"
            Dispatch = "codex-auto"
            Reason = "Explicit Codex override was provided."
            Confidence = "high"
            AskFirst = $false
            CodexSignals = $codexSignals.ToArray()
            ChatGPTSignals = @()
            NextAction = "Dispatch through codex-auto with credit optimization disabled."
        }
    }

    if ($ForceChatGPT -or $forceChatGptTag) {
        $chatGptSignals.Add("explicit ChatGPT override")
        return [pscustomobject]@{
            Route = "chatgpt"
            Dispatch = "chatgpt-auto-route"
            Reason = "Explicit ChatGPT override was provided."
            Confidence = "high"
            AskFirst = $false
            CodexSignals = @()
            ChatGPTSignals = $chatGptSignals.ToArray()
            NextAction = "Prepare a ChatGPT bridge session with a compact return packet."
        }
    }

    $gearOverride = $normalized -match "\[(low|fast|medium|balanced|high|deep|xhigh|max|review)\]" -or
        $normalized -match "\s--(low|fast|medium|balanced|high|deep|xhigh|max|review)\b"
    if ($gearOverride) {
        $codexSignals.Add("explicit Codex gear override")
    }

    $codexSignalDefs = [ordered]@{
        "local files or repo context" = "(\b(repo|repository|codebase|workspace|local files?|filesystem|folder|directory|path|cwd|project folder|this project)\b|[a-z]:\\|\.codex|agents\.md)"
        "code/build/test/git work" = "(\b(code|codebase|implement|implementation|component|page|route|api|endpoint|database|migration|schema|script|fix|bug|debug|tests|build|lint|typecheck|git|commit|branch|push|pull request|pr|ci|github actions|deploy|deployment|logs?|stack trace|crash|terminal|shell|powershell|cmd|npm|pnpm|yarn|python|node)\b|\b(failing|broken|unit|integration|e2e|smoke|regression)\s+tests?\b|\b(run|rerun|execute|write|add)\s+tests?\b)"
        "browser or app verification" = "\b(browser|chrome|screenshot|playwright|localhost|127\.0\.0\.1|app verification|responsive|mobile|desktop qa)\b"
        "connected apps or private account state" = "\b(gmail|email inbox|inbox|slack|notion|linear|jira|github|vercel|supabase|stripe|datadog|sentry|google analytics|search console|cloudflare|zapier|make\.com|connector|mcp|app session)\b"
        "local asset generation or export" = "(\b(save|export|download|render|wire|apply)\b.*\b(logos?|images?|assets?|png|jpe?g|svg|webp|pdf|site|page|project|folder)\b|\b(logos?|images?|assets?|png|jpe?g|svg|webp|pdf)\b.*\b(save|export|download|render|wire|apply)\b)"
        "sensitive or production risk" = "\b(auth|oauth|security|secret|token|permissions?|billing|payments?|production|prod|owner button|env vars?|api key)\b"
        "specific file path or extension" = "\b[\w.-]+\.(ts|tsx|js|jsx|py|ps1|cmd|md|json|yml|yaml|toml|css|html|sql|sh|bat|cs|go|rs|java|php|rb)\b"
    }

    $chatGptSignalDefs = [ordered]@{
        "writing or copy" = "\b(write|rewrite|draft|polish|edit|improve|email|message|post|copy|tone|headline|tagline|slogan|cold email|sales copy)\b"
        "ideas or strategy" = "\b(brainstorm|ideate|ideas?|naming|name ideas|domain names?|strategy|plan|critique|second opinion|options?|pros and cons|positioning|offer|angle|campaign|go-to-market|gtm)\b"
        "summary or explanation" = "\b(summarize|summary|outline|explain|teach|learn|notes?|meeting notes|synthesis|classify|pasted text)\b"
        "research or comparison without local execution" = "\b(research|compare|competitor|market scan|best practices|examples?|sources?|literature|overview)\b"
        "translation or transformation" = "\b(translate|transcribe cleanup|condense|expand|turn .* into|convert .* into)\b"
        "design or creative generation" = "\b(moodboard|layout concept|design direction|ad concept|poster concept|social concept|image prompt|color palette|typography|logos?|logo sheet|logo concepts?|brand identity|visual identity|wordmark|brand mark|visual mockup|ad creative)\b"
    }

    foreach ($entry in $codexSignalDefs.GetEnumerator()) {
        if ($normalized -match $entry.Value -and -not $codexSignals.Contains($entry.Key)) {
            $codexSignals.Add($entry.Key)
        }
    }
    foreach ($entry in $chatGptSignalDefs.GetEnumerator()) {
        if ($normalized -match $entry.Value) {
            $chatGptSignals.Add($entry.Key)
        }
    }

    $hasSensitiveSignal = $codexSignals.Contains("sensitive or production risk") -or
        $codexSignals.Contains("connected apps or private account state")
    $hasCodexSignals = $codexSignals.Count -gt 0
    $hasChatGptSignals = $chatGptSignals.Count -gt 0

    if ($hasSensitiveSignal) {
        return [pscustomobject]@{
            Route = "codex"
            Dispatch = "codex-auto"
            Reason = "Sensitive, account, connector, or production-risk work must stay in Codex unless explicitly forced."
            Confidence = "high"
            AskFirst = $true
            CodexSignals = $codexSignals.ToArray()
            ChatGPTSignals = $chatGptSignals.ToArray()
            NextAction = "Keep in Codex; use ChatGPT only for a bounded second opinion after approval if needed."
        }
    }

    if ($hasCodexSignals -and $hasChatGptSignals) {
        return [pscustomobject]@{
            Route = "hybrid"
            Dispatch = "ask-first"
            Reason = "The task mixes detachable ChatGPT work with local Codex execution."
            Confidence = "medium"
            AskFirst = $true
            CodexSignals = $codexSignals.ToArray()
            ChatGPTSignals = $chatGptSignals.ToArray()
            NextAction = "Ask before splitting: ChatGPT should do the detachable thinking or creative pass, then Codex should apply or verify locally."
        }
    }

    if ($hasChatGptSignals) {
        return [pscustomobject]@{
            Route = "chatgpt"
            Dispatch = "chatgpt-auto-route"
            Reason = "The task is high-confidence detachable work and can preserve Codex usage."
            Confidence = "high"
            AskFirst = $false
            CodexSignals = @()
            ChatGPTSignals = $chatGptSignals.ToArray()
            NextAction = "Prepare a ChatGPT bridge session with a compact return packet."
        }
    }

    if ($hasCodexSignals) {
        return [pscustomobject]@{
            Route = "codex"
            Dispatch = "codex-auto"
            Reason = "The task appears to need local files, tools, verification, or Codex execution."
            Confidence = "high"
            AskFirst = $false
            CodexSignals = $codexSignals.ToArray()
            ChatGPTSignals = @()
            NextAction = "Dispatch through codex-auto with credit optimization disabled."
        }
    }

    return [pscustomobject]@{
        Route = "codex"
        Dispatch = "codex-auto"
        Reason = "No high-confidence ChatGPT handoff signal was found."
        Confidence = "low"
        AskFirst = $true
        CodexSignals = @()
        ChatGPTSignals = @()
        NextAction = "Keep in Codex unless the user explicitly forces ChatGPT."
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

Export-ModuleMember -Function Get-CodexGearMatrix, Get-CodexGear, Select-CodexGear, Select-AiWorkRoute, Select-ChatGatewayRoute, ConvertTo-ChatGatewayTaskText, Get-ChatGatewayTaskKey, Test-ChatGatewayFreshnessSensitive, Get-ChatGatewayCacheEntry, Get-ChatGatewaySavingsEstimate, New-ChatGatewayHybridSplit, Get-CodexLatestTokenSnapshot, Get-CodexExecutable, New-CodexConfigArgs
