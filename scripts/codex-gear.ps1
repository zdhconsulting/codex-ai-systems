param(
    [switch] $List,
    [string] $Profile = "",
    [switch] $Json,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $PromptParts
)

$modulePath = Join-Path $PSScriptRoot "CodexGear.psm1"
Import-Module $modulePath -Force

$prompt = ($PromptParts -join " ").Trim()
$matrix = Get-CodexGearMatrix

if ($Profile) {
    $gear = Get-CodexGear -Profile $Profile
} elseif ($prompt) {
    $gear = Get-CodexGear -Profile (Select-CodexGear -Text $prompt)
} else {
    $gear = $null
}
$workRoute = if ($prompt) { Select-AiWorkRoute -Text $prompt } else { $null }

if ($Json) {
    if ($gear) {
        $gear | ConvertTo-Json -Depth 4
    } else {
        $matrix.Values | ConvertTo-Json -Depth 4
    }
    exit 0
}

if ($gear) {
    if ($workRoute) {
        $signalText = if ($workRoute.Signals -and $workRoute.Signals.Count -gt 0) {
            $workRoute.Signals -join ", "
        } else {
            "none"
        }
        Write-Host "AI credits optimizer route"
        Write-Host "Work route: $($workRoute.Route)"
        Write-Host "Reason: $($workRoute.Reason)"
        Write-Host "Confidence: $($workRoute.Confidence)"
        Write-Host "Signals: $signalText"
        Write-Host ""
    }
    if ($workRoute -and $workRoute.Route -eq "chatgpt") {
        Write-Host "Codex fallback gear route"
    } else {
        Write-Host "Codex gear route"
    }
    Write-Host "Profile: $($gear.Profile)"
    Write-Host "Gear: $($gear.Gear)"
    Write-Host "Model: $($gear.Model)"
    Write-Host "Reasoning effort: $($gear.Effort)"
    $tier = if ($gear.ServiceTier) { $gear.ServiceTier } else { "(default/none)" }
    Write-Host "Service tier: $tier"
    Write-Host "Command: codex $($gear.Command)"
    Write-Host "Purpose: $($gear.Purpose)"
    if ($prompt) { Write-Host "Prompt: $prompt" }
    exit 0
}

$matrix.Values |
    Select-Object Profile, Gear, Model, Effort, @{Name="ServiceTier";Expression={if ($_.ServiceTier) {$_.ServiceTier} else {"(default/none)"}}}, Command, Purpose |
    Format-Table -AutoSize -Wrap
