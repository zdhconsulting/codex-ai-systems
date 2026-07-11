param(
    [string] $CodexHome = "",
    [string] $TestRoot = "",
    [switch] $Json
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { [System.IO.Path]::GetFullPath($CodexHome) } else { Split-Path -Parent $PSScriptRoot }
$bridgePath = Join-Path $CodexHome "scripts\claude-bridge.ps1"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$TestRoot = if ($TestRoot) { [System.IO.Path]::GetFullPath($TestRoot) } else { Join-Path $CodexHome "tmp\claude-bridge-tests\$stamp offline suite" }
$workspace = Join-Path $TestRoot "workspace with spaces"
$handoffs = Join-Path $TestRoot "handoffs with spaces"
$fakePath = Join-Path $TestRoot "fake-claude.exe"
$fakeLog = Join-Path $TestRoot "fake-invocations.json"
$script:Checks = New-Object System.Collections.Generic.List[object]
$script:Failures = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param([string] $Name, [bool] $Passed, [string] $Detail = "")
    $status = if ($Passed) { "pass" } else { "fail" }
    $script:Checks.Add([pscustomobject]@{ name = $Name; status = $status; detail = $Detail })
    if (-not $Passed) { $script:Failures.Add("$Name - $Detail") }
    if (-not $Json) { Write-Host "$(if ($Passed) { 'PASS' } else { 'FAIL' }) $Name$(if ($Detail) { " - $Detail" })" }
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

function Invoke-Bridge {
    param([string[]] $Arguments)
    $allArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $bridgePath) + $Arguments
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = (Get-Command powershell.exe).Source
    $info.Arguments = (($allArguments | ForEach-Object { ConvertTo-WindowsArgument "$_" }) -join " ")
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{ exit_code = [int]$process.ExitCode; output = ($stdout.Result + $stderr.Result) }
}

function Get-ExchangePaths {
    if (-not (Test-Path -LiteralPath $handoffs)) { return @() }
    return @(Get-ChildItem -LiteralPath $handoffs -Directory | ForEach-Object { $_.FullName })
}

