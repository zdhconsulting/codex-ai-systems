[CmdletBinding(DefaultParameterSetName = "Create")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Create")]
    [string] $Project,
    [Parameter(ParameterSetName = "Create")]
    [string] $Task,
    [Parameter(ParameterSetName = "Create")]
    [string] $TaskFile = "",
    [Parameter(ParameterSetName = "Create")]
    [string[]] $InputFile = @(),
    [Parameter(ParameterSetName = "Create")]
    [string] $InputListFile = "",
    [Parameter(ParameterSetName = "Create")]
    [string] $WorkspaceRoot = (Get-Location).Path,
    [Parameter(ParameterSetName = "Create")]
    [string[]] $AllowedRoot = @(),
    [Parameter(ParameterSetName = "Create")]
    [string] $Model = "fable",
    [Parameter(ParameterSetName = "Create")]
    [double] $MaxBudgetUsd = 0,
    [Parameter(ParameterSetName = "Create")]
    [int] $MaxRounds = 2,
    [Parameter(ParameterSetName = "Create")]
    [int] $RoundNumber = 1,
    [Parameter(ParameterSetName = "Create")]
    [string] $RunId = "",
    [Parameter(ParameterSetName = "Create")]
    [string] $TaskId = "",
    [Parameter(ParameterSetName = "Create")]
    [string] $CorrelationId = "",
    [Parameter(ParameterSetName = "Create")]
    [string] $AttemptId = "",
    [Parameter(ParameterSetName = "Create")]
    [string[]] $DoneCriteria = @(),
    [Parameter(ParameterSetName = "Create")]
    [string[]] $NoTouchRule = @(),
    [Parameter(ParameterSetName = "Create")]
    [int] $TimeoutSeconds = 300,
    [Parameter(ParameterSetName = "Create")]
    [string] $ClaudePath = "C:\Users\zev\.local\bin\claude.exe",
    [Parameter(ParameterSetName = "Create")]
    [string[]] $ClaudePrefixArgument = @(),
    [Parameter(ParameterSetName = "Create")]
    [Alias("DryRun")]
    [switch] $PlanOnly,
    [Parameter(Mandatory = $true, ParameterSetName = "Import")]
    [string] $ExchangePath,
    [Parameter(Mandatory = $true, ParameterSetName = "Import")]
    [string] $ImportResponseFile,
    [string] $HandoffRoot = "",
    [switch] $Json
)

$ErrorActionPreference = "Stop"
$script:CodexHome = Split-Path -Parent $PSScriptRoot
$script:SkillRoot = Join-Path $script:CodexHome "skills\codex-claude-bridge"
$script:ReceiptSchemaPath = Join-Path $script:SkillRoot "references\receipt.schema.json"
$script:TaskSchemaPath = Join-Path $script:SkillRoot "references\task.schema.json"
$script:HandoffRoot = if ($HandoffRoot) { [System.IO.Path]::GetFullPath($HandoffRoot) } else { Join-Path $script:CodexHome "handoffs\claude" }
$script:RequiredReceiptFields = @(
    "schema_version", "run_id", "task_id", "correlation_id", "attempt_id", "status",
    "summary", "decisions", "deliverable", "evidence", "files_needed", "files_touched",
    "blockers", "owner_button_needed", "commander_approval_needed", "codex_next_action",
    "confidence", "go_back_to_codex", "completed_at"
)

function Get-UtcStamp {
    return [DateTime]::UtcNow.ToString("o")
}

function ConvertTo-SafeSlug {
    param([string] $Value, [string] $Fallback = "item")
    $slug = ($Value -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return $Fallback }
    if ($slug.Length -gt 48) { return $slug.Substring(0, 48).TrimEnd('-') }
    return $slug
}

