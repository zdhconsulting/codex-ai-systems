[CmdletBinding()]
param(
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'

$requiredVersion = '1.0.6'
$cacheBase = Join-Path $env:USERPROFILE '.claude\plugins\cache\openai-codex\codex'
$patchRoot = Join-Path $PSScriptRoot "vendor\codex-plugin-cc\$requiredVersion\scripts"
$expectedFiles = @(
    [pscustomobject]@{
        RelativePath = 'lib\codex.mjs'
        OfficialHash = '3446BAB264CA51EE16F8A1458248973B1E19B53A5766B33EBAD4C0EAE813CB2B'
    },
    [pscustomobject]@{
        RelativePath = 'lib\tracked-jobs.mjs'
        OfficialHash = 'EB61689344857155762D6A7246CB2CEED683B6CA67D41D761E9B16C2A2FA5C9D'
    },
    [pscustomobject]@{
        RelativePath = 'codex-companion.mjs'
        OfficialHash = 'E33A4206EB45A274997B93BA2332EC395046FE00700147D540FD5740B25A906B'
    }
)

function Write-Result {
    param(
        [string]$Status,
        [object[]]$Files,
        [string]$Detail = $null
    )

    [pscustomobject]@{
        status = $Status
        plugin = 'codex@openai-codex'
        required_version = $requiredVersion
        detail = $Detail
        files = $Files
    } | ConvertTo-Json -Depth 6
}

if (-not (Test-Path -LiteralPath $cacheBase)) {
    Write-Result -Status 'plugin_not_installed' -Files @() -Detail $cacheBase
    exit 2
}

$versionDirectory = Get-ChildItem -LiteralPath $cacheBase -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1

if (-not $versionDirectory) {
    Write-Result -Status 'plugin_version_not_found' -Files @() -Detail $cacheBase
    exit 2
}

if ($versionDirectory.Name -ne $requiredVersion) {
    Write-Result -Status 'unsupported_plugin_version' -Files @() -Detail "Installed $($versionDirectory.Name); port and re-verify the telemetry patch before applying it."
    exit 2
}

$fileStates = foreach ($file in $expectedFiles) {
    $source = Join-Path $patchRoot $file.RelativePath
    $destination = Join-Path $versionDirectory.FullName (Join-Path 'scripts' $file.RelativePath)
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Durable patch source is missing: $source"
    }

    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
    $destinationExists = Test-Path -LiteralPath $destination
    $destinationHash = if ($destinationExists) {
        (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
    } else {
        $null
    }
    $state = if ($destinationHash -eq $patchHash) {
        'patched'
    } elseif (-not $destinationExists -or $destinationHash -eq $file.OfficialHash) {
        'needs_patch'
    } else {
        'unexpected_content'
    }

    [pscustomobject]@{
        relative_path = $file.RelativePath
        source = $source
        destination = $destination
        destination_existed = $destinationExists
        official_hash = $file.OfficialHash
        patch_hash = $patchHash
        destination_hash = $destinationHash
        state = $state
    }
}

if ($fileStates.state -contains 'unexpected_content') {
    Write-Result -Status 'refused_unexpected_content' -Files $fileStates -Detail 'A plugin file differs from both the verified official source and the durable patch. No files were changed.'
    exit 2
}

if ($CheckOnly) {
    $status = if ($fileStates.state -contains 'needs_patch') { 'patch_needed' } else { 'patched' }
    Write-Result -Status $status -Files $fileStates
    exit 0
}

if ($fileStates.state -notcontains 'needs_patch') {
    Write-Result -Status 'patched' -Files $fileStates -Detail 'No changes required.'
    exit 0
}

$backupRoot = Join-Path $env:TEMP "codex-plugin-cc-telemetry-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

try {
    foreach ($file in $fileStates) {
        if ($file.state -ne 'needs_patch') {
            continue
        }

        if ($file.destination_existed) {
            $backup = Join-Path $backupRoot $file.relative_path
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
            Copy-Item -LiteralPath $file.destination -Destination $backup -Force
        }

        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file.destination) | Out-Null
        Copy-Item -LiteralPath $file.source -Destination $file.destination -Force
    }

    foreach ($file in $fileStates) {
        & node --check $file.destination
        if ($LASTEXITCODE -ne 0) {
            throw "Node syntax validation failed for $($file.destination)"
        }
    }
} catch {
    foreach ($file in $fileStates) {
        if ($file.state -ne 'needs_patch') {
            continue
        }
        $backup = Join-Path $backupRoot $file.relative_path
        if ($file.destination_existed -and (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $backup -Destination $file.destination -Force
        } elseif (-not $file.destination_existed -and (Test-Path -LiteralPath $file.destination)) {
            Remove-Item -LiteralPath $file.destination -Force
        }
    }
    throw
} finally {
    Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$finalStates = foreach ($file in $fileStates) {
    $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.destination).Hash
    [pscustomobject]@{
        relative_path = $file.relative_path
        destination = $file.destination
        patch_hash = $file.patch_hash
        destination_hash = $destinationHash
        state = if ($destinationHash -eq $file.patch_hash) { 'patched' } else { 'verification_failed' }
    }
}

if ($finalStates.state -contains 'verification_failed') {
    Write-Result -Status 'verification_failed' -Files $finalStates
    exit 2
}

Write-Result -Status 'patched' -Files $finalStates -Detail 'Telemetry compatibility patch applied and syntax-checked.'
