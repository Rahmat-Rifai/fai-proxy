#Requires -Version 5.1
<#
.SYNOPSIS
    Installs or removes the scheduled monitoring task for the pool.

.DESCRIPTION
    Registers a Scheduled Task named "windows-proxy-pool-monitor" that
    runs scripts\monitor.ps1 -AutoRestart -Silent on a fixed interval
    (default: every 5 minutes). On failure it auto-restarts the failed
    instance(s) and records everything in run\pool-status.json /
    run\pool-status.log plus the Windows Application event log.

.PARAMETER Remove
    Unregister the scheduled monitoring task.

.PARAMETER TaskName
    Name of the scheduled task. Default: windows-proxy-pool-monitor.

.PARAMETER IntervalMinutes
    How often the monitor runs. Default: 5.

.PARAMETER Count
    Number of proxy instances. Default: 30.

.PARAMETER BasePort
    Port of the first instance. Default: 8001.

.PARAMETER BindAddress
    Interface the proxies listen on. Default: 127.0.0.1.

.PARAMETER NoAutoRestart
    Register the monitor WITHOUT -AutoRestart (monitor only, never
    restarts an instance). Use when you prefer a human to investigate.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\install-monitor.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\install-monitor.ps1 -Remove
#>
[CmdletBinding()]
param(
    [switch]$Remove,
    [string]$TaskName = "windows-proxy-pool-monitor",
    [int]$IntervalMinutes = 5,
    [int]$Count = 30,
    [int]$BasePort = 8001,
    [string]$BindAddress = "127.0.0.1",
    [switch]$NoAutoRestart
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$MonitorScript = Join-Path $Root "scripts\monitor.ps1"

if ($Remove) {
    Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue |
        Unregister-ScheduledTask -Confirm:$false
    Write-Host "Removed scheduled task '$TaskName' (if it existed)." -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $MonitorScript)) {
    Write-Host "monitor.ps1 not found: $MonitorScript" -ForegroundColor Red
    exit 1
}

$autoFlag = if ($NoAutoRestart) { "" } else { " -AutoRestart" }
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$MonitorScript`"$autoFlag -Silent -Count $Count -BasePort $BasePort -BindAddress `"$BindAddress`""

$action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArgs -WorkingDirectory $Root
$trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
            -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
            -RepetitionDuration (New-TimeSpan -Days 365)
$settings = New-ScheduledTaskSettingsSet `
            -StartWhenAvailable `
            -RestartCount 2 `
            -RestartInterval (New-TimeSpan -Minutes 1) `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries

Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue |
    Unregister-ScheduledTask -Confirm:$false

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description "Health monitor for the local HTTP proxy pool. Auto-restarts failed instances." |
    Out-Null

Write-Host ""
Write-Host "Scheduled task '$TaskName' installed." -ForegroundColor Green
Write-Host "  Interval: every $IntervalMinutes minute(s)"
Write-Host ("  AutoRestart: {0}" -f (-not $NoAutoRestart))
Write-Host "  Action : $taskArgs"
Write-Host ""
Write-Host "Output:"
Write-Host "  run\pool-status.json   (structured, machine-readable)"
Write-Host "  run\pool-status.log    (append-only summary lines)"
Write-Host "  Windows Event Log      (source: windows-proxy-pool)"
Write-Host ""
Write-Host "Verify with:  Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo"
Write-Host "Remove with:  scripts\install-monitor.ps1 -Remove"
