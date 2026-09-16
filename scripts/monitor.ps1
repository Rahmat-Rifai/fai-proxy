#Requires -Version 5.1
<#
.SYNOPSIS
    Production health monitor for the proxy pool.

.DESCRIPTION
    Checks every proxy instance: port listening, Basic Auth enforced,
    and egress working. Writes a structured status file to
    run\pool-status.json and creates a summary line in
    run\pool-status.log (append).

    Designed to be run from a Scheduled Task (see install-monitor.ps1).
    Exit code 0 = all healthy, 1 = one or more failures.

.PARAMETER Count
    Number of proxy instances. Default: 30.

.PARAMETER BasePort
    Port of the first instance. Default: 8001.

.PARAMETER BindAddress
    Interface the proxies listen on. Default: 127.0.0.1.

.PARAMETER TimeoutSec
    Max seconds per single request through a proxy. Default: 15.

.PARAMETER AutoRestart
    When a failed proxy is detected, automatically restart only that
    instance (not the whole pool). A restart is attempted up to 3 times
    with a 2-second pause between attempts. Instances that fail after 3
    retries are reported as CRITICAL.

.PARAMETER Silent
    Suppress the per-instance console output. Only print the summary
    line and any critical events. Useful when running from a scheduled
    task.

.PARAMETER StatusFile
    Path to the JSON status file. Default: run\pool-status.json.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\monitor.ps1

.EXAMPLE
    # Auto-restart failed instances + silent mode (for scheduled task)
    powershell -ExecutionPolicy Bypass -File scripts\monitor.ps1 -AutoRestart -Silent
#>
[CmdletBinding()]
param(
    [int]$Count = 30,
    [int]$BasePort = 8001,
    [string]$BindAddress = "127.0.0.1",
    [int]$TimeoutSec = 15,
    [switch]$AutoRestart,
    [switch]$Silent,
    [string]$StatusFile = ""
)

$ErrorActionPreference = "Continue"

$Root = Split-Path $PSScriptRoot -Parent
$RunDir = Join-Path $Root "run"
$ConfigDir = Join-Path $Root "config"
$Exe = Join-Path $Root "bin\3proxy.exe"
if (-not $StatusFile) { $StatusFile = Join-Path $RunDir "pool-status.json" }

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

# --- Load credentials (ordered: line i = instance i) ---
$CredentialsFile = Join-Path $Root "credentials.txt"
$creds = New-Object System.Collections.ArrayList
if (Test-Path $CredentialsFile) {
    foreach ($line in Get-Content $CredentialsFile) {
        $t = $line.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        $parts = $t -split ":", 2
        if ($parts.Count -eq 2) { [void]$creds.Add(@($parts[0].Trim(), $parts[1])) }
    }
}

# --- Public IP services ---
$ipServices = @("https://api.ipify.org", "https://ifconfig.me/ip", "http://api.ipify.org")

function Get-PublicIp([string]$proxyUrl) {
    foreach ($svc in $ipServices) {
        $body = & curl.exe -s --connect-timeout 8 --max-time $TimeoutSec -x $proxyUrl $svc 2>$null
        if ($LASTEXITCODE -eq 0 -and $body) {
            $ip = ($body -join " ").Trim()
            if ($ip -match "^(\d{1,3}\.){3}\d{1,3}$") { return $ip }
        }
    }
    return ""
}

function Restart-Instance([string]$name, [int]$port) {
    $conf = Join-Path $ConfigDir "$name.conf"
    if (-not (Test-Path $conf)) { return $false }
    $pidFile = Join-Path $RunDir "$name.pid"
    if (Test-Path $pidFile) {
        $oldPid = (Get-Content $pidFile | Select-Object -First 1).Trim()
        if ($oldPid) { Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500 }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }
    $argLine = '"{0}"' -f $conf
    $p = Start-Process -FilePath $Exe -ArgumentList $argLine -WorkingDirectory $Root -WindowStyle Hidden -PassThru
    $pidVal = ""
    for ($w = 0; $w -lt 25; $w++) {
        if (Test-Path $pidFile) {
            $pidVal = (Get-Content $pidFile | Select-Object -First 1).Trim()
            if ($pidVal -and (Get-Process -Id $pidVal -ErrorAction SilentlyContinue)) { break }
        }
        if ($p.HasExited) { break }
        Start-Sleep -Milliseconds 200
    }
    return [bool]($pidVal -and (Get-Process -Id $pidVal -ErrorAction SilentlyContinue))
}

# --- Check each instance ---
$timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
$healthy = @()
$unhealthy = @()
$critical = @()

if (-not $Silent) {
    Write-Host ""
    Write-Host "Monitor $timestamp" -ForegroundColor Cyan
    Write-Host ("{0,-6} {1,-7} {2,-6} {3,-7} {4}" -f "Proxy", "Port", "Auth", "Status", "Public IP")
    Write-Host ("{0,-6} {1,-7} {2,-6} {3,-7} {4}" -f "-----", "----", "----", "------", "---------")
}

