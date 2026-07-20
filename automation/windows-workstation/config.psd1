@{
    RequiredWindowsFeatures = @(
        'Microsoft-Windows-Subsystem-Linux'
        'VirtualMachinePlatform'
    )

    ProtectedServices = @(
        'BFE'
        'mpssvc'
        'SecurityHealthService'
        'WinDefend'
        'wuauserv'
        'InstallService'
        'WSearch'
    )

    ApprovedStartupApplications = @()
    ReviewApplications = @()
    ReviewScheduledTasks = @()
    ApprovedAppxRemoval = @()

    PreferredPowerPolicy = @{
        MinimumProcessorStateAC = 5
        MinimumProcessorStateDC = 5
        DiskIdleTimeoutACMinutes = 20
        DiskIdleTimeoutDCMinutes = 10
    }

    SamplingDurationSeconds = 5
    TopProcessCount = 10
    EventLookbackHours = 24
}
