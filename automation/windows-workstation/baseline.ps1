#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Audit', 'Plan', 'Apply', 'Rollback')]
    [string]$Mode = 'Audit',

    [Parameter()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.psd1'),

    [Parameter()]
    [string]$OutputPath = (Join-Path $PSScriptRoot 'output'),

    [Parameter()]
    [string]$AuditPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Import-Module (Join-Path $PSScriptRoot 'modules/Audit.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'modules/Changes.psm1') -Force

    $config = Import-WorkstationConfig -Path $ConfigPath
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        $null = New-Item -ItemType Directory -Path $OutputPath
    }

    switch ($Mode) {
        'Audit' {
            $audit = Get-WorkstationAudit -Config $config
            $paths = Export-AuditReport -Audit $audit -OutputPath $OutputPath
            Write-Output 'Audit complete.'
            Write-Output "Markdown: $($paths.Markdown)"
            Write-Output "JSON:     $($paths.Json)"
        }
        'Plan' {
            if (-not $AuditPath) {
                $AuditPath = Get-ChildItem -LiteralPath $OutputPath -Filter 'audit-*.json' |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1 -ExpandProperty FullName
            }
            if (-not $AuditPath -or -not (Test-Path -LiteralPath $AuditPath)) {
                throw 'Plan mode requires -AuditPath or an existing output/audit-*.json report.'
            }
            $audit = Read-AuditReport -Path $AuditPath
            $recommendations = Get-WorkstationPlan -Audit $audit -Config $config
            $paths = Export-PlanReport -Recommendations $recommendations -OutputPath $OutputPath
            Write-Output 'Plan complete. No system changes were made.'
            foreach ($classification in 'Safe', 'Review', 'DoNotChange') {
                $count = @($recommendations |
                    Where-Object Classification -eq $classification).Count
                Write-Output ("{0}: {1}" -f $classification, $count)
            }
            Write-Output "Markdown: $($paths.Markdown)"
            Write-Output "JSON:     $($paths.Json)"
        }
        { $_ -in 'Apply', 'Rollback' } {
            Write-Warning "$Mode is intentionally not implemented. No system changes were made."
            exit 2
        }
    }
}
catch {
    Write-Error "baseline.ps1 failed: $($_.Exception.Message)"
    exit 1
}
