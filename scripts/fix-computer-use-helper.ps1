param(
    [string]$RuntimeRoot = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\runtimes\cua_node")
)

$ErrorActionPreference = "Stop"

$ExportKey = "./dist/project/cua/sky_js/src/targets/windows/internal/computer_use_client_base.js"
$ExportValue = "./dist/project/cua/sky_js/src/targets/windows/internal/computer_use_client_base.js"

if (-not (Test-Path -LiteralPath $RuntimeRoot)) {
    throw "Codex Computer Use runtime root not found: $RuntimeRoot"
}

$packageFiles = @(Get-ChildItem -LiteralPath $RuntimeRoot -Recurse -Filter package.json |
    Where-Object { $_.FullName -like "*\node_modules\@oai\sky\package.json" })

if (-not $packageFiles.Count) {
    throw "No @oai/sky package.json found under $RuntimeRoot"
}

$updated = New-Object System.Collections.Generic.List[string]
$alreadyOk = New-Object System.Collections.Generic.List[string]

foreach ($file in $packageFiles) {
    $json = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if ($json.name -ne "@oai/sky") {
        continue
    }

    if ($null -eq $json.exports) {
        $json | Add-Member -MemberType NoteProperty -Name "exports" -Value ([pscustomobject]@{}) -Force
    }

    $exports = $json.exports
    $hasExport = $false
    if ($exports.PSObject.Properties.Name -contains $ExportKey) {
        $hasExport = ([string]$exports.$ExportKey -eq $ExportValue)
    }

    if ($hasExport) {
        $alreadyOk.Add($file.FullName) | Out-Null
        continue
    }

    $exports | Add-Member -MemberType NoteProperty -Name $ExportKey -Value $ExportValue -Force
    $encoded = $json | ConvertTo-Json -Depth 20
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($file.FullName, $encoded + [Environment]::NewLine, $utf8NoBom)
    $updated.Add($file.FullName) | Out-Null
}

[pscustomobject][ordered]@{
    status = "ok"
    updated_count = $updated.Count
    already_ok_count = $alreadyOk.Count
    updated = @($updated.ToArray())
    already_ok = @($alreadyOk.ToArray())
} | ConvertTo-Json -Depth 4
