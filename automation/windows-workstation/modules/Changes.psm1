Set-StrictMode -Version Latest

function New-Recommendation {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Classification,
        [Parameter(Mandatory)][string]$CurrentState,
        [Parameter(Mandatory)][string]$ProposedState,
        [Parameter(Mandatory)][string]$Rationale,
        [Parameter(Mandatory)][string]$ExpectedBenefit,
        [Parameter(Mandatory)][string]$Risk,
        [Parameter(Mandatory)][string[]]$Dependencies,
        [Parameter(Mandatory)][string]$ValidationCommand,
        [Parameter(Mandatory)][string]$RollbackApproach,
        [Parameter(Mandatory)][string]$Confidence
    )
    if ($Classification -notin 'Safe', 'Review', 'DoNotChange') {
        throw "Invalid recommendation classification: $Classification"
    }
    [pscustomobject]@{
        Name = $Name
        Classification = $Classification
        CurrentState = $CurrentState
        ProposedState = $ProposedState
        Rationale = $Rationale
        ExpectedBenefit = $ExpectedBenefit
        Risk = $Risk
        Dependencies = $Dependencies
        ValidationCommand = $ValidationCommand
        RollbackApproach = $RollbackApproach
        Confidence = $Confidence
    }
}

function Get-Probe {
    param([Parameter(Mandatory)]$Audit, [Parameter(Mandatory)][string]$Name)
    return @($Audit.Probes | Where-Object Name -eq $Name | Select-Object -ExpandProperty Data)
}

