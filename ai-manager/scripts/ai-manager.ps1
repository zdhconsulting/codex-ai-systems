param(
    [string] $ConfigPath = "",
    [switch] $Json,
    [switch] $RunCommands,
    [switch] $Fix,
    [string] $OwnerQueuePath = ""
)

$ErrorActionPreference = "Stop"
$managerRoot = Split-Path -Parent $PSScriptRoot
$defaultLocalConfig = Join-Path $managerRoot "projects.local.json"
$defaultExampleConfig = Join-Path $managerRoot "projects.example.json"

if (-not $ConfigPath) {
    if (Test-Path -LiteralPath $defaultLocalConfig) {
        $ConfigPath = $defaultLocalConfig
    } else {
        $ConfigPath = $defaultExampleConfig
    }
}

if (-not $OwnerQueuePath) {
    $OwnerQueuePath = Join-Path $env:USERPROFILE ".codex\queues\owner-buttons.json"
}

function Convert-ToArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value) }
    return @($Value)
}

function Add-Reason {
    param(
        [System.Collections.Generic.List[object]] $List,
        [string] $Kind,
        [string] $Message
    )
    [void] $List.Add([pscustomobject]@{
        Kind = $Kind
        Message = $Message
    })
}

function Invoke-GitText {
    param(
        [string] $RepoPath,
        [string[]] $GitArgs
    )

    $output = & git -C $RepoPath @GitArgs 2>&1
    $text = (($output | Out-String).Trim())
    return [pscustomobject]@{
        Ok = ($LASTEXITCODE -eq 0)
        Text = $text
        ExitCode = $LASTEXITCODE
    }
}

function Quote-Argument {
    param([string] $Value)
    if ($null -eq $Value) { return '""' }
    $escaped = $Value.Replace('"', '\"')
    if ($escaped -match '\s|"' -or $escaped.Length -eq 0) {
        return '"' + $escaped + '"'
    }
    return $escaped
}

function Invoke-ConfiguredCommand {
    param(
        $CommandSpec,
        [string] $ProjectPath,
        [int] $DefaultTimeoutSeconds = 60
    )

    $commandName = if ($CommandSpec.name) { [string] $CommandSpec.name } else { [string] $CommandSpec.command }
    $commandPath = [string] $CommandSpec.command
    $args = @(Convert-ToArray $CommandSpec.args | ForEach-Object { [string] $_ })
    $timeoutSeconds = if ($CommandSpec.timeoutSeconds) { [int] $CommandSpec.timeoutSeconds } else { $DefaultTimeoutSeconds }

    if (-not [System.IO.Path]::IsPathRooted($commandPath)) {
        $candidate = Join-Path $ProjectPath $commandPath
        if (Test-Path -LiteralPath $candidate) {
            $commandPath = $candidate
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    if ($commandPath.ToLowerInvariant().EndsWith(".cmd") -or $commandPath.ToLowerInvariant().EndsWith(".bat")) {
        $psi.FileName = "cmd.exe"
        $allArgs = @("/c", $commandPath) + $args
        $psi.Arguments = (($allArgs | ForEach-Object { Quote-Argument $_ }) -join " ")
    } else {
        $psi.FileName = $commandPath
        $psi.Arguments = (($args | ForEach-Object { Quote-Argument $_ }) -join " ")
    }
    $psi.WorkingDirectory = $ProjectPath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    try {
        $process = [System.Diagnostics.Process]::Start($psi)
        $finished = $process.WaitForExit($timeoutSeconds * 1000)
        if (-not $finished) {
            try { $process.Kill() } catch {}
            return [pscustomobject]@{
                Name = $commandName
                Ok = $false
                ExitCode = -1
                Output = ""
                Error = "Timed out after $timeoutSeconds seconds."
            }
        }

        $stdout = $process.StandardOutput.ReadToEnd().Trim()
        $stderr = $process.StandardError.ReadToEnd().Trim()
        return [pscustomobject]@{
            Name = $commandName
            Ok = ($process.ExitCode -eq 0)
            ExitCode = $process.ExitCode
            Output = $stdout
            Error = $stderr
        }
    } catch {
        return [pscustomobject]@{
            Name = $commandName
            Ok = $false
            ExitCode = -1
            Output = ""
            Error = $_.Exception.Message
        }
    }
}

function Get-OwnerButtons {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Path = $Path
            Exists = $false
            Open = @()
        }
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $items = @()
        } else {
            $parsed = ConvertFrom-Json -InputObject $raw
            if ($null -eq $parsed) {
                $items = @()
            } elseif ($parsed -is [System.Array]) {
                $items = @($parsed)
            } elseif ($parsed.value -is [System.Array]) {
                $items = @($parsed.value)
            } else {
                $items = @($parsed)
            }
        }
        $open = @($items | Where-Object { $_.Status -eq "open" })
        return [pscustomobject]@{
            Path = $Path
            Exists = $true
            Open = $open
        }
    } catch {
        return [pscustomobject]@{
            Path = $Path
            Exists = $true
            Open = @()
            Error = $_.Exception.Message
        }
    }
}