function Write-Utf8NoBom {
    param([string] $Path, [string] $Content)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-Utf8Text {
    param([string] $Path)
    return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-JsonAtomic {
    param([string] $Path, [object] $Value)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = Join-Path $parent ("." + [Guid]::NewGuid().ToString("N") + ".tmp")
    $content = ($Value | ConvertTo-Json -Depth 30) + [Environment]::NewLine
    Write-Utf8NoBom -Path $temporary -Content $content
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Add-BridgeEvent {
    param([string] $Directory, [string] $Type, [object] $Data = $null)
    $event = [ordered]@{ schema_version = "1.0"; at = Get-UtcStamp; type = $Type; data = $Data }
    $line = ($event | ConvertTo-Json -Depth 20 -Compress) + [Environment]::NewLine
    $path = Join-Path $Directory "events.jsonl"
    [System.IO.File]::AppendAllText($path, $line, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-BridgeStatus {
    param(
        [string] $Directory,
        [object] $TaskPacket,
        [string] $State,
        [string] $Code,
        [string] $Message,
        [string] $ReceiptPath = ""
    )
    $status = [ordered]@{
        schema_version = "1.0"
        run_id = $TaskPacket.run_id
        task_id = $TaskPacket.task_id
        correlation_id = $TaskPacket.correlation_id
        attempt_id = $TaskPacket.attempt_id
        state = $State
        code = $Code
        message = $Message
        receipt_path = $ReceiptPath
        updated_at = Get-UtcStamp
    }
    Write-JsonAtomic -Path (Join-Path $Directory "status.json") -Value $status
    return [pscustomobject]$status
}

function Resolve-DirectoryPath {
    param([string] $Path, [string] $Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label does not exist or is not a directory: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Test-PathInsideRoot {
    param([string] $Path, [string] $Root)
    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    if ($fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $fullPath.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-ApprovedInputs {
    param([string[]] $Paths, [string] $Workspace, [string[]] $Roots)
    $resolved = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($item in $Paths) {
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        $candidate = if ([System.IO.Path]::IsPathRooted($item)) { $item } else { Join-Path $Workspace $item }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Input file does not exist: $candidate"
        }
        $full = (Resolve-Path -LiteralPath $candidate).Path
        $approved = $false
        foreach ($root in $Roots) {
            if (Test-PathInsideRoot -Path $full -Root $root) { $approved = $true; break }
        }
        if (-not $approved) {
            throw "Input file is outside allowed roots: $full"
        }
        if (-not $seen.ContainsKey($full.ToLowerInvariant())) {
            $seen[$full.ToLowerInvariant()] = $true
            $file = Get-Item -LiteralPath $full
            $resolved.Add([pscustomobject]@{
                path = $full
                sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
                size_bytes = [int64]$file.Length
            })
        }
    }
    return [object[]]$resolved
}

function New-ExchangeDirectory {
    param([string] $Root, [string] $ProjectName, [string] $Correlation, [string] $Attempt)
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $base = "{0}-{1}-{2}-{3}" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"), (ConvertTo-SafeSlug $ProjectName "project"), (ConvertTo-SafeSlug $Correlation "correlation"), (ConvertTo-SafeSlug $Attempt "attempt")
    for ($index = 0; $index -lt 100; $index++) {
        $name = if ($index -eq 0) { $base } else { "$base-$index" }
        $path = Join-Path $Root $name
        try {
            New-Item -ItemType Directory -Path $path -ErrorAction Stop | Out-Null
            return $path
        } catch [System.IO.IOException] {
            continue
        }
    }
    throw "Could not allocate a unique Claude exchange directory."
}

function Add-ConstProperty {
    param([object] $Object, [string] $Name, [object] $Value)
    $target = $Object.properties.$Name
    if ($target.PSObject.Properties.Name -contains "const") {
        $target.const = $Value
    } else {
        $target | Add-Member -NotePropertyName "const" -NotePropertyValue $Value
    }
}

function New-RuntimeReceiptSchema {
    param([object] $TaskPacket)
    $schema = Read-Utf8Text -Path $script:ReceiptSchemaPath | ConvertFrom-Json
    Add-ConstProperty -Object $schema -Name "run_id" -Value $TaskPacket.run_id
    Add-ConstProperty -Object $schema -Name "task_id" -Value $TaskPacket.task_id
    Add-ConstProperty -Object $schema -Name "correlation_id" -Value $TaskPacket.correlation_id
    Add-ConstProperty -Object $schema -Name "attempt_id" -Value $TaskPacket.attempt_id
    return $schema
}

function ConvertTo-WindowsArgument {
    param([string] $Value)
    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($slashes * 2) + 1)))
            [void]$builder.Append('"')
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)); $slashes = 0 }
        [void]$builder.Append($character)
    }
    if ($slashes -gt 0) { [void]$builder.Append(('\' * ($slashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-HiddenProcess {
    param(
        [string] $Executable,
        [string[]] $Arguments,
        [string] $WorkingDirectory,
        [string] $StandardInput,
        [int] $Timeout
    )
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = (($Arguments | ForEach-Object { ConvertTo-WindowsArgument "$_" }) -join " ")
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    if (-not $process.Start()) { throw "Provider process did not start." }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timeoutMilliseconds = [int][Math]::Min([int]::MaxValue, ([int64]$Timeout * 1000))
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $inputTask = $process.StandardInput.WriteAsync($StandardInput)
    while (-not $inputTask.IsCompleted -and $timer.ElapsedMilliseconds -lt $timeoutMilliseconds -and -not $process.HasExited) {
        Start-Sleep -Milliseconds 10
    }
    $inputTimedOut = -not $inputTask.IsCompleted -and -not $process.HasExited
    if (-not $inputTimedOut) {
        try { $inputTask.Wait() } catch { }
        try { $process.StandardInput.Close() } catch { }
    }
    $remaining = [Math]::Max(0, $timeoutMilliseconds - [int]$timer.ElapsedMilliseconds)
    $completed = if ($inputTimedOut) { $false } elseif ($process.HasExited) { $true } else { $process.WaitForExit($remaining) }
    if (-not $completed) {
        try { $process.Kill() } catch { }
        try { $process.WaitForExit() } catch { }
        try { $process.StandardInput.Close() } catch { }
    } else {
        $process.WaitForExit()
    }
    $timer.Stop()
    return [pscustomobject]@{
        exit_code = if ($completed) { [int]$process.ExitCode } else { $null }
        timed_out = -not $completed
        stdout = $stdoutTask.Result
        stderr = $stderrTask.Result
    }
}

function Get-ProviderReceiptCandidate {
    param([string] $Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { throw "empty_response|Provider returned no JSON." }
    try {
        $envelope = $Text.Trim() | ConvertFrom-Json
    } catch {
        throw "malformed_json|Provider response is not valid JSON."
    }
    if ($envelope.PSObject.Properties.Name -contains "structured_output" -and $null -ne $envelope.structured_output) {
        return [pscustomobject]@{ envelope = $envelope; receipt = $envelope.structured_output }
    }
    if ($envelope.PSObject.Properties.Name -contains "schema_version") {
        return [pscustomobject]@{ envelope = $envelope; receipt = $envelope }
    }
    if ($envelope.PSObject.Properties.Name -contains "result") {
        if ($envelope.result -is [string]) {
            try { $candidate = $envelope.result | ConvertFrom-Json } catch { throw "malformed_result_json|Provider result field is not valid JSON." }
            return [pscustomobject]@{ envelope = $envelope; receipt = $candidate }
        }
        if ($null -ne $envelope.result) {
            return [pscustomobject]@{ envelope = $envelope; receipt = $envelope.result }
        }
    }
    throw "missing_structured_output|Provider JSON did not contain structured output."
}

function Test-StringArray {
    param([object] $Value)
    if ($null -eq $Value -or $Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) { return $false }
    foreach ($item in @($Value)) { if ($item -isnot [string]) { return $false } }
    return $true
}

function Assert-ReceiptValid {
    param([object] $Receipt, [object] $TaskPacket)
    $names = @($Receipt.PSObject.Properties.Name)
    foreach ($field in $script:RequiredReceiptFields) {
        if ($names -notcontains $field) { throw "missing_field|Receipt is missing required field: $field" }
    }
    $extra = @($names | Where-Object { $script:RequiredReceiptFields -notcontains $_ })
    if ($extra.Count -gt 0) { throw "unexpected_field|Receipt contains unsupported fields: $($extra -join ', ')" }
    if ($Receipt.schema_version -ne "1.0") { throw "schema_version_mismatch|Receipt schema version is not 1.0." }
    foreach ($idField in @("run_id", "task_id", "correlation_id", "attempt_id")) {
        if ($Receipt.$idField -ne $TaskPacket.$idField) { throw "${idField}_mismatch|Receipt $idField does not match the current attempt." }
    }
    if (@("succeeded", "blocked", "failed") -notcontains $Receipt.status) { throw "invalid_status|Receipt status is invalid." }
    foreach ($field in @("summary", "deliverable", "codex_next_action", "completed_at")) {
        if ($Receipt.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($Receipt.$field)) { throw "invalid_field|Receipt field '$field' must be a non-empty string." }
    }
    foreach ($field in @("decisions", "files_needed", "files_touched", "blockers")) {
        if (-not (Test-StringArray $Receipt.$field)) { throw "invalid_field|Receipt field '$field' must be a string array." }
    }
    if ($Receipt.owner_button_needed -isnot [bool] -or $Receipt.commander_approval_needed -isnot [bool] -or $Receipt.go_back_to_codex -isnot [bool]) {
        throw "invalid_boolean|Receipt approval and return flags must be booleans."
    }
    if ($Receipt.confidence -isnot [ValueType] -or [double]$Receipt.confidence -lt 0 -or [double]$Receipt.confidence -gt 100) {
        throw "invalid_confidence|Receipt confidence must be between 0 and 100."
    }
    try { [void][DateTimeOffset]::Parse($Receipt.completed_at) } catch { throw "invalid_completed_at|Receipt completed_at is not a valid timestamp." }
    if (@($Receipt.files_touched).Count -gt 0) { throw "authority_violation|Read-only v1 receipts cannot report touched files." }
    $claimText = "$($Receipt.summary)`n$($Receipt.deliverable)"
    if ($claimText -match '(?i)\b(I|we)\s+(edited|modified|created|deleted|wrote|committed|pushed)\b') {
        throw "authority_violation|Receipt claims file or Git changes under read-only authority."
    }
    if ($null -eq $Receipt.evidence -or $Receipt.evidence -is [string] -or $Receipt.evidence -isnot [System.Collections.IEnumerable]) {
        throw "invalid_evidence|Receipt evidence must be an array."
    }
    foreach ($item in @($Receipt.evidence)) {
        $itemNames = @($item.PSObject.Properties.Name)
        if ($itemNames -notcontains "claim" -or $itemNames -notcontains "ref" -or
            $item.claim -isnot [string] -or [string]::IsNullOrWhiteSpace($item.claim) -or
            $item.ref -isnot [string] -or [string]::IsNullOrWhiteSpace($item.ref)) {
            throw "invalid_evidence|Every evidence item needs non-empty claim and ref strings."
        }
    }
    if ($Receipt.status -eq "succeeded" -and @($Receipt.evidence).Count -eq 0) {
        throw "missing_evidence|Succeeded receipts require evidence."
    }
    if ($Receipt.status -ne "succeeded" -and @($Receipt.blockers).Count -eq 0) {
        throw "missing_blocker|Blocked or failed receipts require a blocker."
    }
}

function Get-BridgeErrorParts {
    param([System.Management.Automation.ErrorRecord] $Record)
    $message = $Record.Exception.Message
    $separator = $message.IndexOf('|')
    if ($separator -gt 0) {
        return [pscustomobject]@{ code = $message.Substring(0, $separator); message = $message.Substring($separator + 1) }
    }
    return [pscustomobject]@{ code = "receipt_validation_failed"; message = $message }
}

function Save-RawResponse {
    param([string] $Directory, [object] $ProcessResult, [object] $Envelope = $null, [string] $Source = "provider")
    $raw = [ordered]@{
        schema_version = "1.0"
        captured_at = Get-UtcStamp
        source = $Source
        exit_code = $ProcessResult.exit_code
        timed_out = [bool]$ProcessResult.timed_out
        stdout = $ProcessResult.stdout
        stderr = $ProcessResult.stderr
        parsed_envelope = $Envelope
    }
    Write-JsonAtomic -Path (Join-Path $Directory "raw-response.json") -Value $raw
}

function Import-ReceiptText {
    param([string] $Directory, [object] $TaskPacket, [string] $ResponseText, [object] $ProcessResult, [string] $Source)
    $receiptPath = Join-Path $Directory "receipt.json"
    if (Test-Path -LiteralPath $receiptPath) {
        Add-BridgeEvent -Directory $Directory -Type "duplicate_terminal_receipt_rejected" -Data @{ receipt_path = $receiptPath }
        throw "duplicate_terminal_receipt|A terminal receipt already exists; it was not overwritten."
    }
    try {
        $candidate = Get-ProviderReceiptCandidate -Text $ResponseText
        Save-RawResponse -Directory $Directory -ProcessResult $ProcessResult -Envelope $candidate.envelope -Source $Source
        Assert-ReceiptValid -Receipt $candidate.receipt -TaskPacket $TaskPacket
        Write-JsonAtomic -Path $receiptPath -Value $candidate.receipt
        $status = Write-BridgeStatus -Directory $Directory -TaskPacket $TaskPacket -State "succeeded" -Code "receipt_accepted" -Message "Schema-valid read-only Claude receipt accepted." -ReceiptPath $receiptPath
        Add-BridgeEvent -Directory $Directory -Type "receipt_accepted" -Data @{ receipt_path = $receiptPath; status = $candidate.receipt.status }
        return [pscustomobject]@{ status = $status; receipt = $candidate.receipt; receipt_path = $receiptPath }
    } catch {
        $parts = Get-BridgeErrorParts $_
        if (-not (Test-Path -LiteralPath (Join-Path $Directory "raw-response.json"))) {
            Save-RawResponse -Directory $Directory -ProcessResult $ProcessResult -Source $Source
        }
        $status = Write-BridgeStatus -Directory $Directory -TaskPacket $TaskPacket -State "quarantined" -Code $parts.code -Message $parts.message
        Add-BridgeEvent -Directory $Directory -Type "response_quarantined" -Data @{ code = $parts.code; message = $parts.message }
        throw "$($parts.code)|$($parts.message)"
    }
}

function Write-Result {
    param([string] $Directory, [object] $Status, [object] $Receipt = $null, [switch] $AsJson)
    $result = [pscustomobject]@{ exchange_path = $Directory; status = $Status; receipt = $Receipt }
    if ($AsJson) {
        $result | ConvertTo-Json -Depth 30
    } else {
        Write-Host "CLAUDE_BRIDGE status=$($Status.state) code=$($Status.code)"
        Write-Host "Exchange: $Directory"
        if ($Receipt) {
            Write-Host "Receipt: $(Join-Path $Directory 'receipt.json')"
            $Receipt | ConvertTo-Json -Depth 30
        }
    }
}

if (-not (Test-Path -LiteralPath $script:TaskSchemaPath -PathType Leaf) -or -not (Test-Path -LiteralPath $script:ReceiptSchemaPath -PathType Leaf)) {
    [Console]::Error.WriteLine("Claude bridge schemas are missing from $script:SkillRoot")
    exit 2
}

if ($PSCmdlet.ParameterSetName -eq "Import") {
    try {
        $root = Resolve-DirectoryPath -Path $script:HandoffRoot -Label "Handoff root"
        $directory = Resolve-DirectoryPath -Path $ExchangePath -Label "Exchange path"
        if (-not (Test-PathInsideRoot -Path $directory -Root $root)) { throw "Exchange path is outside the Claude handoff root: $directory" }
        if (-not (Test-Path -LiteralPath $ImportResponseFile -PathType Leaf)) { throw "Import response file does not exist: $ImportResponseFile" }
        $taskPacket = Read-Utf8Text -Path (Join-Path $directory "task.json") | ConvertFrom-Json
        if (Test-Path -LiteralPath (Join-Path $directory "receipt.json")) {
            Add-BridgeEvent -Directory $directory -Type "duplicate_terminal_receipt_rejected" -Data @{ source = $ImportResponseFile }
            $existing = Read-Utf8Text -Path (Join-Path $directory "status.json") | ConvertFrom-Json
            Write-Result -Directory $directory -Status $existing -AsJson:$Json
            exit 2
        }
        $text = Read-Utf8Text -Path $ImportResponseFile
        $processResult = [pscustomobject]@{ exit_code = 0; timed_out = $false; stdout = $text; stderr = "" }
        $imported = Import-ReceiptText -Directory $directory -TaskPacket $taskPacket -ResponseText $text -ProcessResult $processResult -Source "import_file"
        Write-Result -Directory $directory -Status $imported.status -Receipt $imported.receipt -AsJson:$Json
        exit 0
    } catch {
        if ($directory -and $taskPacket) {
            $parts = Get-BridgeErrorParts $_
            if ($parts.code -ne "duplicate_terminal_receipt") {
                $status = Write-BridgeStatus -Directory $directory -TaskPacket $taskPacket -State "quarantined" -Code $parts.code -Message $parts.message
                Write-Result -Directory $directory -Status $status -AsJson:$Json
            }
        }
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 2
    }
}

$directory = $null
$taskPacket = $null
try {
    if ([string]::IsNullOrWhiteSpace($Project)) { throw "Project is required." }
    if (-not [string]::IsNullOrWhiteSpace($Task) -and -not [string]::IsNullOrWhiteSpace($TaskFile)) { throw "Use Task or TaskFile, not both." }
    if ($MaxRounds -lt 1 -or $MaxRounds -gt 4) { throw "MaxRounds must be between 1 and 4." }
    if ($RoundNumber -lt 1 -or $RoundNumber -gt $MaxRounds) { throw "RoundNumber must be between 1 and MaxRounds." }
    if ($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 3600) { throw "TimeoutSeconds must be between 1 and 3600." }
    if ($MaxBudgetUsd -lt 0) { throw "MaxBudgetUsd cannot be negative." }

    $workspace = Resolve-DirectoryPath -Path $WorkspaceRoot -Label "Workspace root"
    $roots = New-Object System.Collections.Generic.List[string]
    $roots.Add($workspace)
    foreach ($rootCandidate in $AllowedRoot) {
        if ([string]::IsNullOrWhiteSpace($rootCandidate)) { continue }
        $resolvedRoot = Resolve-DirectoryPath -Path $rootCandidate -Label "Allowed root"
        if (-not ($roots | Where-Object { $_.Equals($resolvedRoot, [StringComparison]::OrdinalIgnoreCase) })) { $roots.Add($resolvedRoot) }
    }
    [string[]]$rootArray = $roots
    $inputCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($item in $InputFile) { if (-not [string]::IsNullOrWhiteSpace($item)) { $inputCandidates.Add($item) } }
    if ($InputListFile) {
        if (-not (Test-Path -LiteralPath $InputListFile -PathType Leaf)) { throw "Input list file does not exist: $InputListFile" }
        $listedInputs = Read-Utf8Text -Path $InputListFile | ConvertFrom-Json
        if ($listedInputs -is [string] -or $listedInputs -isnot [System.Collections.IEnumerable]) { throw "Input list file must contain a JSON array of paths." }
        foreach ($item in $listedInputs) {
            if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item)) { throw "Input list file entries must be non-empty strings." }
            $inputCandidates.Add($item)
        }
    }
    if ($TaskFile) { $inputCandidates.Add($TaskFile) }
    $inputs = Resolve-ApprovedInputs -Paths ([string[]]$inputCandidates) -Workspace $workspace -Roots $rootArray
    [object[]]$inputArray = @($inputs)
    if ($TaskFile) {
        $taskCandidate = if ([System.IO.Path]::IsPathRooted($TaskFile)) { $TaskFile } else { Join-Path $workspace $TaskFile }
        $resolvedTaskFile = (Resolve-Path -LiteralPath $taskCandidate).Path
        $Task = Read-Utf8Text -Path $resolvedTaskFile
    }
    if ([string]::IsNullOrWhiteSpace($Task)) { throw "Task or TaskFile is required." }

    if (-not $RunId) { $RunId = "run-" + [Guid]::NewGuid().ToString("N") }
    if (-not $TaskId) { $TaskId = "task-" + [Guid]::NewGuid().ToString("N") }
    if (-not $CorrelationId) { $CorrelationId = "correlation-" + [Guid]::NewGuid().ToString("N") }
    if (-not $AttemptId) { $AttemptId = ("attempt-{0:D3}-" -f $RoundNumber) + [Guid]::NewGuid().ToString("N").Substring(0, 12) }
    if ($DoneCriteria.Count -eq 0) { $DoneCriteria = @("Return a complete schema-valid evidence-backed receipt without editing files.") }
    if ($NoTouchRule.Count -eq 0) {
        $NoTouchRule = @(
            "Do not edit, create, move, or delete files.",
            "Do not run shell, Git, browser, network, deployment, outreach, billing, or account actions.",
            "Do not read credentials, secrets, browser profiles, or unrelated project history."
        )
    }

    $requiredReturn = @($script:RequiredReceiptFields)
    $taskPacket = [pscustomobject][ordered]@{
        schema_version = "1.0"
        run_id = $RunId
        task_id = $TaskId
        correlation_id = $CorrelationId
        attempt_id = $AttemptId
        created_at = Get-UtcStamp
        project_name = $Project
        workspace_root = $workspace
        objective = $Task
        input_files = $inputArray
        allowed_roots = $rootArray
        authority = [ordered]@{
            mode = "read_only"
            permission_mode = "plan"
            allowed_tools = @("Read", "Glob", "Grep")
            forbidden_tools = @("Bash", "Edit", "Write", "WebFetch", "WebSearch", "NotebookEdit", "Task")
        }
        no_touch_rules = @($NoTouchRule)
        done_criteria = @($DoneCriteria)
        required_return_fields = $requiredReturn
        model_request = [ordered]@{
            provider = "claude-code"
            model = $Model
            max_budget_usd = if ($MaxBudgetUsd -gt 0) { $MaxBudgetUsd } else { $null }
            budget_note = "Claude CLI documents this as API-call budget only; it is not claimed to cap subscription usage."
        }
        max_rounds = $MaxRounds
        round_number = $RoundNumber
    }

    $directory = New-ExchangeDirectory -Root $script:HandoffRoot -ProjectName $Project -Correlation $CorrelationId -Attempt $AttemptId
    Write-JsonAtomic -Path (Join-Path $directory "task.json") -Value $taskPacket
    Add-BridgeEvent -Directory $directory -Type "task_created" -Data @{ project = $Project; round_number = $RoundNumber; plan_only = [bool]$PlanOnly }

    $taskJson = $taskPacket | ConvertTo-Json -Depth 30
    $prompt = @"
You are a bounded read-only review worker reporting back to Codex.

Follow the task packet exactly. Use only Read, Glob, and Grep. Do not edit files, invoke shell or network tools, use browser integrations, contact anyone, change Git state, or broaden your authority. If required evidence is unavailable, return blocked instead of guessing.

Return only one JSON object matching the supplied JSON Schema. Keep all IDs exactly as provided. `files_touched` must be an empty array.

BEGIN_TASK_PACKET
$taskJson
END_TASK_PACKET
"@
    Write-Utf8NoBom -Path (Join-Path $directory "prompt.md") -Content $prompt

    $runtimeSchema = New-RuntimeReceiptSchema -TaskPacket $taskPacket
    $runtimeSchemaJson = $runtimeSchema | ConvertTo-Json -Depth 30 -Compress
    $sessionName = ConvertTo-SafeSlug -Value ("codex-claude-{0}-{1}" -f $Project, $AttemptId) -Fallback "codex-claude-review"
    $claudeArguments = New-Object System.Collections.Generic.List[string]
    foreach ($prefix in $ClaudePrefixArgument) { $claudeArguments.Add($prefix) }
    foreach ($argument in @(
        "--safe-mode", "--permission-mode", "plan", "--tools", "Read,Glob,Grep",
        "--allowedTools", "Read,Glob,Grep", "--disallowedTools", "Bash,Edit,Write,WebFetch,WebSearch,NotebookEdit,Task",
        "--strict-mcp-config", "--mcp-config", "{}", "--no-chrome", "--no-session-persistence",
        "--model", $Model, "--name", $sessionName, "--output-format", "json", "--json-schema", $runtimeSchemaJson, "-p"
    )) { $claudeArguments.Add("$argument") }
    $claudeArguments.Add("--add-dir")
    foreach ($root in $rootArray) { $claudeArguments.Add($root) }
    if ($MaxBudgetUsd -gt 0) { $claudeArguments.Add("--max-budget-usd"); $claudeArguments.Add($MaxBudgetUsd.ToString([Globalization.CultureInfo]::InvariantCulture)) }

    $commandPacket = [pscustomobject][ordered]@{
        schema_version = "1.0"
        provider = "claude-code"
        executable = $ClaudePath
        arguments = [string[]]$claudeArguments
        working_directory = $workspace
        stdin_source = "prompt.md"
        timeout_seconds = $TimeoutSeconds
        read_only = $true
        provider_invoked = $false
        created_at = Get-UtcStamp
    }
    Write-JsonAtomic -Path (Join-Path $directory "command.json") -Value $commandPacket
    $status = Write-BridgeStatus -Directory $directory -TaskPacket $taskPacket -State "planned" -Code "packet_ready" -Message "Read-only Claude packet and command prepared; provider not yet invoked."

    if ($PlanOnly) {
        Add-BridgeEvent -Directory $directory -Type "plan_only_completed" -Data @{ provider_invoked = $false }
        Write-Result -Directory $directory -Status $status -AsJson:$Json
        exit 0
    }

    $resolvedClaude = $null
    if (Test-Path -LiteralPath $ClaudePath -PathType Leaf) {
        $resolvedClaude = (Resolve-Path -LiteralPath $ClaudePath).Path
    } else {
        $command = Get-Command $ClaudePath -ErrorAction SilentlyContinue
        if ($command) { $resolvedClaude = $command.Source }
    }
    if (-not $resolvedClaude) {
        $status = Write-BridgeStatus -Directory $directory -TaskPacket $taskPacket -State "failed" -Code "provider_missing" -Message "Claude executable was not found: $ClaudePath"
        Add-BridgeEvent -Directory $directory -Type "provider_missing" -Data @{ executable = $ClaudePath }
        Write-Result -Directory $directory -Status $status -AsJson:$Json
        exit 3
    }

    $commandPacket.executable = $resolvedClaude
    $commandPacket.provider_invoked = $true
    $commandPacket | Add-Member -NotePropertyName "invoked_at" -NotePropertyValue (Get-UtcStamp)
    Write-JsonAtomic -Path (Join-Path $directory "command.json") -Value $commandPacket
    $status = Write-BridgeStatus -Directory $directory -TaskPacket $taskPacket -State "invoking" -Code "provider_started" -Message "Claude provider process started in hidden read-only mode."
    Add-BridgeEvent -Directory $directory -Type "provider_started" -Data @{ executable = $resolvedClaude; model = $Model }

    $processResult = Invoke-HiddenProcess -Executable $resolvedClaude -Arguments ([string[]]$claudeArguments) -WorkingDirectory $workspace -StandardInput $prompt -Timeout $TimeoutSeconds
    Save-RawResponse -Directory $directory -ProcessResult $processResult -Source "provider"
    if ($processResult.timed_out) {
        $status = Write-BridgeStatus -Directory $directory -TaskPacket $taskPacket -State "failed" -Code "provider_timeout" -Message "Claude provider exceeded the timeout and was terminated."
        Add-BridgeEvent -Directory $directory -Type "provider_timeout" -Data @{ timeout_seconds = $TimeoutSeconds }
        Write-Result -Directory $directory -Status $status -AsJson:$Json
        exit 4
    }
    if ($processResult.exit_code -ne 0) {
        $status = Write-BridgeStatus -Directory $directory -TaskPacket $taskPacket -State "failed" -Code "provider_exit_nonzero" -Message "Claude provider exited with code $($processResult.exit_code)."
        Add-BridgeEvent -Directory $directory -Type "provider_exit_nonzero" -Data @{ exit_code = $processResult.exit_code }
        Write-Result -Directory $directory -Status $status -AsJson:$Json
        exit 5
    }

    try {
        $imported = Import-ReceiptText -Directory $directory -TaskPacket $taskPacket -ResponseText $processResult.stdout -ProcessResult $processResult -Source "provider"
        Write-Result -Directory $directory -Status $imported.status -Receipt $imported.receipt -AsJson:$Json
        exit 0
    } catch {
        $quarantined = Read-Utf8Text -Path (Join-Path $directory "status.json") | ConvertFrom-Json
        Write-Result -Directory $directory -Status $quarantined -AsJson:$Json
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 6
    }
} catch {
    if ($directory -and $taskPacket) {
        $status = Write-BridgeStatus -Directory $directory -TaskPacket $taskPacket -State "failed" -Code "bridge_error" -Message $_.Exception.Message
        Add-BridgeEvent -Directory $directory -Type "bridge_error" -Data @{ message = $_.Exception.Message }
        Write-Result -Directory $directory -Status $status -AsJson:$Json
    }
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
}
