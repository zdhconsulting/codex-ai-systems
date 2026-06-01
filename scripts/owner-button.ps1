param(
    [ValidateSet("list", "add", "done", "clear-done")]
    [string] $Action = "list",
    [string] $Id = "",
    [string] $Project = "",
    [string] $Site = "",
    [string] $Needed = "",
    [string] $Why = "",
    [string] $Next = ""
)

$queuePath = Join-Path $env:USERPROFILE ".codex\queues\owner-buttons.json"
New-Item -ItemType Directory -Force (Split-Path $queuePath) | Out-Null
if (-not (Test-Path $queuePath)) {
    "[]" | Set-Content -Path $queuePath -Encoding UTF8
}

function Read-Queue {
    $raw = Get-Content -Path $queuePath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $items = $raw | ConvertFrom-Json
    if ($null -eq $items) { return @() }
    return @($items)
}

function Save-Queue {
    param([array] $Items)
    $Items = @($Items)
    if ($Items.Count -eq 0) {
        "[]" | Set-Content -Path $queuePath -Encoding UTF8
        return
    }
    ConvertTo-Json -InputObject $Items -Depth 8 | Set-Content -Path $queuePath -Encoding UTF8
}

function Show-Queue {
    $items = Read-Queue
    $open = @($items | Where-Object { $_.Status -eq "open" })
    if ($open.Count -eq 0) {
        Write-Host "Owner Button Queue: no open owner buttons."
        Write-Host "Queue file: $queuePath"
        return
    }

    Write-Host "Owner Button Queue: $($open.Count) open"
    foreach ($item in $open) {
        Write-Host ""
        Write-Host "ID: $($item.Id)"
        Write-Host "Project: $($item.Project)"
        Write-Host "Site/tool: $($item.Site)"
        Write-Host "Needed: $($item.Needed)"
        if ($item.Why) { Write-Host "Why Codex is blocked: $($item.Why)" }
        if ($item.Next) { Write-Host "Codex next: $($item.Next)" }
        Write-Host "Created: $($item.CreatedAt)"
    }
    Write-Host ""
    Write-Host "Queue file: $queuePath"
}

switch ($Action) {
    "list" {
        Show-Queue
    }
    "add" {
        if (-not $Project -or -not $Site -or -not $Needed) {
            Write-Error "Usage: owner-button.cmd add -Project NAME -Site TOOL -Needed ACTION [-Why REASON] [-Next NEXT_STEP]"
            exit 2
        }
        $items = Read-Queue
        $newId = "ob-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        $item = [ordered]@{
            Id = $newId
            Status = "open"
            Project = $Project
            Site = $Site
            Needed = $Needed
            Why = $Why
            Next = $Next
            CreatedAt = (Get-Date).ToString("s")
            DoneAt = ""
        }
        Save-Queue -Items (@($items) + [pscustomobject]$item)
        Write-Host "Owner button added: $newId"
        Show-Queue
    }
    "done" {
        if (-not $Id) {
            Write-Error "Usage: owner-button.cmd done -Id OWNER_BUTTON_ID"
            exit 2
        }
        $items = Read-Queue
        $found = $false
        foreach ($item in $items) {
            if ($item.Id -eq $Id) {
                $item.Status = "done"
                $item.DoneAt = (Get-Date).ToString("s")
                $found = $true
            }
        }
        if (-not $found) {
            Write-Error "Owner button ID not found: $Id"
            exit 1
        }
        Save-Queue -Items $items
        Write-Host "Owner button marked done: $Id"
        Show-Queue
    }
    "clear-done" {
        $items = Read-Queue
        $open = @($items | Where-Object { $_.Status -eq "open" })
        Save-Queue -Items $open
        Write-Host "Cleared done owner buttons. Open items kept: $($open.Count)"
    }
}
