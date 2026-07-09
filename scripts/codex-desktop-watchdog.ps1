param(
    [string]$LogPath = "C:\Users\zev\Documents\Codex\codex-desktop-watchdog\watchdog.log",
    [string]$StatePath = "C:\Users\zev\.codex\state\codex-desktop-watchdog-state.json",
    [string]$EventLogPath = "C:\Users\zev\.codex\logs\crash-recovery\events.jsonl"
)

$ErrorActionPreference = "Stop"

$CodexHome = "C:\Users\zev\.codex"
$DesktopAppId = "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
$ShellStewardScript = Join-Path $CodexHome "scripts\codex-shell-steward.ps1"
$ActiveWorkRegistryScript = Join-Path $CodexHome "scripts\codex-active-work-registry.ps1"
$RunHiddenVbs = Join-Path $CodexHome "scripts\run-hidden-powershell.vbs"
$BossmanTaskName = "Bossman2RuntimeUser"
$BossmanHeartbeatPath = "C:\repos\bossman2-architecture-review-yhl582\data\command-center\heartbeat.json"
$ActiveWorkRegistryPath = Join-Path $CodexHome "state\active-work-registry.json"
$LegacyCommandCenterRoot = "C:\Users\zev\OneDrive\Documents\New project 2\data\command-center"
$LegacyLaneLeasesPath = Join-Path $LegacyCommandCenterRoot "lane-leases.json"
$LegacyCommandInboxPath = Join-Path $LegacyCommandCenterRoot "command-inbox.json"