function Get-WorkstationPlan {
    <#
    .SYNOPSIS
    Creates evidence-based recommendations from an audit without applying changes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Audit,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $results = @()
    $features = @(Get-Probe $Audit 'PlatformFeatures')
    $wsl = @(Get-Probe $Audit 'WSL') | Select-Object -First 1
    foreach ($name in $Config.RequiredWindowsFeatures) {
        $feature = $features | Where-Object FeatureName -eq $name | Select-Object -First 1
        $state = if ($feature) { [string]$feature.State } else { 'Unknown' }
        $proposedState = 'Remain enabled'
        $rationale = 'Workstation policy requires this virtualization capability for WSL 2.'
        if ($name -eq 'Microsoft-Windows-Subsystem-Linux' -and
            $state -eq 'Disabled' -and $wsl -and $wsl.Available) {
            $proposedState = 'Leave unchanged while WSL 2 remains operational'
            $rationale = 'WSL 2 is operational through the current Store and virtualization configuration; do not change the legacy optional component without a dependency reason.'
        }
        $results += New-Recommendation -Name "Protect Windows feature: $name" `
            -Classification DoNotChange -CurrentState $state -ProposedState $proposedState `
            -Rationale $rationale `
            -ExpectedBenefit 'Preserves the supported development environment.' `
            -Risk 'Disabling it can prevent WSL 2 and dependent virtualization workloads from starting.' `
            -Dependencies @('WSL 2', 'Virtual Machine Platform') `
            -ValidationCommand "Get-WindowsOptionalFeature -Online -FeatureName '$name'" `
            -RollbackApproach 'Re-enable the feature and restart if a separate change disables it.' `
            -Confidence High
    }

    foreach ($serviceName in $Config.ProtectedServices) {
        $service = @(Get-Probe $Audit 'Services') |
            Where-Object Name -eq $serviceName | Select-Object -First 1
        if ($service) {
            $results += New-Recommendation -Name "Protect service: $serviceName" `
                -Classification DoNotChange `
                -CurrentState "$($service.State), startup $($service.StartMode)" `
                -ProposedState 'Keep the existing supported configuration' `
                -Rationale 'Policy protects security, update, Store, firewall, or search functionality.' `
                -ExpectedBenefit 'Avoids breaking a protected Windows capability.' `
                -Risk 'Disabling may reduce security or operating-system functionality.' `
                -Dependencies @($service.DisplayName) `
                -ValidationCommand "Get-CimInstance Win32_Service -Filter `"Name='$serviceName'`"" `
                -RollbackApproach 'Restore the prior startup type and start the service.' `
                -Confidence High
        }
    }

    $security = @(Get-Probe $Audit 'Security') | Select-Object -First 1
    $securityControls = @(
        @{
            Name = 'Memory Integrity (HVCI)'
            State = if ($security) { [string]$security.MemoryIntegrityRunning } else { 'Unknown' }
            Command = 'Get-CimInstance -Namespace root/Microsoft/Windows/DeviceGuard -ClassName Win32_DeviceGuard'
        }
        @{
            Name = 'Microsoft Defender'
            State = if ($security -and $security.Defender) {
                "Antivirus=$($security.Defender.AntivirusEnabled), real-time=$($security.Defender.RealTimeProtectionEnabled)"
            } else { 'Unknown' }
            Command = 'Get-MpComputerStatus'
        }
        @{
            Name = 'Windows Firewall'
            State = if ($security -and $security.Firewall) {
                (($security.Firewall | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ', ')
            } else { 'Unknown' }
            Command = 'Get-NetFirewallProfile'
        }
    )
    foreach ($control in $securityControls) {
        $results += New-Recommendation -Name "Protect security control: $($control.Name)" `
            -Classification DoNotChange -CurrentState $control.State `
            -ProposedState 'Keep enabled' `
            -Rationale 'Workstation policy requires the Windows security control.' `
            -ExpectedBenefit 'Preserves defense-in-depth and the supported security posture.' `
            -Risk 'Disabling reduces protection and may violate enterprise policy.' `
            -Dependencies @('Windows security policy') -ValidationCommand $control.Command `
            -RollbackApproach 'Restore the prior enabled policy and verify the control reports healthy.' `
            -Confidence High
    }

    $power = @(Get-Probe $Audit 'Power') | Select-Object -First 1
    if ($power -and $power.ActivePlan -match 'High performance|Ultimate Performance') {
        $results += New-Recommendation -Name 'Review active high-performance power plan' `
            -Classification Review -CurrentState $power.ActivePlan.Trim() `
            -ProposedState 'Use Balanced unless a measured workload requires the current plan' `
            -Rationale 'The audit found a performance-oriented plan that can increase idle power use.' `
            -ExpectedBenefit 'Lower idle power and heat with normal dynamic performance scaling.' `
            -Risk 'Latency-sensitive workloads may behave differently; measure before changing.' `
            -Dependencies @('Gaming benchmarks', 'Container and build workload measurements') `
            -ValidationCommand 'powercfg.exe /getactivescheme' `
            -RollbackApproach 'Select the recorded power scheme again with powercfg /setactive.' `
            -Confidence Medium
    }

    $startup = @(Get-Probe $Audit 'StartupApplications')
    foreach ($candidate in $Config.ReviewApplications) {
        foreach ($match in @($startup | Where-Object Name -Like $candidate)) {
            if ($match.Name -notin $Config.ApprovedStartupApplications) {
                $results += New-Recommendation -Name "Review startup application: $($match.Name)" `
                    -Classification Review -CurrentState "Starts from $($match.Location)" `
                    -ProposedState 'Disable startup only if the application is not needed at sign-in' `
                    -Rationale 'The application matches an explicit policy review candidate.' `
                    -ExpectedBenefit 'May reduce sign-in work and background memory use.' `
                    -Risk 'Background updates, notifications, or hardware integration may stop.' `
                    -Dependencies @('Confirm application owner and purpose') `
                    -ValidationCommand 'Get-CimInstance Win32_StartupCommand' `
                    -RollbackApproach 'Re-enable the original startup entry.' -Confidence Medium
            }
        }
    }

    $tasks = @(Get-Probe $Audit 'ScheduledTasks')
    foreach ($candidate in $Config.ReviewScheduledTasks) {
        foreach ($match in @($tasks | Where-Object { "$($_.TaskPath)$($_.TaskName)" -like $candidate })) {
            $results += New-Recommendation -Name "Review scheduled task: $($match.TaskPath)$($match.TaskName)" `
                -Classification Review -CurrentState "$($match.State)" `
                -ProposedState 'Disable only after confirming the task is redundant telemetry or update work' `
                -Rationale 'The task matches an explicit policy review candidate.' `
                -ExpectedBenefit 'May avoid unnecessary periodic background work.' `
                -Risk 'Vendor updates or device support functions may stop.' `
                -Dependencies @('Inspect task actions and triggers', 'Confirm vendor utility requirements') `
                -ValidationCommand "Get-ScheduledTask -TaskName '$($match.TaskName)'" `
                -RollbackApproach 'Re-enable the scheduled task.' -Confidence Medium
        }
    }

    $storage = @(Get-Probe $Audit 'Storage') | Select-Object -First 1
    if ($storage -and $storage.AutomaticPageFile) {
        $results += New-Recommendation -Name 'Keep system-managed page file' `
            -Classification DoNotChange -CurrentState 'System managed' `
            -ProposedState 'Remain system managed' `
            -Rationale 'No audit evidence justifies overriding Windows memory management.' `
            -ExpectedBenefit 'Preserves crash dumps and commit-limit flexibility.' `
            -Risk 'Manual limits can cause allocation failures or prevent complete dumps.' `
            -Dependencies @('Virtual memory', 'Crash dump configuration') `
            -ValidationCommand 'Get-CimInstance Win32_ComputerSystem | Select-Object AutomaticManagedPagefile' `
            -RollbackApproach 'Restore AutomaticManagedPagefile to true.' -Confidence High
    }
    return $results
}

function ConvertTo-PlanMarkdown {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Recommendations
    )
    if ($Recommendations.Count -eq 0) {
        return "# Workstation plan`n`nNo recommendations were justified by the audit and policy."
    }
    $lines = @('# Workstation plan', '', 'No system changes were made.', '')
    foreach ($item in $Recommendations) {
        $lines += @(
            "## $($item.Name)", '',
            "- Classification: $($item.Classification)",
            "- Current state: $($item.CurrentState)",
            "- Proposed state: $($item.ProposedState)",
            "- Rationale: $($item.Rationale)",
            "- Expected benefit: $($item.ExpectedBenefit)",
            "- Risk: $($item.Risk)",
            "- Dependencies: $($item.Dependencies -join ', ')",
            "- Validation command: ``$($item.ValidationCommand)``",
            "- Rollback: $($item.RollbackApproach)",
            "- Confidence: $($item.Confidence)", ''
        )
    }
    return ($lines -join [Environment]::NewLine)
}

function Export-PlanReport {
    <#
    .SYNOPSIS
    Writes JSON and Markdown recommendation reports.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Recommendations,
        [Parameter(Mandatory)][string]$OutputPath
    )
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        $null = New-Item -ItemType Directory -Path $OutputPath
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $jsonPath = Join-Path $OutputPath "plan-$stamp.json"
    $markdownPath = Join-Path $OutputPath "plan-$stamp.md"
    $report = [pscustomobject]@{
        SchemaVersion = 1
        GeneratedAt = (Get-Date).ToString('o')
        Recommendations = @($Recommendations)
    }
    $report | ConvertTo-Json -Depth 7 |
        Set-Content -LiteralPath $jsonPath -Encoding UTF8
    ConvertTo-PlanMarkdown $Recommendations |
        Set-Content -LiteralPath $markdownPath -Encoding UTF8
    [pscustomobject]@{ Json = $jsonPath; Markdown = $markdownPath }
}

Export-ModuleMember -Function New-Recommendation, Get-WorkstationPlan,
    ConvertTo-PlanMarkdown, Export-PlanReport
