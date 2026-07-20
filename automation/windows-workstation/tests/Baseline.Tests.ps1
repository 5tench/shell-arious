$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'modules/Audit.psm1') -Force
Import-Module (Join-Path $root 'modules/Changes.psm1') -Force

Describe 'Configuration validation' {
    It 'loads the repository policy' {
        $config = Import-WorkstationConfig (Join-Path $root 'config.psd1')
        $config.SamplingDurationSeconds | Should -BeGreaterThan 0
        $config.RequiredWindowsFeatures | Should -Contain 'VirtualMachinePlatform'
    }

    It 'rejects a missing policy key' {
        $path = Join-Path $TestDrive 'invalid.psd1'
        Set-Content $path '@{ SamplingDurationSeconds = 1 }'
        { Import-WorkstationConfig $path } | Should -Throw "*missing*"
    }
}

Describe 'Audit report parsing and generation' {
    BeforeAll {
        $script:audit = [pscustomobject]@{
            SchemaVersion = 1
            CollectedAt = '2026-01-02T03:04:05Z'
            Computer = [pscustomobject]@{ ComputerName = 'TEST'; Edition = 'Windows 11' }
            UtilizationSamples = @()
            Probes = @(
                [pscustomobject]@{
                    Name = 'StartupApplications'; Status = 'Collected'
                    Data = @([pscustomobject]@{ Name = 'Example'; Location = 'Registry' })
                    Error = $null
                }
            )
        }
    }

    It 'round trips structured JSON' {
        $null = New-Item -ItemType Directory (Join-Path $TestDrive 'reports')
        $paths = Export-AuditReport $audit (Join-Path $TestDrive 'reports')
        $parsed = Read-AuditReport $paths.Json
        $parsed.SchemaVersion | Should -Be 1
        $parsed.Computer.ComputerName | Should -Be 'TEST'
    }

    It 'generates readable Markdown' {
        ConvertTo-MarkdownTable @([pscustomobject]@{ Name = 'a|b'; State = 'Running' }) |
            Should -Match 'a\\\|b'
    }

    It 'handles an empty table' {
        ConvertTo-MarkdownTable @() | Should -Match 'None or unavailable'
    }
}

Describe 'Recommendation classification' {
    It 'rejects unknown classifications' {
        $parameters = @{
            Name = 'Test'; Classification = 'Maybe'; CurrentState = 'A'
            ProposedState = 'B'; Rationale = 'C'; ExpectedBenefit = 'D'
            Risk = 'E'; Dependencies = @('F'); ValidationCommand = 'G'
            RollbackApproach = 'H'; Confidence = 'Low'
        }
        { New-Recommendation @parameters } | Should -Throw '*classification*'
    }

    It 'marks required virtualization features DoNotChange' {
        $config = Import-WorkstationConfig (Join-Path $root 'config.psd1')
        $audit = [pscustomobject]@{
            Probes = @([pscustomobject]@{
                Name = 'PlatformFeatures'
                Data = @([pscustomobject]@{
                    FeatureName = 'VirtualMachinePlatform'; State = 'Enabled'
                })
            })
        }
        $plan = @(Get-WorkstationPlan $audit $config)
        ($plan | Where-Object Name -like '*VirtualMachinePlatform').Classification |
            Should -Be 'DoNotChange'
    }

    It 'does not claim an operational Store WSL feature must remain enabled' {
        $config = Import-WorkstationConfig (Join-Path $root 'config.psd1')
        $audit = [pscustomobject]@{
            Probes = @(
                [pscustomobject]@{
                    Name = 'PlatformFeatures'
                    Data = @([pscustomobject]@{
                        FeatureName = 'Microsoft-Windows-Subsystem-Linux'
                        State = 'Disabled'
                    })
                }
                [pscustomobject]@{
                    Name = 'WSL'
                    Data = @([pscustomobject]@{ Available = $true })
                }
            )
        }
        $item = Get-WorkstationPlan $audit $config |
            Where-Object Name -like '*Microsoft-Windows-Subsystem-Linux'
        $item.ProposedState | Should -Be 'Leave unchanged while WSL 2 remains operational'
    }
}
