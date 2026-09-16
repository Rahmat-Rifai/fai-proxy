#Requires -Version 5.1
<#
.SYNOPSIS
    Stops all proxy instances.

.DESCRIPTION
    Stops each instance by reading its PID file from run\. If the PID
    file is missing or stale it falls back to matching running
    3proxy.exe processes by command line (the config path). Stale PID
    files are removed.

.PARAMETER Count
    Number of proxy instances. Default: 30.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\stop.ps1
#>
[CmdletBinding()]
param([int]$Count = 30)

$ErrorActionPreference = "Continue"   # never abort on a single failure

$Root      = Split-Path $PSScriptRoot -Parent
$RunDir    = Join-Path $Root "run"
$ConfigDir = Join-Path $Root "config"

$stopped = 0; $notRunning = 0
for ($i = 1; $i -le $Count; $i++) {
    $name    = "proxy{0:D2}" -f $i
    $pidFile = Join-Path $RunDir "$name.pid"
    $conf    = Join-Path $ConfigDir "$name.conf"

    $targetPid = ""
    $proc = $null

    if (Test-Path $pidFile) {
        $targetPid = (Get-Content $pidFile | Select-Object -First 1).Trim()
        if ($targetPid) { $proc = Get-Process -Id $targetPid -ErrorAction SilentlyContinue }
    }
    if (-not $proc) {
        $cim = Get-CimInstance Win32_Process -Filter "Name='3proxy.exe'" -ErrorAction SilentlyContinue |
               Where-Object { $_.CommandLine -and $_.CommandLine -like "*$name.conf*" } |
               Select-Object -First 1
        if ($cim) {
            $targetPid = [string]$cim.ProcessId
            $proc = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
        }
    }

    if ($proc) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 200
        if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) {
            Write-Host ("{0} could not be stopped (PID {1})" -f $name, $proc.Id) -ForegroundColor Red
        } else {
            Write-Host ("{0} stopped (PID {1})" -f $name, $proc.Id)
            $stopped++
        }
    } else {
        $notRunning++
    }
    if (Test-Path $pidFile) { Remove-Item $pidFile -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host ("Stopped: {0}   Not running: {1}" -f $stopped, $notRunning)