function Test-Project {
    param(
        $Project,
        [switch] $RunCommands,
        [switch] $Fix
    )

    $warnings = New-Object System.Collections.Generic.List[object]
    $failures = New-Object System.Collections.Generic.List[object]
    $changes = New-Object System.Collections.Generic.List[object]
    $details = [ordered]@{}
    $projectPath = [string] $Project.path

    if (-not $projectPath) {
        Add-Reason $failures "missing-path-config" "No project path is configured."
        return [pscustomobject]@{
            Name = [string] $Project.name
            Path = ""
            Status = "not-running"
            Warnings = @($warnings.ToArray())
            Failures = @($failures.ToArray())
            Changes = @($changes.ToArray())
            Details = $details
        }
    }

    if (-not (Test-Path -LiteralPath $projectPath)) {
        Add-Reason $failures "missing-path" "Project path does not exist: $projectPath"
        return [pscustomobject]@{
            Name = [string] $Project.name
            Path = $projectPath
            Status = "not-running"
            Warnings = @($warnings.ToArray())
            Failures = @($failures.ToArray())
            Changes = @($changes.ToArray())
            Details = $details
        }
    }

    $insideGit = Invoke-GitText -RepoPath $projectPath -GitArgs @("rev-parse", "--is-inside-work-tree")
    if ($insideGit.Ok -and $insideGit.Text -eq "true") {
        $repoRoot = Invoke-GitText -RepoPath $projectPath -GitArgs @("rev-parse", "--show-toplevel")
        $branch = Invoke-GitText -RepoPath $projectPath -GitArgs @("branch", "--show-current")
        $remote = Invoke-GitText -RepoPath $projectPath -GitArgs @("remote", "get-url", "origin")
        $head = Invoke-GitText -RepoPath $projectPath -GitArgs @("log", "-1", "--oneline")
        $dirty = Invoke-GitText -RepoPath $projectPath -GitArgs @("status", "--short")

        $details.Git = [ordered]@{
            RepoRoot = $repoRoot.Text
            Branch = $branch.Text
            Remote = $remote.Text
            Head = $head.Text
            Dirty = @($dirty.Text -split "`r?`n" | Where-Object { $_ })
        }

        if ($Project.expectedBranch -and $branch.Text -ne [string] $Project.expectedBranch) {
            Add-Reason $failures "wrong-branch" "Expected branch '$($Project.expectedBranch)' but found '$($branch.Text)'."
        }

        if ($Project.expectedRemoteContains -and ($remote.Text -notlike ("*" + [string] $Project.expectedRemoteContains + "*"))) {
            Add-Reason $failures "wrong-remote" "Remote does not match expected text '$($Project.expectedRemoteContains)': $($remote.Text)"
        }

        if ($dirty.Text) {
            Add-Reason $warnings "dirty-worktree" "Repo has uncommitted files."
        }
    } else {
        Add-Reason $warnings "not-a-git-repo" "Project path is not inside a git repo."
    }

    foreach ($requiredPath in (Convert-ToArray $Project.requiredPaths)) {
        $fullPath = Join-Path $projectPath ([string] $requiredPath)
        if (-not (Test-Path -LiteralPath $fullPath)) {
            Add-Reason $failures "missing-required-path" "Missing required path: $requiredPath"
        }
    }

    foreach ($processName in (Convert-ToArray $Project.processNames)) {
        $normalizedName = [System.IO.Path]::GetFileNameWithoutExtension([string] $processName)
        $matches = @(Get-Process -Name $normalizedName -ErrorAction SilentlyContinue)
        if ($matches.Count -eq 0) {
            Add-Reason $failures "stopped-process" "Expected process is not running: $processName"
        } else {
            $details["Process:$processName"] = "$($matches.Count) running"
        }
    }

    foreach ($url in (Convert-ToArray $Project.healthUrls)) {
        try {
            $response = Invoke-WebRequest -Uri ([string] $url) -UseBasicParsing -TimeoutSec 8
            if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 400) {
                Add-Reason $failures "bad-health-url" "Health URL returned HTTP $($response.StatusCode): $url"
            } else {
                $details["Health:$url"] = "HTTP $($response.StatusCode)"
            }
        } catch {
            Add-Reason $failures "health-url-down" "Health URL failed: $url ($($_.Exception.Message))"
        }
    }

    $checkCommands = @(Convert-ToArray $Project.checkCommands)
    if ($checkCommands.Count -gt 0 -and -not $RunCommands) {
        Add-Reason $warnings "commands-skipped" "Configured check commands were not run. Rerun with -RunCommands."
    }

    if ($RunCommands) {
        foreach ($commandSpec in $checkCommands) {
            $commandResult = Invoke-ConfiguredCommand -CommandSpec $commandSpec -ProjectPath $projectPath
            $details["Check:$($commandResult.Name)"] = "exit $($commandResult.ExitCode)"
            if (-not $commandResult.Ok) {
                $message = "Check command failed: $($commandResult.Name)"
                if ($commandResult.Error) { $message = "$message - $($commandResult.Error)" }
                Add-Reason $failures "check-command-failed" $message
            }
        }
    }

    if ($Fix) {
        foreach ($commandSpec in (Convert-ToArray $Project.fixCommands)) {
            $fixResult = Invoke-ConfiguredCommand -CommandSpec $commandSpec -ProjectPath $projectPath -DefaultTimeoutSeconds 120
            [void] $changes.Add([pscustomobject]@{
                Name = $fixResult.Name
                Ok = $fixResult.Ok
                ExitCode = $fixResult.ExitCode
                Error = $fixResult.Error
            })
        }

        if (@(Convert-ToArray $Project.fixCommands).Count -eq 0) {
            Add-Reason $warnings "no-fix-commands" "-Fix was passed, but this project has no configured fix commands."
        }
    }

    $status = "running"
    if ($failures.Count -gt 0) {
        $status = "not-running"
    } elseif ($warnings.Count -gt 0) {
        $status = "needs-attention"
    }

    return [pscustomobject]@{
        Name = [string] $Project.name
        Path = $projectPath
        Status = $status
        Warnings = @($warnings.ToArray())
        Failures = @($failures.ToArray())
        Changes = @($changes.ToArray())
        Details = $details
    }
}

