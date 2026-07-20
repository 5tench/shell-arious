Set-StrictMode -Version Latest

function Import-WorkstationConfig {
    <#
    .SYNOPSIS
    Loads and validates workstation policy.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file not found: $Path"
    }
    $config = Import-PowerShellDataFile -LiteralPath $Path
    $required = @(
        'RequiredWindowsFeatures', 'ProtectedServices',
        'ApprovedStartupApplications', 'ReviewApplications',
        'ReviewScheduledTasks', 'ApprovedAppxRemoval',
        'PreferredPowerPolicy', 'SamplingDurationSeconds',
        'TopProcessCount', 'EventLookbackHours'
    )
    foreach ($key in $required) {
        if (-not $config.ContainsKey($key)) {
            throw "Configuration is missing '$key'."
        }
    }
    foreach ($key in 'SamplingDurationSeconds', 'TopProcessCount', 'EventLookbackHours') {
        if ($config[$key] -isnot [int] -or $config[$key] -lt 1) {
            throw "Configuration '$key' must be a positive integer."
        }
    }
    foreach ($key in 'RequiredWindowsFeatures', 'ProtectedServices',
        'ApprovedStartupApplications', 'ReviewApplications',
        'ReviewScheduledTasks', 'ApprovedAppxRemoval') {
        if ($config[$key] -isnot [array]) {
            throw "Configuration '$key' must be an array."
        }
    }
    $powerKeys = @(
        'MinimumProcessorStateAC', 'MinimumProcessorStateDC',
        'DiskIdleTimeoutACMinutes', 'DiskIdleTimeoutDCMinutes'
    )
    foreach ($key in $powerKeys) {
        if (-not $config.PreferredPowerPolicy.ContainsKey($key) -or
            $config.PreferredPowerPolicy[$key] -isnot [int] -or
            $config.PreferredPowerPolicy[$key] -lt 0) {
            throw "PreferredPowerPolicy '$key' must be a non-negative integer."
        }
    }
    return $config
}

function Invoke-AuditProbe {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )
    try {
        [pscustomobject]@{ Name = $Name; Status = 'Collected'; Data = @(& $ScriptBlock); Error = $null }
    }
    catch {
        [pscustomobject]@{ Name = $Name; Status = 'Unavailable'; Data = @(); Error = $_.Exception.Message }
    }
}

function ConvertTo-RegistryApplication {
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.PSObject.Properties.Name -contains 'DisplayName' -and
            -not [string]::IsNullOrWhiteSpace([string]$_.DisplayName)
        } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
        Sort-Object DisplayName -Unique
}

function Get-ProcessSnapshot {
    foreach ($process in Get-Process) {
        try {
            $cpu = $process.TotalProcessorTime.TotalSeconds
            $workingSet = $process.WorkingSet64
        }
        catch {
            # Protected and short-lived processes can disappear or reject property access.
            continue
        }
        [pscustomobject]@{
            Name = $process.ProcessName
            Id = $process.Id
            CPU = [math]::Round($cpu, 3)
            WorkingSet64 = $workingSet
        }
    }
}

function Get-PowerCfgText {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $text = & powercfg.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($text -join [Environment]::NewLine) }
    return ($text -join [Environment]::NewLine)
}

function Get-OptionalRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    $item = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
    if ($null -ne $item -and $item.PSObject.Properties.Name -contains $Name) {
        return $item.$Name
    }
    return $null
}

function Get-FeatureState {
    $names = @(
        'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform',
        'Microsoft-Hyper-V-All', 'HypervisorPlatform'
    )
    foreach ($name in $names) {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction SilentlyContinue
        [pscustomobject]@{
            FeatureName = $name
            State = if ($feature) { [string]$feature.State } else { 'NotPresent' }
        }
    }
}

function Get-WslState {
    $status = & wsl.exe --status 2>&1
    $statusExit = $LASTEXITCODE
    $version = & wsl.exe --version 2>&1
    $versionExit = $LASTEXITCODE
    $distributions = & wsl.exe --list --verbose 2>&1
    [pscustomobject]@{
        Available = ($statusExit -eq 0 -or $versionExit -eq 0)
        Status = ($status -join "`n")
        Version = ($version -join "`n")
        Distributions = ($distributions -join "`n")
    }
}

