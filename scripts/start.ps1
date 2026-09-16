#Requires -Version 5.1
<#
.SYNOPSIS
    Starts all proxy instances as separate background processes.

.DESCRIPTION
    Starts one 3proxy.exe process per instance (proxy01..proxy30), each
    with its own config file. 3proxy writes its own PID file to run\
    (pidfile directive). Instances that are already running are skipped.

.PARAMETER Count
    Number of proxy instances. Default: 30.

.PARAMETER BasePort
    Port of the first instance. Default: 8001.

.PARAMETER BindAddress
    Interface the proxies listen on (informational). Default: 127.0.0.1.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\start.ps1
#>
[CmdletBinding()]
param(
    [int]$Count = 30,
    [int]$BasePort = 8001,
    [string]$BindAddress = "127.0.0.1"
)

$ErrorActionPreference = "Stop"

$Root      = Split-Path $PSScriptRoot -Parent
$Bin       = Join-Path $Root "bin"
$ConfigDir = Join-Path $Root "config"
$LogsDir   = Join-Path $Root "logs"
$RunDir    = Join-Path $Root "run"
$Exe       = Join-Path $Bin "3proxy.exe"

if (-not (Test-Path $Exe)) {
    Write-Host "3proxy.exe not found in $Bin. Run scripts\install.ps1 first." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path (Join-Path $ConfigDir "proxy01.conf"))) {
    Write-Host "Config files not found. Running scripts\generate.ps1 first ..." -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot "generate.ps1")
}
New-Item -ItemType Directory -Force -Path $RunDir, $LogsDir | Out-Null

$started = 0; $already = 0; $failed = 0
for ($i = 1; $i -le $Count; $i++) {
    $name    = "proxy{0:D2}" -f $i
    $port    = $BasePort + ($i - 1)
    $conf    = Join-Path $ConfigDir "$name.conf"
    $pidFile = Join-Path $RunDir "$name.pid"

    # Skip if already running (a stale pid file is cleaned up)
    if (Test-Path $pidFile) {
        $oldPid = (Get-Content $pidFile | Select-Object -First 1).Trim()
        if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
            Write-Host ("{0} already running (PID {1}) - skipped" -f $name, $oldPid)
            $already++
            continue
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }

    $argLine = '"{0}"' -f $conf
    $p = Start-Process -FilePath $Exe -ArgumentList $argLine -WorkingDirectory $Root -WindowStyle Hidden -PassThru

    # Wait for 3proxy to write its pid file (and still be alive)
    $pidVal = ""
    for ($w = 0; $w -lt 25; $w++) {
        if (Test-Path $pidFile) {
            $pidVal = (Get-Content $pidFile | Select-Object -First 1).Trim()
            if ($pidVal -and (Get-Process -Id $pidVal -ErrorAction SilentlyContinue)) { break }
        }
        if ($p.HasExited) { break }
        Start-Sleep -Milliseconds 200
    }

    if ($pidVal -and (Get-Process -Id $pidVal -ErrorAction SilentlyContinue)) {
        Write-Host ("{0} started on {1}:{2} (PID {3})" -f $name, $BindAddress, $port, $pidVal)
        $started++
    } else {
        Write-Host ("{0} FAILED to start" -f $name) -ForegroundColor Red
        $log = Join-Path $LogsDir "$name.log"
        if (Test-Path $log) {
            Get-Content $log -Tail 5 | ForEach-Object { Write-Host ("    {0}" -f $_) -ForegroundColor DarkGray }
        }
        $failed++
    }
}

Write-Host ""
Write-Host ("Started: {0}   Already running: {1}   Failed: {2}" -f $started, $already, $failed)

# Auto-export the proxy list (only running + listening proxies are included,
# so instances that failed to start are never exported).
Write-Host ""
& (Join-Path $PSScriptRoot "export-proxies.ps1") -Count $Count -BasePort $BasePort -BindAddress $BindAddress

Write-Host ""
Write-Host "Verify with scripts\status.ps1, then scripts\test.ps1"