function Write-HumanReport {
    param($Report)

    Write-Host "AI Manager report"
    Write-Host "Config: $($Report.ConfigPath)"
    Write-Host "RunCommands: $($Report.RunCommands)"
    Write-Host "Fix: $($Report.Fix)"
    Write-Host ""
    Write-Host "Summary"
    Write-Host "  Running: $($Report.Summary.running)"
    Write-Host "  Needs attention: $($Report.Summary.'needs-attention')"
    Write-Host "  Not running: $($Report.Summary.'not-running')"
    Write-Host "  Owner buttons open: $($Report.OwnerButtons.OpenCount)"

    foreach ($project in $Report.Projects) {
        Write-Host ""
        Write-Host "$($project.Name): $($project.Status)"
        Write-Host "  Path: $($project.Path)"

        foreach ($failure in $project.Failures) {
            Write-Host "  Why not running: [$($failure.Kind)] $($failure.Message)"
        }

        foreach ($warning in $project.Warnings) {
            Write-Host "  Attention: [$($warning.Kind)] $($warning.Message)"
        }

        foreach ($change in $project.Changes) {
            $changeStatus = if ($change.Ok) { "ok" } else { "failed" }
            Write-Host "  Change: $($change.Name) -> $changeStatus (exit $($change.ExitCode))"
            if ($change.Error) { Write-Host "    $($change.Error)" }
        }

        if ($project.Failures.Count -eq 0 -and $project.Warnings.Count -eq 0) {
            Write-Host "  Everything expected is running."
        }
    }

    if ($Report.OwnerButtons.OpenCount -gt 0) {
        Write-Host ""
        Write-Host "Owner buttons"
        foreach ($item in ($Report.OwnerButtons.Open | Select-Object -First 10)) {
            Write-Host "  $($item.Project): $($item.Needed)"
        }
        if ($Report.OwnerButtons.OpenCount -gt 10) {
            Write-Host "  ...and $($Report.OwnerButtons.OpenCount - 10) more."
        }
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Error "Config file not found: $ConfigPath"
    exit 2
}

try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "Could not parse config: $ConfigPath ($($_.Exception.Message))"
    exit 2
}

$ownerButtons = Get-OwnerButtons -Path $OwnerQueuePath
$projects = New-Object System.Collections.Generic.List[object]

foreach ($project in (Convert-ToArray $config.projects)) {
    if ($project.enabled -eq $false) { continue }
    [void] $projects.Add((Test-Project -Project $project -RunCommands:$RunCommands -Fix:$Fix))
}

$running = @($projects | Where-Object { $_.Status -eq "running" }).Count
$attention = @($projects | Where-Object { $_.Status -eq "needs-attention" }).Count
$notRunning = @($projects | Where-Object { $_.Status -eq "not-running" }).Count

$report = [pscustomobject]@{
    GeneratedAt = (Get-Date).ToString("s")
    ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
    RunCommands = [bool] $RunCommands
    Fix = [bool] $Fix
    Summary = [ordered]@{
        running = $running
        "needs-attention" = $attention
        "not-running" = $notRunning
    }
    OwnerButtons = [pscustomobject]@{
        Path = $ownerButtons.Path
        Exists = $ownerButtons.Exists
        OpenCount = @($ownerButtons.Open).Count
        Open = @($ownerButtons.Open)
        Error = $ownerButtons.Error
    }
    Projects = @($projects.ToArray())
}

if ($Json) {
    $report | ConvertTo-Json -Depth 12
} else {
    Write-HumanReport -Report $report
}

if ($notRunning -gt 0) { exit 2 }
if ($attention -gt 0 -or $report.OwnerButtons.OpenCount -gt 0) { exit 1 }
exit 0