function Get-WorkstationAudit {
    <#
    .SYNOPSIS
    Collects a read-only Windows workstation inventory.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    if ($env:OS -ne 'Windows_NT') {
        throw 'Audit mode is supported only on Windows.'
    }
    $now = Get-Date
    $os = Get-CimInstance Win32_OperatingSystem
    $samples = @()
    $sampleCount = [Math]::Max(1, $Config.SamplingDurationSeconds)
    for ($index = 0; $index -lt $sampleCount; $index++) {
        $cpu = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
        $currentOs = Get-CimInstance Win32_OperatingSystem
        $used = $currentOs.TotalVisibleMemorySize - $currentOs.FreePhysicalMemory
        $samples += [pscustomobject]@{
            Timestamp = (Get-Date).ToString('o')
            CpuPercent = [math]::Round([double]$cpu, 1)
            MemoryPercent = [math]::Round(100 * $used / $currentOs.TotalVisibleMemorySize, 1)
        }
        if ($index -lt ($sampleCount - 1)) { Start-Sleep -Seconds 1 }
    }

    $probes = @(
        Invoke-AuditProbe 'Power' {
            [pscustomobject]@{
                ActivePlan = Get-PowerCfgText '/getactivescheme'
                ProcessorMinimumAC = Get-PowerCfgText @('/query', 'SCHEME_CURRENT', 'SUB_PROCESSOR', 'PROCTHROTTLEMIN')
                DiskIdle = Get-PowerCfgText @('/query', 'SCHEME_CURRENT', 'SUB_DISK', 'DISKIDLE')
            }
        }
        Invoke-AuditProbe 'Processes' {
            $processes = @(Get-ProcessSnapshot)
            $processes | Sort-Object CPU -Descending |
                Select-Object -First $Config.TopProcessCount @{
                    Name = 'RankedBy'; Expression = { 'CPU' }
                }, Name, Id, CPU, WorkingSet64
            $processes | Sort-Object WorkingSet64 -Descending |
                Select-Object -First $Config.TopProcessCount @{
                    Name = 'RankedBy'; Expression = { 'WorkingSet' }
                }, Name, Id, CPU, WorkingSet64
        }
        Invoke-AuditProbe 'StartupApplications' {
            Get-CimInstance Win32_StartupCommand |
                Select-Object Name, Command, Location, User
        }
        Invoke-AuditProbe 'Services' {
            Get-CimInstance Win32_Service |
                Select-Object Name, DisplayName, State, StartMode, PathName
        }
        Invoke-AuditProbe 'ScheduledTasks' {
            Get-ScheduledTask | Where-Object TaskPath -NotLike '\Microsoft\*' |
                Select-Object TaskName, TaskPath, State, Author
        }
        Invoke-AuditProbe 'OptionalFeatures' {
            Get-WindowsOptionalFeature -Online |
                Where-Object State -eq 'Enabled' |
                Select-Object FeatureName, State
        }
        Invoke-AuditProbe 'PlatformFeatures' { Get-FeatureState }
        Invoke-AuditProbe 'Applications' { ConvertTo-RegistryApplication }
        Invoke-AuditProbe 'AppxPackages' {
            Get-AppxPackage | Select-Object Name, PackageFullName, Publisher, IsFramework
        }
        Invoke-AuditProbe 'WSL' { Get-WslState }
        Invoke-AuditProbe 'Security' {
            $deviceGuard = Get-CimInstance -Namespace root/Microsoft/Windows/DeviceGuard -ClassName Win32_DeviceGuard
            [pscustomobject]@{
                MemoryIntegrityRunning = 2 -in $deviceGuard.SecurityServicesRunning
                Defender = Get-MpComputerStatus |
                    Select-Object AntivirusEnabled, RealTimeProtectionEnabled, BehaviorMonitorEnabled
                Firewall = Get-NetFirewallProfile |
                    Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
            }
        }
        Invoke-AuditProbe 'SearchAndDeliveryOptimization' {
            [pscustomobject]@{
                WindowsSearch = Get-Service WSearch | Select-Object Name, Status, StartType
                DeliveryOptimization = if (Get-Command Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue) {
                    Get-DeliveryOptimizationStatus
                } else { $null }
                DeliveryOptimizationPolicy = Get-ItemProperty -Path (
                    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
                ) -ErrorAction SilentlyContinue
                GameMode = Get-OptionalRegistryValue -Path (
                    'HKCU:\Software\Microsoft\GameBar'
                ) -Name AutoGameModeEnabled
            }
        }
        Invoke-AuditProbe 'Storage' {
            [pscustomobject]@{
                PageFiles = Get-CimInstance Win32_PageFileUsage |
                    Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage
                AutomaticPageFile = (Get-CimInstance Win32_ComputerSystem).AutomaticManagedPagefile
                Volumes = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
                    Select-Object DeviceID, VolumeName, Size, FreeSpace
                Trim = (& fsutil.exe behavior query DisableDeleteNotify 2>&1) -join "`n"
            }
        }
        Invoke-AuditProbe 'PendingReboot' {
            [pscustomobject]@{
                ComponentBasedServicing = Test-Path (
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
                )
                WindowsUpdate = Test-Path (
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
                )
                PendingFileRename = $null -ne (Get-OptionalRegistryValue -Path (
                    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
                ) -Name PendingFileRenameOperations)
            }
        }
        Invoke-AuditProbe 'DeviceErrors' {
            Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' |
                Select-Object Name, PNPDeviceID, ConfigManagerErrorCode, Status
        }
        Invoke-AuditProbe 'RecentEvents' {
            $start = (Get-Date).AddHours(-$Config.EventLookbackHours)
            Get-WinEvent -FilterHashtable @{
                LogName = 'System'
                StartTime = $start
                Level = 1, 2
            } -ErrorAction Stop | Select-Object -First 100 TimeCreated, Id, ProviderName, LevelDisplayName, Message
        }
    )

    [pscustomobject]@{
        SchemaVersion = 1
        CollectedAt = $now.ToString('o')
        Computer = [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            Edition = $os.Caption
            Version = $os.Version
            Build = $os.BuildNumber
            UptimeSeconds = [math]::Round(($now - $os.LastBootUpTime).TotalSeconds)
        }
        UtilizationSamples = $samples
        Probes = $probes
    }
}