function Get-NewExchange {
    param([string[]] $Before)
    $beforeMap = @{}
    foreach ($path in $Before) { $beforeMap[$path.ToLowerInvariant()] = $true }
    return Get-ChildItem -LiteralPath $handoffs -Directory |
        Where-Object { -not $beforeMap.ContainsKey($_.FullName.ToLowerInvariant()) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Read-Json {
    param([string] $Path)
    return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json
}

if (-not (Test-Path -LiteralPath $bridgePath -PathType Leaf)) {
    throw "Bridge script missing: $bridgePath"
}
New-Item -ItemType Directory -Path $workspace, $handoffs -Force | Out-Null
$hebrew = [string]([char]0x05E9) + [char]0x05DC + [char]0x05D5 + [char]0x05DD
$spanish = "an" + [char]0x00E1 + "lisis"
$unicodeTask = "Review $hebrew and $spanish without edits"
[System.IO.File]::WriteAllText((Join-Path $workspace "first input.txt"), "first input - $hebrew", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $workspace "second input.md"), "second input - $spanish", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $TestRoot "outside.txt"), "outside", (New-Object System.Text.UTF8Encoding($false)))
$inputListPath = Join-Path $TestRoot "input-files.json"
[System.IO.File]::WriteAllText($inputListPath, (@((Join-Path $workspace "first input.txt"), (Join-Path $workspace "second input.md")) | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
$taskFilePath = Join-Path $workspace "unicode task.txt"
[System.IO.File]::WriteAllText($taskFilePath, $unicodeTask, (New-Object System.Text.UTF8Encoding($false)))

$fakeSource = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

public static class FakeClaudeProgram
{
    public static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        Console.InputEncoding = new UTF8Encoding(false);
        var serializer = new JavaScriptSerializer();
        var log = Environment.GetEnvironmentVariable("FAKE_CLAUDE_LOG");
        if (!String.IsNullOrEmpty(log)) File.WriteAllText(log, serializer.Serialize(args), new UTF8Encoding(false));
        var mode = Environment.GetEnvironmentVariable("FAKE_CLAUDE_MODE") ?? "valid";
        if (mode == "nonzero") { Console.Error.Write("simulated provider failure"); return 9; }
        if (mode == "timeout") { Thread.Sleep(3000); return 0; }
        if (mode == "malformed") { Console.Write("{not-json"); return 0; }
        var prompt = Console.In.ReadToEnd();
        const string begin = "BEGIN_TASK_PACKET";
        const string end = "END_TASK_PACKET";
        var start = prompt.IndexOf(begin, StringComparison.Ordinal);
        var finish = prompt.LastIndexOf(end, StringComparison.Ordinal);
        if (start < 0 || finish <= start) { Console.Error.Write("task packet markers missing"); return 8; }
        start += begin.Length;
        var taskJson = prompt.Substring(start, finish - start).Trim();
        var task = serializer.Deserialize<Dictionary<string, object>>(taskJson);
        var correlation = task["correlation_id"].ToString();
        var attempt = task["attempt_id"].ToString();
        if (mode == "wrong-correlation") correlation = "wrong-correlation";
        if (mode == "stale-attempt") attempt = "attempt-000-stale";
        var filesTouched = mode == "write-claim" ? new object[] { "unauthorized.txt" } : new object[0];
        var deliverable = mode == "write-claim" ? "I edited unauthorized.txt." : "Specific read-only recommendations with \u05e9\u05dc\u05d5\u05dd and an\u00e1lisis.";
        var receipt = new Dictionary<string, object> {
            { "schema_version", "1.0" },
            { "run_id", task["run_id"].ToString() },
            { "task_id", task["task_id"].ToString() },
            { "correlation_id", correlation },
            { "attempt_id", attempt },
            { "status", "succeeded" },
            { "summary", "Offline fake Claude review completed." },
            { "decisions", new object[] { "Keep deterministic scoring separate from judgment." } },
            { "deliverable", deliverable },
            { "evidence", new object[] { new Dictionary<string, object> { { "claim", "The supplied file was reviewed." }, { "ref", "first input.txt" } } } },
            { "files_needed", new object[0] },
            { "files_touched", filesTouched },
            { "blockers", new object[0] },
            { "owner_button_needed", false },
            { "commander_approval_needed", false },
            { "codex_next_action", "Apply or reject the recommendations in Codex." },
            { "confidence", 91 },
            { "go_back_to_codex", true },
            { "completed_at", DateTime.UtcNow.ToString("o") }
        };
        Console.Write(serializer.Serialize(new Dictionary<string, object> { { "type", "result" }, { "structured_output", receipt } }));
        return 0;
    }
}
'@

try {
    Add-Type -TypeDefinition $fakeSource -Language CSharp -OutputAssembly $fakePath -OutputType ConsoleApplication -ReferencedAssemblies "System.Web.Extensions.dll"
    Add-Check "fake provider compiled" (Test-Path -LiteralPath $fakePath -PathType Leaf) $fakePath
} catch {
    Add-Check "fake provider compiled" $false $_.Exception.Message
    $summary = [pscustomobject]@{ status = "fail"; test_root = $TestRoot; failures = @($script:Failures); checks = @($script:Checks) }
    if ($Json) { $summary | ConvertTo-Json -Depth 8 }
    exit 1
}

$env:FAKE_CLAUDE_LOG = $fakeLog
$env:FAKE_CLAUDE_MODE = "valid"

$before = Get-ExchangePaths
$plan = Invoke-Bridge @(
    "-PlanOnly", "-Json", "-Project", "Unicode Project", "-TaskFile", $taskFilePath,
    "-WorkspaceRoot", $workspace, "-InputListFile", $inputListPath,
    "-ClaudePath", $fakePath, "-HandoffRoot", $handoffs
)
$planExchange = Get-NewExchange $before
Add-Check "plan-only exits successfully" ($plan.exit_code -eq 0) (($plan.output -replace '\s+', ' ').Trim())
Add-Check "plan-only creates exchange" ($null -ne $planExchange) $(if ($planExchange) { $planExchange.FullName } else { "none" })
Add-Check "plan-only never invokes provider" (-not (Test-Path -LiteralPath $fakeLog)) $fakeLog
if ($planExchange) {
    $planTask = Read-Json (Join-Path $planExchange.FullName "task.json")
    $planCommand = Read-Json (Join-Path $planExchange.FullName "command.json")
    $planStatus = Read-Json (Join-Path $planExchange.FullName "status.json")
    Add-Check "task packet contains multiple input files" (@($planTask.input_files).Count -eq 3) "count=$(@($planTask.input_files).Count)"
    Add-Check "unicode task survives packet" ($planTask.objective -match [regex]::Escape($hebrew) -and $planTask.objective -match [regex]::Escape($spanish)) $planTask.objective
    Add-Check "plan status is non-terminal planned" ($planStatus.state -eq "planned" -and $planStatus.code -eq "packet_ready") "$($planStatus.state)/$($planStatus.code)"
    $argText = @($planCommand.arguments) -join " "
    $safeArgs = $argText -match "--safe-mode" -and $argText -match "--permission-mode plan" -and
        $argText -match "--tools Read,Glob,Grep" -and $argText -match "--strict-mcp-config" -and
        $argText -match "--no-chrome" -and $argText -match "--no-session-persistence" -and
        $argText -notmatch "dangerously-skip-permissions"
    Add-Check "read-only command construction" $safeArgs $argText
}

$before = Get-ExchangePaths
$env:FAKE_CLAUDE_MODE = "valid"
$valid = Invoke-Bridge @(
    "-Json", "-Project", "Valid Fake Review", "-Task", "Review the supplied evidence",
    "-WorkspaceRoot", $workspace, "-InputFile", (Join-Path $workspace "first input.txt"),
    "-ClaudePath", $fakePath, "-HandoffRoot", $handoffs, "-TimeoutSeconds", "10"
)
$validExchange = Get-NewExchange $before
Add-Check "valid fake invocation exits successfully" ($valid.exit_code -eq 0) (($valid.output -replace '\s+', ' ').Trim())
if ($validExchange) {
    $validStatus = Read-Json (Join-Path $validExchange.FullName "status.json")
    $validTask = Read-Json (Join-Path $validExchange.FullName "task.json")
    $validReceiptPath = Join-Path $validExchange.FullName "receipt.json"
    $validReceipt = if (Test-Path -LiteralPath $validReceiptPath) { Read-Json $validReceiptPath } else { $null }
    Add-Check "valid receipt accepted" ($validStatus.state -eq "succeeded" -and $validStatus.code -eq "receipt_accepted" -and $validReceipt) "$($validStatus.state)/$($validStatus.code)"
    Add-Check "receipt IDs correlate" ($validReceipt -and $validReceipt.correlation_id -eq $validTask.correlation_id -and $validReceipt.attempt_id -eq $validTask.attempt_id) $(if ($validReceipt) { "$($validReceipt.correlation_id)" } else { "receipt missing" })
    Add-Check "unicode response survives" ($validReceipt -and $validReceipt.deliverable -match [regex]::Escape($hebrew) -and $validReceipt.deliverable -match [regex]::Escape($spanish)) $(if ($validReceipt) { $validReceipt.deliverable } else { "receipt missing" })
    Add-Check "all required artifacts exist" ((@("task.json", "prompt.md", "command.json", "raw-response.json", "receipt.json", "status.json", "events.jsonl") | Where-Object { -not (Test-Path -LiteralPath (Join-Path $validExchange.FullName $_)) }).Count -eq 0) $validExchange.FullName
}
Add-Check "fake provider received invocation" (Test-Path -LiteralPath $fakeLog -PathType Leaf) $fakeLog

$scenarioExpectations = [ordered]@{
    "malformed" = @{ exit = 6; state = "quarantined"; code = "malformed_json" }
    "wrong-correlation" = @{ exit = 6; state = "quarantined"; code = "correlation_id_mismatch" }
    "stale-attempt" = @{ exit = 6; state = "quarantined"; code = "attempt_id_mismatch" }
    "write-claim" = @{ exit = 6; state = "quarantined"; code = "authority_violation" }
    "nonzero" = @{ exit = 5; state = "failed"; code = "provider_exit_nonzero" }
    "timeout" = @{ exit = 4; state = "failed"; code = "provider_timeout" }
}
foreach ($mode in $scenarioExpectations.Keys) {
    $before = Get-ExchangePaths
    $env:FAKE_CLAUDE_MODE = $mode
    $timeout = if ($mode -eq "timeout") { "1" } else { "10" }
    $run = Invoke-Bridge @(
        "-Json", "-Project", "Scenario $mode", "-Task", "Offline failure-path test",
        "-WorkspaceRoot", $workspace, "-InputFile", (Join-Path $workspace "first input.txt"),
        "-ClaudePath", $fakePath, "-HandoffRoot", $handoffs, "-TimeoutSeconds", $timeout
    )
    $exchange = Get-NewExchange $before
    $expected = $scenarioExpectations[$mode]
    $status = if ($exchange) { Read-Json (Join-Path $exchange.FullName "status.json") } else { $null }
    $passed = $run.exit_code -eq $expected.exit -and $status -and $status.state -eq $expected.state -and $status.code -eq $expected.code
    Add-Check "failure path: $mode" $passed "exit=$($run.exit_code) state=$($status.state) code=$($status.code)"
}

$before = Get-ExchangePaths
$missingProvider = Invoke-Bridge @(
    "-Json", "-Project", "Missing Provider", "-Task", "Do not invoke",
    "-WorkspaceRoot", $workspace, "-ClaudePath", (Join-Path $TestRoot "missing-claude.exe"),
    "-HandoffRoot", $handoffs
)
$missingProviderExchange = Get-NewExchange $before
$missingProviderStatus = if ($missingProviderExchange) { Read-Json (Join-Path $missingProviderExchange.FullName "status.json") } else { $null }
Add-Check "missing executable fails closed" ($missingProvider.exit_code -eq 3 -and $missingProviderStatus.code -eq "provider_missing") "exit=$($missingProvider.exit_code) code=$($missingProviderStatus.code)"

$countBefore = (Get-ExchangePaths).Count
$outside = Invoke-Bridge @(
    "-PlanOnly", "-Json", "-Project", "Outside Root", "-Task", "Reject outside input",
    "-WorkspaceRoot", $workspace, "-InputFile", (Join-Path $TestRoot "outside.txt"),
    "-ClaudePath", $fakePath, "-HandoffRoot", $handoffs
)
Add-Check "outside allowed root rejected" ($outside.exit_code -eq 2 -and (Get-ExchangePaths).Count -eq $countBefore) "exit=$($outside.exit_code)"

$missingInput = Invoke-Bridge @(
    "-PlanOnly", "-Json", "-Project", "Missing Input", "-Task", "Reject missing input",
    "-WorkspaceRoot", $workspace, "-InputFile", (Join-Path $workspace "missing.txt"),
    "-ClaudePath", $fakePath, "-HandoffRoot", $handoffs
)
Add-Check "missing input rejected" ($missingInput.exit_code -eq 2) "exit=$($missingInput.exit_code)"

$bounded = Invoke-Bridge @(
    "-PlanOnly", "-Json", "-Project", "Bounded Rounds", "-Task", "Reject excess round",
    "-WorkspaceRoot", $workspace, "-RoundNumber", "3", "-MaxRounds", "2",
    "-ClaudePath", $fakePath, "-HandoffRoot", $handoffs
)
Add-Check "bounded round enforcement" ($bounded.exit_code -eq 2) "exit=$($bounded.exit_code)"

$before = Get-ExchangePaths
$duplicatePlan = Invoke-Bridge @(
    "-PlanOnly", "-Json", "-Project", "Duplicate Receipt", "-Task", "Import one receipt once",
    "-WorkspaceRoot", $workspace, "-InputFile", (Join-Path $workspace "first input.txt"),
    "-ClaudePath", $fakePath, "-HandoffRoot", $handoffs
)
$duplicateExchange = Get-NewExchange $before
if ($duplicateExchange) {
    $duplicateTask = Read-Json (Join-Path $duplicateExchange.FullName "task.json")
    $response = [ordered]@{
        structured_output = [ordered]@{
            schema_version = "1.0"
            run_id = $duplicateTask.run_id
            task_id = $duplicateTask.task_id
            correlation_id = $duplicateTask.correlation_id
            attempt_id = $duplicateTask.attempt_id
            status = "succeeded"
            summary = "Imported once."
            decisions = @("Keep the bridge bounded.")
            deliverable = "Offline imported receipt."
            evidence = @([ordered]@{ claim = "Input was available."; ref = "first input.txt" })
            files_needed = @()
            files_touched = @()
            blockers = @()
            owner_button_needed = $false
            commander_approval_needed = $false
            codex_next_action = "Continue in Codex."
            confidence = 90
            go_back_to_codex = $true
            completed_at = [DateTime]::UtcNow.ToString("o")
        }
    }
    $responsePath = Join-Path $TestRoot "import-response.json"
    [System.IO.File]::WriteAllText($responsePath, ($response | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
    $firstImport = Invoke-Bridge @("-Json", "-ExchangePath", $duplicateExchange.FullName, "-ImportResponseFile", $responsePath, "-HandoffRoot", $handoffs)
    $receiptPath = Join-Path $duplicateExchange.FullName "receipt.json"
    $firstHash = if (Test-Path -LiteralPath $receiptPath) { (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash } else { "" }
    $secondImport = Invoke-Bridge @("-Json", "-ExchangePath", $duplicateExchange.FullName, "-ImportResponseFile", $responsePath, "-HandoffRoot", $handoffs)
    $secondHash = if (Test-Path -LiteralPath $receiptPath) { (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash } else { "" }
    Add-Check "valid receipt import" ($firstImport.exit_code -eq 0 -and $firstHash) "exit=$($firstImport.exit_code)"
    Add-Check "duplicate terminal receipt rejected without overwrite" ($secondImport.exit_code -eq 2 -and $firstHash -eq $secondHash) "exit=$($secondImport.exit_code)"
} else {
    Add-Check "valid receipt import" $false "Plan-only exchange was not created."
    Add-Check "duplicate terminal receipt rejected without overwrite" $false "Plan-only exchange was not created."
}

$bridgeText = [System.IO.File]::ReadAllText($bridgePath, (New-Object System.Text.UTF8Encoding($false)))
$noUiDependency = $bridgeText -notmatch '(?i)Get-Clipboard|Set-Clipboard|agent\.browsers|Start-Process\s+.*(chrome|edge)'
Add-Check "no clipboard or browser dependency" $noUiDependency $bridgePath

$skillValidator = Join-Path $CodexHome "skills\.system\skill-creator\scripts\quick_validate.py"
$skillPath = Join-Path $CodexHome "skills\codex-claude-bridge"
$previousPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = "Continue"
    $validatorOutput = & python $skillValidator $skillPath 2>&1 | Out-String
    $validatorExitCode = $LASTEXITCODE
} catch {
    $validatorOutput = $_.Exception.Message
    $validatorExitCode = 999
} finally {
    $ErrorActionPreference = $previousPreference
}
Add-Check "skill validates" ($validatorExitCode -eq 0 -and $validatorOutput -match "Skill is valid") (($validatorOutput -replace '\s+', ' ').Trim())

Remove-Item Env:\FAKE_CLAUDE_MODE -ErrorAction SilentlyContinue
Remove-Item Env:\FAKE_CLAUDE_LOG -ErrorAction SilentlyContinue
$statusText = if ($script:Failures.Count -eq 0) { "pass" } else { "fail" }
$summary = [pscustomobject]@{
    status = $statusText
    test_root = $TestRoot
    fake_provider = $fakePath
    checks_passed = @($script:Checks | Where-Object { $_.status -eq "pass" }).Count
    checks_failed = $script:Failures.Count
    failures = [string[]]$script:Failures
    checks = [object[]]$script:Checks
    live_provider_invoked = $false
}
if ($Json) {
    $summary | ConvertTo-Json -Depth 10
} else {
    Write-Host ""
    Write-Host "Claude bridge offline smoke summary"
    Write-Host "Status: $($summary.status)"
    Write-Host "Passed: $($summary.checks_passed)"
    Write-Host "Failed: $($summary.checks_failed)"
    Write-Host "Artifacts: $TestRoot"
    Write-Host "Live provider invoked: false"
}
if ($script:Failures.Count -gt 0) { exit 1 }
exit 0
