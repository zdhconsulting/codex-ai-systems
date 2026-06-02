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

$modulePath = Join-Path $PSScriptRoot "CodexGear.psm1"
Import-Module $modulePath -Force

$profile = Select-CodexGear -Text $prompt
$gear = Get-CodexGear -Profile $profile

Write-Host "Codex auto gear: $($gear.Profile) ($($gear.Gear))"
Write-Host "Model: $($gear.Model)"
Write-Host "Reasoning effort: $($gear.Effort)"
$tier = if ($gear.ServiceTier) { $gear.ServiceTier } else { "(default/none)" }
Write-Host "Service tier: $tier"
Write-Host "Workspace: $Cwd"
Write-Host "Command: codex $($gear.Command)"

$codexHome = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $codexHome "logs"
$logPath = Join-Path $logDir "reasoning-gear.log"
New-Item -ItemType Directory -Force $logDir | Out-Null
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[$timestamp] $($gear.Profile)/$($gear.Gear) | model=$($gear.Model) | effort=$($gear.Effort) | tier=$tier | $Cwd | $prompt" | Add-Content -Path $logPath

if ($DryRun) {
    Write-Host "Dry run only. Prompt: $prompt"
    Write-Host "Logged to: $logPath"
    exit 0
}

$codex = Get-CodexExecutable
if ($gear.Command -eq "review") {
    $configArgs = New-CodexConfigArgs -Gear $gear
    Push-Location -LiteralPath $Cwd
    try {
        & $codex review @configArgs $prompt
    } finally {
        Pop-Location
    }
} else {
    & $codex exec -C $Cwd -p $profile $prompt
}
