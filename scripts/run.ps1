#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the whole proxy pool in one go.

.DESCRIPTION
    1. Checks that 3proxy.exe is installed.
    2. Starts all proxy instances (scripts\start.ps1).
    3. Waits until ports 8001..8030 are listening.
    4. Health-checks every proxy (Basic Auth enforced + egress works).
    5. Exports the proxy list (scripts\export-proxies.ps1).
    6. Prints a summary.

.PARAMETER Count
    Number of proxy instances. Default: 30.

.PARAMETER BasePort
    Port of the first instance. Default: 8001.

.PARAMETER BindAddress
    Interface the proxies listen on. Default: 127.0.0.1.

.PARAMETER WaitSeconds
    How long to wait for all ports to listen. Default: 30.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\run.ps1
#>
[CmdletBinding()]
param(
    [int]$Count = 30,
    [int]$BasePort = 8001,
    [string]$BindAddress = "127.0.0.1",
    [int]$WaitSeconds = 30
)

$ErrorActionPreference = "Continue"

$Root = Split-Path $PSScriptRoot -Parent
$Bin  = Join-Path $Root "bin"
$Exe  = Join-Path $Bin "3proxy.exe"
$RunDir = Join-Path $Root "run"
$CredentialsFile = Join-Path $Root "credentials.txt"

Write-Host ""
Write-Host "========================================"
Write-Host "        FAi Proxy Pool"
Write-Host "========================================"
Write-Host ""

# --- 1. Check that 3proxy is available ---
if (-not (Test-Path $Exe)) {
    Write-Host "3proxy.exe not found in $Bin" -ForegroundColor Red
    Write-Host "Run: powershell -ExecutionPolicy Bypass -File scripts\install.ps1" -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path $CredentialsFile)) {
    Write-Host "credentials.txt not found. Run scripts\generate.ps1 first." -ForegroundColor Red
    exit 1
}

# --- 2. Start all proxies (start.ps1 already exports the proxy list) ---
Write-Host ("Starting {0} proxies..." -f $Count)
& (Join-Path $PSScriptRoot "start.ps1") -Count $Count -BasePort $BasePort -BindAddress $BindAddress

# --- 3. Wait until all ports are listening ---
Write-Host ""
Write-Host "Waiting for ports to listen..."
$deadline = (Get-Date).AddSeconds($WaitSeconds)
$listeningPorts = @()
while ((Get-Date) -lt $deadline) {
    $listeningPorts = @()
    for ($i = 1; $i -le $Count; $i++) {
        $port = $BasePort + ($i - 1)
        if (Get-NetTCPConnection -LocalAddress $BindAddress -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
            $listeningPorts += $port
        }
    }
    if ($listeningPorts.Count -ge $Count) { break }
    Start-Sleep -Milliseconds 500
}

# Running count (pid file + process alive)
$runningCount = 0
for ($i = 1; $i -le $Count; $i++) {
    $pidFile = Join-Path $RunDir ("proxy{0:D2}.pid" -f $i)
    if (Test-Path $pidFile) {
        $pidVal = (Get-Content $pidFile | Select-Object -First 1).Trim()
        if ($pidVal -and (Get-Process -Id $pidVal -ErrorAction SilentlyContinue)) { $runningCount++ }
    }
}
$listeningCount = $listeningPorts.Count

# --- 4. Health check: Basic Auth enforced (407 without creds) + egress OK (200 with creds) ---
Write-Host ""
Write-Host "Health check..."
$creds = New-Object System.Collections.ArrayList
if (Test-Path $CredentialsFile) {
    foreach ($line in Get-Content $CredentialsFile) {
        $t = $line.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        $parts = $t -split ":", 2
        if ($parts.Count -eq 2) { [void]$creds.Add(@($parts[0].Trim(), $parts[1])) }
    }
}

$healthyCount = 0
for ($i = 1; $i -le $Count; $i++) {
    $port = $BasePort + ($i - 1)
    $user = ""; $pass = ""
    if ($creds.Count -ge $i) { $user = $creds[$i-1][0]; $pass = $creds[$i-1][1] }

    $healthy = $false
    if ($user) {
        $noAuthCode = & curl.exe -s -o NUL -w "%{http_code}" --connect-timeout 5 --max-time 10 -x "http://$BindAddress`:$port" "http://api.ipify.org" 2>$null
        if ($noAuthCode -eq "407") {
            $okCode = & curl.exe -s -o NUL -w "%{http_code}" --connect-timeout 5 --max-time 15 -x "http://${user}:${pass}@${BindAddress}:${port}" "http://api.ipify.org" 2>$null
            if ($okCode -eq "200") { $healthy = $true }
        }
    }
    if ($healthy) { $healthyCount++; Write-Host ("[OK]   {0}" -f $port) -ForegroundColor Green }
    else          { Write-Host ("[FAIL] {0}" -f $port) -ForegroundColor Red }
}

# --- 5. Export the proxy list ---
Write-Host ""
& (Join-Path $PSScriptRoot "export-proxies.ps1") -Count $Count -BasePort $BasePort -BindAddress $BindAddress

# --- 6. Summary ---
Write-Host ""
Write-Host ("Running : {0}/{1}" -f $runningCount, $Count)
Write-Host ("Listening: {0}/{1}" -f $listeningCount, $Count)
Write-Host ("Healthy : {0}/{1}" -f $healthyCount, $Count)
Write-Host ""
Write-Host "Proxy list exported:"
Write-Host (Join-Path $Root "proxy-list.txt")
Write-Host ""
Write-Host "Proxy range:"
Write-Host ("{0}:{1} - {0}:{2}" -f $BindAddress, $BasePort, ($BasePort + $Count - 1))
Write-Host ""
Write-Host "Done."