function Get-ProbeData {
    param([Parameter(Mandatory)]$Audit, [Parameter(Mandatory)][string]$Name)
    return @($Audit.Probes | Where-Object Name -eq $Name | Select-Object -ExpandProperty Data)
}

function ConvertTo-MarkdownTable {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$InputObject
    )
    if ($InputObject.Count -eq 0) { return '_None or unavailable._' }
    $properties = @($InputObject[0].PSObject.Properties.Name)
    $lines = @(
        '| ' + ($properties -join ' | ') + ' |'
        '| ' + (($properties | ForEach-Object { '---' }) -join ' | ') + ' |'
    )
    foreach ($item in $InputObject) {
        $values = foreach ($property in $properties) {
            ([string]$item.$property).Replace('|', '\|').Replace("`r", '').Replace("`n", '<br>')
        }
        $lines += '| ' + ($values -join ' | ') + ' |'
    }
    return ($lines -join [Environment]::NewLine)
}

function Export-AuditReport {
    <#
    .SYNOPSIS
    Writes JSON and readable Markdown audit reports.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Audit,
        [Parameter(Mandatory)][string]$OutputPath
    )
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        $null = New-Item -ItemType Directory -Path $OutputPath
    }
    $stamp = Get-Date -Date $Audit.CollectedAt -Format 'yyyyMMdd-HHmmss'
    $jsonPath = Join-Path $OutputPath "audit-$stamp.json"
    $markdownPath = Join-Path $OutputPath "audit-$stamp.md"
    $Audit | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $probeSummary = $Audit.Probes | Select-Object Name, Status, Error
    $detailSections = foreach ($probe in $Audit.Probes) {
        "## $($probe.Name)"
        ''
        if ($probe.Status -eq 'Collected') {
            ConvertTo-MarkdownTable @($probe.Data)
        }
        else {
            "_Unavailable: $($probe.Error)_"
        }
        ''
    }
    $markdown = @"
# Workstation audit

Collected: $($Audit.CollectedAt)

## System

$(ConvertTo-MarkdownTable @($Audit.Computer))

## Utilization samples

$(ConvertTo-MarkdownTable @($Audit.UtilizationSamples))

## Collection status

$(ConvertTo-MarkdownTable @($probeSummary))

$($detailSections -join [Environment]::NewLine)

The JSON companion contains the complete inventory. Inventory reports may contain names,
paths, user names, and device identifiers; keep them local.
"@
    Set-Content -LiteralPath $markdownPath -Value $markdown -Encoding UTF8
    [pscustomobject]@{ Json = $jsonPath; Markdown = $markdownPath }
}

function Read-AuditReport {
    <#
    .SYNOPSIS
    Reads a JSON audit report.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $audit = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($audit.SchemaVersion -ne 1 -or -not $audit.Probes) {
        throw "Unsupported or invalid audit report: $Path"
    }
    return $audit
}

Export-ModuleMember -Function Import-WorkstationConfig, Get-WorkstationAudit,
    Export-AuditReport, Read-AuditReport, Get-ProbeData, ConvertTo-MarkdownTable
