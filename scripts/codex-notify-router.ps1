param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $EventArgs
)

$ErrorActionPreference = "Continue"
$codexHome = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $codexHome "logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
$logPath = Join-Path $logDir "notify-router.log"

function Write-NotifyLog {
    param([string] $Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$stamp] $Message" | Add-Content -LiteralPath $logPath
}

try {
    $computerUseRoot = Join-Path $codexHome "plugins\cache\openai-bundled\computer-use"
    if (Test-Path -LiteralPath $computerUseRoot) {
        $computerUseNotify = Get-ChildItem -LiteralPath $computerUseRoot -Recurse -Filter "codex-computer-use.exe" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($computerUseNotify) {
            & $computerUseNotify.FullName @EventArgs | Out-Null
            Write-NotifyLog "computer-use notify forwarded: $($EventArgs -join ' ')"
        }
    }
} catch {
    Write-NotifyLog "computer-use notify failed: $($_.Exception.Message)"
}

try {
    & (Join-Path $PSScriptRoot "codex-project-freshness.ps1") -Quiet | Out-Null
    Write-NotifyLog "project freshness updated"
} catch {
    Write-NotifyLog "project freshness failed: $($_.Exception.Message)"
}
