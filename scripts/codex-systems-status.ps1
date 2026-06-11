param(
    [string] $CodexHome = "",
    [string] $SystemsRepo = "C:\Repos\codex-ai-systems",
    [string] $Task = ""
)

$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$ErrorActionPreference = "Continue"

function Write-Section {
    param([string] $Name)
    Write-Host ""
    Write-Host $Name
    Write-Host ("-" * $Name.Length)
}

function Invoke-GitText {
    param(
        [string[]] $GitArgs,
        [string] $WorkDir = (Get-Location).Path
    )

    $output = & git -C $WorkDir @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return "" }
    return (($output | Out-String).Trim())
}

$scriptRoot = Join-Path $CodexHome "scripts"
$gearModule = Join-Path $scriptRoot "CodexGear.psm1"
if (Test-Path -LiteralPath $gearModule) {
    Import-Module $gearModule -Force
}

Write-Host "Codex systems status"
Write-Host "Codex home: $CodexHome"
Write-Host "Current dir: $((Get-Location).Path)"

Write-Section "Current Git Repo"
$repoRoot = Invoke-GitText -GitArgs @("rev-parse", "--show-toplevel")
if ($repoRoot) {
    $branch = Invoke-GitText -GitArgs @("branch", "--show-current") -WorkDir $repoRoot
    $origin = Invoke-GitText -GitArgs @("remote", "get-url", "origin") -WorkDir $repoRoot
    $head = Invoke-GitText -GitArgs @("log", "-1", "--oneline") -WorkDir $repoRoot
    $dirtyText = Invoke-GitText -GitArgs @("status", "--short") -WorkDir $repoRoot
    $dirty = @($dirtyText -split "`r?`n" | Where-Object { $_ })

    Write-Host "Repo: $repoRoot"
    Write-Host "Branch: $branch"
    if ($origin) { Write-Host "Origin: $origin" } else { Write-Host "Origin: (none)" }
    Write-Host "HEAD: $head"
    Write-Host "Dirty files: $($dirty.Count)"
    foreach ($line in $dirty) { Write-Host "  $line" }
} else {
    Write-Host "Not inside a git repo."
}

Write-Section "Owner Buttons"
$queuePath = Join-Path $CodexHome "queues\owner-buttons.json"
if (Test-Path -LiteralPath $queuePath) {
    $rawQueue = Get-Content -Path $queuePath -Raw
    $queueItems = @()
    if (-not [string]::IsNullOrWhiteSpace($rawQueue)) {
        $parsedQueue = $rawQueue | ConvertFrom-Json
        if ($null -ne $parsedQueue) { $queueItems = @($parsedQueue) }
    }
    $openButtons = @($queueItems | Where-Object { $_.Status -eq "open" })
    if ($openButtons.Count -eq 0) {
        Write-Host "Owner Button Queue: no open owner buttons."
    } else {
        Write-Host "Owner Button Queue: $($openButtons.Count) open"
        foreach ($item in $openButtons) {
            Write-Host ""
            Write-Host "ID: $($item.Id)"
            Write-Host "Project: $($item.Project)"
            Write-Host "Site/tool: $($item.Site)"
            Write-Host "Needed: $($item.Needed)"
            if ($item.Why) { Write-Host "Why Codex is blocked: $($item.Why)" }
            if ($item.Next) { Write-Host "Codex next: $($item.Next)" }
            Write-Host "Created: $($item.CreatedAt)"
        }
    }
    Write-Host "Queue file: $queuePath"
} else {
    Write-Host "Queue file not found: $queuePath"
}

Write-Section "Gear Routes"
if (Test-Path -LiteralPath $gearModule) {
    $matrix = Get-CodexGearMatrix
    $matrix.Values |
        Select-Object Profile, Gear, Model, Effort, @{Name="ServiceTier";Expression={if ($_.ServiceTier) {$_.ServiceTier} else {"(default/none)"}}}, Command |
        Format-Table -AutoSize

    if ($Task) {
        $workRoute = Select-AiWorkRoute -Text $Task
        $gatewayRoute = Select-ChatGatewayRoute -Text $Task
        $cacheEntry = if ($gatewayRoute.Route -eq "chatgpt") { Get-ChatGatewayCacheEntry -CodexHome $CodexHome -Task $Task -Project "Gateway" } else { $null }
        $profile = Select-CodexGear -Text $Task
        $gear = Get-CodexGear -Profile $profile
        Write-Host "Task route: $Task"
        Write-Host "AI work route: $($workRoute.Route) ($($workRoute.Reason))"
        Write-Host "Gateway route: $($gatewayRoute.Route) ($($gatewayRoute.Reason))"
        if ($cacheEntry) { Write-Host "Gateway cache: $($cacheEntry.Status) ($($cacheEntry.Reason))" }
        Write-Host "Codex fallback: $($gear.Profile) / $($gear.Gear) / $($gear.Model) / $($gear.Effort)"
    }
} else {
    Write-Host "CodexGear.psm1 not found."
}

