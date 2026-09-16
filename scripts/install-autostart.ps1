#Requires -Version 5.1
<#
.SYNOPSIS
    Installs or removes a Windows Scheduled Task that auto-starts the
    proxy pool at user logon.

.DESCRIPTION
    Registers a Scheduled Task named "windows-proxy-pool" that runs
    scripts\start.ps1 at logon of the current user, so the pool comes
    back up automatically after a reboot / re-logon.

    Design choices:
      * Logon trigger (not "At startup"): the pool runs as the normal
        user so file permissions and proxies behave exactly like a
        manual start. No elevated/SYSTEM context required.
      * Runs start.ps1 (not run.ps1) so a slow health check never delays
        boot; run test.ps1 / monitor.ps1 separately on a schedule.
      * The task runs hidden (window style hidden) with the "Run only
        when user is logged on" setting.
      * If the pool is already running, start.ps1 simply skips it, so
        the task is idempotent.

.PARAMETER Remove
    Unregister the scheduled task instead of installing it.

.PARAMETER TaskName
    Name of the scheduled task. Default: windows-proxy-pool.

.PARAMETER Count
    Number of proxy instances. Default: 30.

.PARAMETER BasePort
    Port of the first instance. Default: 8001.

.PARAMETER BindAddress
    Interface the proxies listen on. Default: 127.0.0.1.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1 -Remove
#>
[CmdletBinding()]
param(
    [switch]$Remove,
    [string]$TaskName = "windows-proxy-pool",
    [int]$Count = 30,
    [int]$BasePort = 8001,
    [string]$BindAddress = "127.0.0.1"
)

$ErrorActionPreference = "Stop"
$Root      = Split-Path $PSScriptRoot -Parent
$StartScript = Join-Path $Root "scripts\start.ps1"

if ($Remove) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed scheduled task '$TaskName'." -ForegroundColor Green
    } else {
        Write-Host "No scheduled task named '$TaskName' was found." -ForegroundColor Yellow
    }
    exit 0
}

if (-not (Test-Path $StartScript)) {
    Write-Host "start.ps1 not found: $StartScript" -ForegroundColor Red
    exit 1
}

# Build the action: powershell -NoProfile -ExecutionPolicy Bypass -File start.ps1 ...
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$StartScript`" -Count $Count -BasePort $BasePort -BindAddress `"$BindAddress`""

$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArgs -WorkingDirectory $Root
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -RestartCount 2 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

# Unregister an old version of the task before registering the new one.
Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue |
    Unregister-ScheduledTask -Confirm:$false

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description "Starts the local HTTP proxy pool (127.0.0.1:8001-8030) at user logon." |
    Out-Null

Write-Host ""
Write-Host "Scheduled task '$TaskName' installed." -ForegroundColor Green
Write-Host "  Action : $taskArgs"
Write-Host "  Trigger: At logon of $env:USERNAME"
Write-Host "  Idempotent: if the pool is already running, start.ps1 skips it."
Write-Host ""
Write-Host "Verify with:  Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo"
Write-Host "Remove with:  scripts\install-autostart.ps1 -Remove"
