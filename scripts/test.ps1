#Requires -Version 5.1
<#
.SYNOPSIS
    Tests every proxy instance through curl.

.DESCRIPTION
    For each instance it verifies:
      1. Auth    - a request WITHOUT credentials must be rejected (HTTP 407),
                   proving Basic Auth is enforced.
      2. Status  - a request WITH credentials must succeed, and the body is
                   the public (egress) IP seen by the target service.
    Prints a table: Proxy | Port | Auth | Status | Public IP.

.PARAMETER Count
    Number of proxy instances. Default: 30.

.PARAMETER BasePort
    Port of the first instance. Default: 8001.

.PARAMETER BindAddress
    Interface the proxies listen on. Default: 127.0.0.1.

.PARAMETER TimeoutSec
    Max seconds per request through a proxy. Default: 20.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\test.ps1
#>
[CmdletBinding()]
param(
    [int]$Count = 30,
    [int]$BasePort = 8001,
    [string]$BindAddress = "127.0.0.1",
    [int]$TimeoutSec = 20
)

$ErrorActionPreference = "Continue"

$Root = Split-Path $PSScriptRoot -Parent
$CredentialsFile = Join-Path $Root "credentials.txt"

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    Write-Host "curl.exe not found. Windows 10/11 ships curl.exe - open a new shell or install it." -ForegroundColor Red
    exit 1
}

# Load credentials as an ordered list. Line i belongs to instance i
# (port BasePort + i - 1). Do NOT look users up by instance name: the
# default pattern is proxy1..proxy30 while instances are named proxy01..proxy30.
$creds = New-Object System.Collections.ArrayList
if (Test-Path $CredentialsFile) {
    foreach ($line in Get-Content $CredentialsFile) {
        $t = $line.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        $parts = $t -split ":", 2
        if ($parts.Count -eq 2) { [void]$creds.Add(@($parts[0].Trim(), $parts[1])) }
    }
} else {
    Write-Host "credentials.txt not found at $CredentialsFile - run scripts\generate.ps1 first." -ForegroundColor Red
    exit 1
}

# Public IP services, tried in order until one returns a valid IPv4
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

Write-Host ""
Write-Host ("{0,-6} {1,-7} {2,-6} {3,-7} {4}" -f "Proxy", "Port", "Auth", "Status", "Public IP")
Write-Host ("{0,-6} {1,-7} {2,-6} {3,-7} {4}" -f "-----", "----", "----", "------", "---------")

$okCount = 0
for ($i = 1; $i -le $Count; $i++) {
    $name = "proxy{0:D2}" -f $i
    $port = $BasePort + ($i - 1)
    $user = ""; $pass = ""
    if ($creds.Count -ge $i) { $user = $creds[$i-1][0]; $pass = $creds[$i-1][1] }

    # 1) Auth check: request WITHOUT credentials must be rejected (407).
    #    Uses a plain HTTP URL: for https URLs curl reports 000 when the
    #    proxy rejects the CONNECT with 407, so the code would be missed.
    $noAuthUrl = "http://$BindAddress`:$port"
    $code = & curl.exe -s -o NUL -w "%{http_code}" --connect-timeout 5 --max-time 10 -x $noAuthUrl "http://api.ipify.org" 2>$null
    $auth = "NO"
    if ($code -eq "407") { $auth = "OK" }

    # 2) Proxy check: request WITH credentials must return the public IP
    $proxyUrl = "http://${user}:${pass}@${BindAddress}:${port}"
    $ip = Get-PublicIp $proxyUrl
    $status = "FAIL"
    if ($ip) { $status = "OK"; $okCount++ }

    Write-Host ("{0,-6} {1,-7} {2,-6} {3,-7} {4}" -f $i, $port, $auth, $status, $ip)
}

Write-Host ""
Write-Host ("{0} of {1} proxies passed." -f $okCount, $Count)
if ($okCount -lt $Count) {
    Write-Host "Check the per-instance logs under logs\ for failing instances." -ForegroundColor Yellow
}