Write-Section "ChatGPT Bridge Cache"
$cacheDir = Join-Path $CodexHome "cache\chatgpt-bridge"
if (Test-Path -LiteralPath $cacheDir) {
    $cacheFiles = @(Get-ChildItem -LiteralPath $cacheDir -Filter "*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    Write-Host "Cache entries: $($cacheFiles.Count)"
    foreach ($item in ($cacheFiles | Select-Object -First 5)) {
        try {
            $entry = Get-Content -LiteralPath $item.FullName -Raw | ConvertFrom-Json
            Write-Host "  $($entry.Project) | $($entry.CompletedAt) | assets=$($entry.AssetCount) | $($entry.Task)"
        } catch {
            Write-Host "  invalid cache entry: $($item.FullName)"
        }
    }
} else {
    Write-Host "Cache entries: 0"
}

Write-Section "Systems Backup"
if (Test-Path -LiteralPath $SystemsRepo) {
    $systemsBranch = Invoke-GitText -GitArgs @("branch", "--show-current") -WorkDir $SystemsRepo
    $systemsOrigin = Invoke-GitText -GitArgs @("remote", "get-url", "origin") -WorkDir $SystemsRepo
    $systemsHead = Invoke-GitText -GitArgs @("log", "-1", "--oneline") -WorkDir $SystemsRepo
    $systemsDirtyText = Invoke-GitText -GitArgs @("status", "--short") -WorkDir $SystemsRepo
    $systemsDirty = @($systemsDirtyText -split "`r?`n" | Where-Object { $_ })

    Write-Host "Repo: $SystemsRepo"
    Write-Host "Branch: $systemsBranch"
    Write-Host "Origin: $systemsOrigin"
    Write-Host "HEAD: $systemsHead"
    Write-Host "Dirty files: $($systemsDirty.Count)"
    foreach ($line in $systemsDirty) { Write-Host "  $line" }
} else {
    Write-Host "Systems repo not found: $SystemsRepo"
}

Write-Section "Useful Commands"
Write-Host "$scriptRoot\codex-systems-status.cmd"
Write-Host "$scriptRoot\ai-credits-optimizer.cmd -DryRun `"draft a client email from these notes`""
Write-Host "$scriptRoot\codex-gateway.cmd -DryRun `"write a cold email`""
Write-Host "$scriptRoot\codex-gateway.cmd -Refresh `"write a cold email`""
Write-Host "$scriptRoot\codex-gateway-tally.cmd"
Write-Host "$scriptRoot\codex-gateway-tally.cmd -All -IncludeTestProjects"
Write-Host "$scriptRoot\codex-gateway-feedback.cmd -Task `"write a cold email`" -Rating 5 -Outcome good"
Write-Host "$scriptRoot\chatgpt-route.cmd `"draft a client email from these notes`""
Write-Host "$scriptRoot\chatgpt-route.cmd `"brainstorm poster concepts for this launch`""
Write-Host "$scriptRoot\chatgpt-return.cmd -Print"
Write-Host "$scriptRoot\codex-project-rules.cmd"
Write-Host "$scriptRoot\zdh-worker-boss-interval.cmd 20"
Write-Host "$scriptRoot\codex-project-freshness.cmd"
Write-Host "$scriptRoot\codex-bounce.cmd `"plan database migration safely`""
Write-Host "$scriptRoot\codex-council.cmd `"build billing-safe workflow`""
Write-Host "$scriptRoot\codex-xhigh-raw.cmd `"raw xhigh without council`""
Write-Host "$scriptRoot\codex-gear.cmd `"debug failing CI`""
Write-Host "$scriptRoot\codex-gear-test.cmd"
Write-Host "$scriptRoot\codex-gear-test.cmd -Smoke"
Write-Host "$scriptRoot\codex-handoff.cmd"
