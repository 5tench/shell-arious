Param(
    [string]$WorkspaceRoot = '\\wsl.localhost\Ubuntu\home\xander\source\repos',
    [string]$HistoryRoot = "$env:APPDATA\Code\User\History",
    [switch]$DryRun,
    [switch]$Backup
)

Write-Host "WorkspaceRoot: $WorkspaceRoot"
Write-Host "HistoryRoot: $HistoryRoot"
Write-Host "DryRun: $DryRun; Backup: $Backup"

$epoch = Get-Date -Date '1970-01-01T00:00:00Z'
$plan = @()

Get-ChildItem -Path $WorkspaceRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $file = $_.FullName
    try {
        $raw = Get-Content -Raw -ErrorAction Stop -LiteralPath $file
    } catch {
        return
    }

    if ($raw -like '*"version":1*' -and $raw -like '*"resource":*' -and $raw -like '*"entries":*') {
        try {
            $json = $raw | ConvertFrom-Json
        } catch {
            Write-Warning "Invalid JSON metadata in $file"
            return
        }

        $resource = $json.resource
        if (-not $resource) { Write-Warning "No resource in metadata for $file"; return }

        $entries = $json.entries
        if (-not $entries) { Write-Warning "No entries in metadata for $file"; return }

        # pick most recent entry
        $entry = $entries[$entries.Count - 1]
        $id = $entry.id
        $timestamp = $entry.timestamp

        # find history file (search all subfolders under HistoryRoot)
        $hist = Get-ChildItem -Path $HistoryRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $id } | Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if (-not $hist) {
            $plan += [pscustomobject]@{ SourceMeta = $file; Id = $id; Found = $false; HistoryPath = $null; Target = $null }
            Write-Host "MISSING: History file for id $id (metadata in $file)"
            return
        }

        # convert resource to UNC path: file://wsl.localhost/Ubuntu/... -> \\wsl.localhost\Ubuntu\...
        $resPath = $resource -replace '^file://',''
        $resPath = $resPath -replace '/','\\'
        if ($resPath -notmatch '^\\\\') { $resPath = '\\' + $resPath }

        $target = $resPath

        $plan += [pscustomobject]@{ SourceMeta = $file; Id = $id; Found = $true; HistoryPath = $hist.FullName; Target = $target; Timestamp = $timestamp }

        Write-Host "PLAN: $id -> $target (from $($hist.FullName))"
    }
}

Write-Host "\nSummary: $($plan.Count) candidate files found.\n"

if ($DryRun) { Write-Host "Dry run complete (no files written)."; return }

foreach ($p in $plan) {
    if (-not $p.Found) { continue }
    $tgtParent = Split-Path -Parent $p.Target
    if (-not (Test-Path $tgtParent)) {
        Write-Host "Creating directory: $tgtParent"
        New-Item -ItemType Directory -Force -Path $tgtParent | Out-Null
    }

    if ($Backup -and (Test-Path $p.Target)) {
        $bak = "$($p.Target).bak.$((Get-Date).ToString('yyyyMMddHHmmss'))"
        Write-Host "Backing up existing file to $bak"
        Copy-Item -LiteralPath $p.Target -Destination $bak -Force
    }

    Write-Host "Restoring $($p.HistoryPath) -> $($p.Target)"
    $content = Get-Content -Raw -LiteralPath $p.HistoryPath
    Set-Content -LiteralPath $p.Target -Value $content -Encoding UTF8 -Force

    if ($p.Timestamp) {
        try {
            $dt = $epoch.AddMilliseconds([double]$p.Timestamp).ToLocalTime()
            (Get-Item -LiteralPath $p.Target).LastWriteTime = $dt
            Write-Host "Set LastWriteTime to $dt"
        } catch {
            Write-Warning "Failed to set timestamp for $($p.Target): $_"
        }
    }
}

Write-Host "Restore complete."