function Ensure-ParentDir {
    param([string]$Path)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Write-Utf8NoBomFile {
    param(
        [string]$Path,
        [string]$Text
    )
    Ensure-ParentDir -Path $Path
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Add-Utf8NoBomLine {
    param(
        [string]$Path,
        [string]$Text
    )
    Ensure-ParentDir -Path $Path
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $stream = [System.IO.StreamWriter]::new($Path, $true, $encoding)
    try {
        $stream.WriteLine($Text)
    } finally {
        $stream.Dispose()
    }
}

function Write-WatchdogLog {
    param([string]$Message)
    Ensure-ParentDir -Path $LogPath
    if ((Test-Path -LiteralPath $LogPath) -and ((Get-Item -LiteralPath $LogPath).Length -gt 5MB)) {
        $archive = "{0}.{1}.old" -f $LogPath, (Get-Date -Format "yyyyMMddHHmmss")
        Move-Item -LiteralPath $LogPath -Destination $archive -Force
    }
    $line = "{0} {1}" -f (Get-Date).ToString("o"), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Write-RecoveryEvent {
    param(
        [string]$Type,
        [hashtable]$Detail
    )
    $payload = [ordered]@{
        at = (Get-Date).ToString("o")
        type = $Type
        detail = $Detail
    }
    Add-Utf8NoBomLine -Path $EventLogPath -Text (($payload | ConvertTo-Json -Depth 8 -Compress))
}

function Read-State {
    if (-not (Test-Path -LiteralPath $StatePath)) {
        return $null
    }
    try {
        return Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Read-OptionalJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    try {
        return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Write-State {
    param([hashtable]$State)
    Write-Utf8NoBomFile -Path $StatePath -Text (($State | ConvertTo-Json -Depth 8))
}

function Get-MainCodexProcess {
    $processes = Get-CimInstance Win32_Process -Filter "name = 'Codex.exe'" -ErrorAction SilentlyContinue
    $main = @($processes | Where-Object {
        $_.CommandLine -match "\\app\\Codex\.exe" -and
        $_.CommandLine -notmatch "--type=" -and
        $_.CommandLine -notmatch "crashpad-handler"
    })
    if ($main.Count -gt 0) {
        return $main
    }
    return @()
}

function Get-CodexMemoryMb {
    $sum = 0.0
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try {
            ($_.ProcessName -in @("Codex", "codex")) -and ($_.Path -match "\\WindowsApps\\OpenAI\.Codex_.*\\app\\")
        } catch {
            $false
        }
    } | ForEach-Object {
        $sum += ($_.WorkingSet64 / 1MB)
    }
    return [math]::Round($sum, 1)
}

function Get-FreeDiskGb {
    try {
        return [math]::Round(((Get-Volume -DriveLetter C).SizeRemaining / 1GB), 2)
    } catch {
        return $null
    }
}

function Get-FreePhysicalGb {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        return [math]::Round(($os.FreePhysicalMemory / 1MB), 2)
    } catch {
        return $null
    }
}

function Get-LargestRecentSessionMb {
    $sessionRoot = Join-Path $CodexHome "sessions"
    if (-not (Test-Path -LiteralPath $sessionRoot)) {
        return 0
    }
    $cutoff = (Get-Date).AddHours(-8)
    $largest = Get-ChildItem -LiteralPath $sessionRoot -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $cutoff } |
        Sort-Object Length -Descending |
        Select-Object -First 1
    if (-not $largest) {
        return 0
    }
    return [math]::Round(($largest.Length / 1MB), 1)
}

function Get-FileAgeHours {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    try {
        return [math]::Round(((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalHours, 2)
    } catch {
        return $null
    }
}

function Start-CodexDesktop {
    Write-WatchdogLog "RESTART no_main_codex_process launching_app"
    Start-Process -FilePath "explorer.exe" -ArgumentList $DesktopAppId
}

function Test-ShellStewardRunning {
    $matches = Get-CimInstance Win32_Process -Filter "name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "codex-shell-steward\.ps1" -and $_.CommandLine -match "watch" }
    return (@($matches).Count -gt 0)
}

function Ensure-ShellSteward {
    if (-not (Test-Path -LiteralPath $ShellStewardScript)) {
        return "missing"
    }
    if (Test-ShellStewardRunning) {
        return "running"
    }
    if (Test-Path -LiteralPath $RunHiddenVbs) {
        Start-Process -FilePath "wscript.exe" -ArgumentList @("//B", "//Nologo", $RunHiddenVbs, $ShellStewardScript, "-Mode", "watch", "-PollSeconds", "5") -WindowStyle Hidden
    } else {
        Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", $ShellStewardScript, "-Mode", "watch", "-PollSeconds", "5") -WindowStyle Hidden
    }
    Start-Sleep -Seconds 1
    if (Test-ShellStewardRunning) {
        return "started"
    }
    return "start_requested"
}

function Get-BossmanHeartbeatAgeSeconds {
    if (-not (Test-Path -LiteralPath $BossmanHeartbeatPath)) {
        return $null
    }
    try {
        $heartbeat = Get-Content -Raw -LiteralPath $BossmanHeartbeatPath | ConvertFrom-Json
        if (-not $heartbeat.at) {
            return $null
        }
        $heartbeatAt = [datetime]::Parse($heartbeat.at).ToUniversalTime()
        return [math]::Round((([datetime]::UtcNow) - $heartbeatAt).TotalSeconds, 1)
    } catch {
        return $null
    }
}

function Ensure-BossmanRuntime {
    param([bool]$CrashDetected)
    $task = Get-ScheduledTask -TaskName $BossmanTaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        return "missing"
    }
    $age = Get-BossmanHeartbeatAgeSeconds
    $stale = ($null -eq $age) -or ($age -gt 900)
    if ($CrashDetected -or $stale) {
        try {
            Start-ScheduledTask -TaskName $BossmanTaskName
            return "start_requested heartbeat_age_s=$age"
        } catch {
            return "start_failed $($_.Exception.Message)"
        }
    }
    return "healthy heartbeat_age_s=$age"
}

function Update-ActiveWorkRegistry {
    if (-not (Test-Path -LiteralPath $ActiveWorkRegistryScript)) {
        return "missing"
    }
    try {
        & $ActiveWorkRegistryScript -OutputPath $ActiveWorkRegistryPath -Quiet
        return "refreshed"
    } catch {
        return "error $($_.Exception.Message)"
    }
}

try {
    $previous = Read-State
    $mainCodex = @(Get-MainCodexProcess)
    $mainIds = @($mainCodex | Select-Object -ExpandProperty ProcessId)
    $codexRunning = ($mainIds.Count -gt 0)
    $crashDetected = $false

    if ($previous -and $previous.codex_running -eq $true -and -not $codexRunning) {
        $crashDetected = $true
        Write-RecoveryEvent -Type "codex_crash_detected" -Detail @{
            previous_process_ids = @($previous.main_process_ids)
            previous_at = [string]$previous.at
        }
        Write-WatchdogLog "CRASH_DETECTED previous_process_ids=$($previous.main_process_ids -join ',')"
    }

    if (-not $codexRunning) {
        Start-CodexDesktop
        Start-Sleep -Seconds 8
        $mainCodex = @(Get-MainCodexProcess)
        $mainIds = @($mainCodex | Select-Object -ExpandProperty ProcessId)
        $codexRunning = ($mainIds.Count -gt 0)
    }

    $shellStewardStatus = Ensure-ShellSteward
    $bossmanStatus = Ensure-BossmanRuntime -CrashDetected:$crashDetected
    $codexMemoryMb = Get-CodexMemoryMb
    $freeDiskGb = Get-FreeDiskGb
    $freePhysicalGb = Get-FreePhysicalGb
    $largestRecentSessionMb = Get-LargestRecentSessionMb
    $activeWorkRefreshStatus = Update-ActiveWorkRegistry
    $activeWorkRegistry = Read-OptionalJson -Path $ActiveWorkRegistryPath

    $warnings = @()
    if ($freeDiskGb -ne $null -and $freeDiskGb -lt 25) {
        $warnings += "low_disk_free_gb=$freeDiskGb"
    }
    if ($freePhysicalGb -ne $null -and $freePhysicalGb -lt 2) {
        $warnings += "low_physical_memory_gb=$freePhysicalGb"
    }
    if ($codexMemoryMb -gt 4500) {
        $warnings += "codex_memory_high_mb=$codexMemoryMb"
    }
    if ($largestRecentSessionMb -gt 900) {
        $warnings += "recent_session_large_mb=$largestRecentSessionMb"
    }
    $activeWorkAgeHours = Get-FileAgeHours -Path $ActiveWorkRegistryPath
    if ($null -eq $activeWorkAgeHours) {
        $warnings += "active_work_registry_missing"
    } elseif ($activeWorkAgeHours -gt 2) {
        $warnings += "active_work_registry_stale_h=$activeWorkAgeHours"
    }
    if ($activeWorkRefreshStatus -notin @("refreshed")) {
        $warnings += "active_work_registry_refresh=$activeWorkRefreshStatus"
    }
    if ($null -ne $activeWorkRegistry -and [string]$activeWorkRegistry.status -ne "healthy") {
        $warnings += "active_work_registry_status=$($activeWorkRegistry.status)"
    }
    $laneLeaseAgeHours = Get-FileAgeHours -Path $LegacyLaneLeasesPath
    if ($null -ne $laneLeaseAgeHours -and $laneLeaseAgeHours -gt 24) {
        $warnings += "lane_leases_stale_h=$laneLeaseAgeHours"
    }
    $commandInboxAgeHours = Get-FileAgeHours -Path $LegacyCommandInboxPath
    if ($null -ne $commandInboxAgeHours -and $commandInboxAgeHours -gt 24) {
        $warnings += "command_inbox_stale_h=$commandInboxAgeHours"
    }

    if ($crashDetected) {
        Write-RecoveryEvent -Type "codex_post_crash_recovery" -Detail @{
            codex_running = $codexRunning
            main_process_ids = $mainIds
            shell_steward = $shellStewardStatus
            bossman_runtime = $bossmanStatus
            free_disk_gb = $freeDiskGb
            free_physical_gb = $freePhysicalGb
            codex_memory_mb = $codexMemoryMb
            warnings = $warnings
        }
    }

    $status = if ($codexRunning) { "healthy" } else { "codex_missing" }
    $state = @{
        at = (Get-Date).ToString("o")
        status = $status
        codex_running = $codexRunning
        main_process_ids = $mainIds
        shell_steward = $shellStewardStatus
        bossman_runtime = $bossmanStatus
        free_disk_gb = $freeDiskGb
        free_physical_gb = $freePhysicalGb
        codex_memory_mb = $codexMemoryMb
        largest_recent_session_mb = $largestRecentSessionMb
        active_work_registry_path = $ActiveWorkRegistryPath
        active_work_registry_age_h = $activeWorkAgeHours
        active_work_registry_refresh = $activeWorkRefreshStatus
        active_work_status = if ($null -ne $activeWorkRegistry) { [string]$activeWorkRegistry.status } else { $null }
        active_work_count = if ($null -ne $activeWorkRegistry) { [int]$activeWorkRegistry.active_count } else { $null }
        lane_leases_age_h = $laneLeaseAgeHours
        command_inbox_age_h = $commandInboxAgeHours
        warnings = $warnings
        log_path = $LogPath
        event_log_path = $EventLogPath
    }
    Write-State -State $state

    $warningText = if ($warnings.Count -gt 0) { " warnings=$($warnings -join ';')" } else { "" }
    if ($codexRunning) {
        Write-WatchdogLog "OK main_codex_running process_ids=$($mainIds -join ',') shell_steward=$shellStewardStatus bossman=$bossmanStatus disk_free_gb=$freeDiskGb memory_free_gb=$freePhysicalGb codex_memory_mb=$codexMemoryMb$warningText"
    } else {
        Write-WatchdogLog "ERROR codex_not_running_after_restart shell_steward=$shellStewardStatus bossman=$bossmanStatus$warningText"
        exit 1
    }
}
catch {
    Write-WatchdogLog "ERROR $($_.Exception.Message)"
    Write-RecoveryEvent -Type "watchdog_error" -Detail @{ message = $_.Exception.Message }
    exit 1
}
