#Requires -Version 5.1
<#
.SYNOPSIS
    Exports a proxy list file from the currently running instances.

.DESCRIPTION
    Reads credentials.txt (line i = instance i) and each instance's
    config (port/bind), checks which instances are actually RUNNING and
    LISTENING on 127.0.0.1, and writes one line per proxy to
    proxy-list.txt in the format:
        protocol://user:pass@host:port
    The file is overwritten on every run. Only running + listening
    proxies are included; lines are validated and de-duplicated.
    NOTE: the output file contains plaintext credentials - do not share
    it and do not commit it to Git.

.PARAMETER Count
    Number of proxy instances. Default: 30.

.PARAMETER BasePort
    Port of the first instance. Default: 8001.

.PARAMETER BindAddress
    Interface the proxies should listen on. Default: 127.0.0.1.

.PARAMETER OutputFile
    Output file path. Default: <project>\proxy-list.txt

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\export-proxies.ps1
#>
[CmdletBinding()]
param(
    [int]$Count = 30,
    [int]$BasePort = 8001,
    [string]$BindAddress = "127.0.0.1",
    [string]$OutputFile = ""
)

$ErrorActionPreference = "Continue"

$Root = Split-Path $PSScriptRoot -Parent
if (-not $OutputFile) { $OutputFile = Join-Path $Root "proxy-list.txt" }
$ConfigDir         = Join-Path $Root "config"
$RunDir            = Join-Path $Root "run"
$CredentialsFile   = Join-Path $Root "credentials.txt"

# --- Load credentials (ordered: line i = instance i) ---
$creds = New-Object System.Collections.ArrayList
if (Test-Path $CredentialsFile) {
    foreach ($line in Get-Content $CredentialsFile) {
        $t = $line.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        $parts = $t -split ":", 2
        if ($parts.Count -eq 2) { [void]$creds.Add(@($parts[0].Trim(), $parts[1])) }
    }
}

Write-Host "Exporting running proxies..." -ForegroundColor Cyan
Write-Host ""

$lines = New-Object System.Collections.ArrayList
$seen  = @{}      # de-duplication set (full line and port)
$okCount = 0

for ($i = 1; $i -le $Count; $i++) {
    $name = "proxy{0:D2}" -f $i

    # --- read port/bind from the instance config (source of truth) ---
    $port = $BasePort + ($i - 1)
    $bind = $BindAddress
    $conf = Join-Path $ConfigDir "$name.conf"
    if (Test-Path $conf) {
        $raw = Get-Content $conf -Raw -ErrorAction SilentlyContinue
        if ($raw -match "proxy\s+-p(\d+)\s+-i([0-9.]+)") {
            $port = [int]$Matches[1]
            $bind = $Matches[2]
        }
    }

    $skipReason = ""

    # --- running check (pid file + process alive) ---
    $running = $false
    $pidFile = Join-Path $RunDir "$name.pid"
    if (Test-Path $pidFile) {
        $pidVal = (Get-Content $pidFile | Select-Object -First 1).Trim()
        if ($pidVal -and (Get-Process -Id $pidVal -ErrorAction SilentlyContinue)) { $running = $true }
    }
    if (-not $running) { $skipReason = "process not running" }

    # --- listening check ---
    $listening = $false
    if ($running) {
        if (Get-NetTCPConnection -LocalAddress $bind -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
            $listening = $true
        } else {
            $skipReason = "not listening on $bind`:$port"
        }
    }

    if (-not $listening) {
        Write-Host ("[SKIP] {0}  ({1})" -f $port, $skipReason) -ForegroundColor Yellow
        continue
    }

    # --- credentials for this instance (line i) ---
    $user = ""; $pass = ""
    if ($creds.Count -ge $i) { $user = $creds[$i-1][0]; $pass = $creds[$i-1][1] }
    if (-not $user) {
        Write-Host ("[SKIP] {0}  (no credentials found for line {1})" -f $port, $i) -ForegroundColor Yellow
        continue
    }

    $line = "http://${user}:${pass}@${bind}:${port}"

    # --- validate format ---
    if ($line -notmatch "^http://[^:@/\s]+:[^:@/\s]*@[0-9.]+:\d+$") {
        Write-Host ("[SKIP] {0}  (invalid format - credentials contain special characters)" -f $port) -ForegroundColor Yellow
        continue
    }
    if ($seen.ContainsKey($line)) { continue }          # duplicate line
    if ($seen.ContainsKey("port:$port")) { continue }   # duplicate port

    $seen[$line] = $true
    $seen["port:$port"] = $true
    [void]$lines.Add($line)
    Write-Host ("[OK] {0}" -f $port) -ForegroundColor Green
    $okCount++
}

# --- overwrite output file ---
$dir = Split-Path $OutputFile -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
Set-Content -Path $OutputFile -Value $lines -Encoding Ascii

Write-Host ""
Write-Host ("{0}/{1} proxies exported." -f $okCount, $Count)
Write-Host ""
Write-Host "Output:"
Write-Host $OutputFile
Write-Host ""
Write-Host "WARNING: this file contains plaintext credentials. Do not share it or commit it to Git." -ForegroundColor Yellow