for ($i = 1; $i -le $Count; $i++) {
    $name = "proxy{0:D2}" -f $i
    $port = $BasePort + ($i - 1)
    $user = ""; $pass = ""
    if ($creds.Count -ge $i) { $user = $creds[$i-1][0]; $pass = $creds[$i-1][1] }

    $instanceHealthy = $false
    $authOk = $false
    $ip = ""

    # 1) Port listening check
    $listening = [bool](Get-NetTCPConnection -LocalAddress $BindAddress -LocalPort $port -State Listen -ErrorAction SilentlyContinue)

    # 2) Process alive check
    $pidFile = Join-Path $RunDir "$name.pid"
    $pidAlive = $false
    if (Test-Path $pidFile) {
        $pidVal = (Get-Content $pidFile | Select-Object -First 1).Trim()
        if ($pidVal -and (Get-Process -Id $pidVal -ErrorAction SilentlyContinue)) { $pidAlive = $true }
    }

    if ($listening -and $pidAlive -and $user) {
        # 3) Auth check: request WITHOUT credentials must return 407
        $code = & curl.exe -s -o NUL -w "%{http_code}" --connect-timeout 5 --max-time 10 -x "http://$BindAddress`:$port" "http://api.ipify.org" 2>$null
        if ($code -eq "407") { $authOk = $true }

        # 4) Egress check: request WITH credentials must return public IP
        if ($authOk) {
            $proxyUrl = "http://${user}:${pass}@${BindAddress}:${port}"
            $ip = Get-PublicIp $proxyUrl
            if ($ip) { $instanceHealthy = $true }
        }
    }

    if (-not $Silent) {
        $authStr = if ($authOk) { "OK" } else { "NO" }
        $statusStr = if ($instanceHealthy) { "OK" } else { "FAIL" }
        $color = if ($instanceHealthy) { "Green" } else { "Red" }
        Write-Host ("{0,-6} {1,-7} {2,-6} {3,-7} {4}" -f $i, $port, $authStr, $statusStr, $ip) -ForegroundColor $color
    }

    if ($instanceHealthy) {
        $healthy += $name
    } elseif ($AutoRestart) {
        # Try restart up to 3 times
        $restored = $false
        for ($r = 1; $r -le 3; $r++) {
            Write-Host ("    [WARN] {0} attempt {1}/3 ..." -f $name, $r) -ForegroundColor Yellow
            if (Restart-Instance $name $port) {
                Write-Host ("    [OK] {0} restored after restart" -f $name) -ForegroundColor Green

                # Log the restart event
                $logMsg = "[$timestamp] $name auto-restarted (attempt $r/3)"
                Add-Content -Path (Join-Path $RunDir "pool-status.log") -Value $logMsg
                try {
                    New-EventLog -LogName Application -Source "windows-proxy-pool" -ErrorAction SilentlyContinue | Out-Null
                    Write-EventLog -LogName Application -Source "windows-proxy-pool" -EventId 1001 `
                        -EntryType Warning -Message $logMsg -ErrorAction SilentlyContinue
                } catch { }

                $healthy += $name
                $restored = $true
                break
            }
            Start-Sleep -Seconds 2
        }
        if (-not $restored) {
            $unhealthy += $name
            $critical += $name
            $logMsg = "[$timestamp] $name CRITICAL - failed to restart after 3 attempts"
            Add-Content -Path (Join-Path $RunDir "pool-status.log") -Value $logMsg
            try {
                New-EventLog -LogName Application -Source "windows-proxy-pool" -ErrorAction SilentlyContinue | Out-Null
                Write-EventLog -LogName Application -Source "windows-proxy-pool" -EventId 1002 `
                    -EntryType Error -Message $logMsg -ErrorAction SilentlyContinue
            } catch { }
        }
    } else {
        $unhealthy += $name
        $critical += $name
    }
}

# --- Summary ---
$healthyCount = $healthy.Count
$unhealthyCount = $unhealthy.Count
$criticalCount = $critical.Count

$summaryLine = "[$timestamp] Healthy: $healthyCount / $Count | Unhealthy: $unhealthyCount | Critical: $criticalCount"
if (-not $Silent) {
    Write-Host ""
    Write-Host $summaryLine
    if ($criticalCount -gt 0) {
        Write-Host ("Critical: {0}" -f ($critical -join ", ")) -ForegroundColor Red
    }
}

# --- Write JSON status file ---
$statusObj = @{
    timestamp = $timestamp
    count = $Count
    healthy = $healthyCount
    unhealthy = $unhealthyCount
    critical = $criticalCount
    healthy_instances = $healthy
    unhealthy_instances = $unhealthy
    critical_instances = $critical
    summary = $summaryLine
}
$statusObj | ConvertTo-Json -Compress | Out-File -FilePath $StatusFile -Encoding Ascii -Force

# --- Append to status log ---
Add-Content -Path (Join-Path $RunDir "pool-status.log") -Value $summaryLine

# --- Write event log for critical failures ---
if ($criticalCount -gt 0 -and -not $AutoRestart) {
    $msg = "[$timestamp] $criticalCount proxy(es) failed: $($critical -join ', ')"
    try {
        New-EventLog -LogName Application -Source "windows-proxy-pool" -ErrorAction SilentlyContinue | Out-Null
        Write-EventLog -LogName Application -Source "windows-proxy-pool" -EventId 1003 `
            -EntryType Error -Message $msg -ErrorAction SilentlyContinue
    } catch { }
}

# --- Exit code for scheduled task / alerting ---
if ($criticalCount -gt 0) { exit 1 }
exit 0