param(
    [string] $CodexHome = "",
    [switch] $Json
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$ScriptPath = Join-Path $CodexHome "scripts\codex-narrow-thread-rehome.ps1"

function Get-CodexDesktopProcess {
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try {
            $path = $_.Path
            $isPackagedApp = $path -match "\\WindowsApps\\OpenAI\.Codex_[^\\]+\\app\\"
            $isUnifiedDesktop = ($_.ProcessName -ieq "ChatGPT") -and ($path -match "\\app\\ChatGPT\.exe$")
            $isLegacyDesktop = ($_.ProcessName -ieq "Codex") -and ($path -match "\\app\\Codex\.exe$")
            $isPackagedApp -and ($isUnifiedDesktop -or $isLegacyDesktop)
        } catch {
            $false
        }
    }
}

Write-Host "Waiting for Codex Desktop to exit before applying narrow thread rehome..."
while (@(Get-CodexDesktopProcess).Count -gt 0) {
    Start-Sleep -Seconds 2
}

if ($Json) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Apply -Json
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Apply
}

$exitCode = $LASTEXITCODE
Write-Host "Narrow thread rehome completed with exit code $exitCode"
exit $exitCode
