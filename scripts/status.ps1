#Requires -Version 5.1
<#
.SYNOPSIS
    Shows the status of every proxy instance.

.DESCRIPTION
    For each instance prints whether the process is running (from the
    PID file in run\) and whether the port is actually listening on the
    loopback interface.

.PARAMETER Count
    Number of proxy instances. Default: 30.

.PARAMETER BasePort
    Port of the first instance. Default: 8001.

.PARAMETER BindAddress
    Interface the proxies should listen on. Default: 127.0.0.1.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\status.ps1
#>
[CmdletBinding()]
param(
    [int]$Count = 30,
    [int]$BasePort = 8001,
    [string]$BindAddress = "127.0.0.1"
)

$Root   = Split-Path $PSScriptRoot -Parent
$RunDir = Join-Path $Root "run"

Write-Host ""
Write-Host ("{0,-10} {1,-7} {2,-8} {3,-9} {4}" -f "Instance", "Port", "PID", "Process", "Listening")
Write-Host ("{0,-10} {1,-7} {2,-8} {3,-9} {4}" -f "--------", "----", "---", "-------", "---------")

$running = 0
for ($i = 1; $i -le $Count; $i++) {
    $name    = "proxy{0:D2}" -f $i
    $port    = $BasePort + ($i - 1)
    $pidFile = Join-Path $RunDir "$name.pid"

    $pidVal = ""; $state = "STOPPED"; $listening = "NO"
    if (Test-Path $pidFile) {
        $pidVal = (Get-Content $pidFile | Select-Object -First 1).Trim()
        if ($pidVal -and (Get-Process -Id $pidVal -ErrorAction SilentlyContinue)) {
            $state = "RUNNING"
            $running++
        } else {
            $state = "STALE"
        }
    }
    if (Get-NetTCPConnection -LocalAddress $BindAddress -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
        $listening = "YES"
    }
    Write-Host ("{0,-10} {1,-7} {2,-8} {3,-9} {4}" -f $name, $port, $pidVal, $state, $listening)
}
Write-Host ""
Write-Host ("{0} of {1} proxies running." -f $running, $Count)
