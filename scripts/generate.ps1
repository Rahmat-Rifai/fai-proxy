#Requires -Version 5.1
<#
.SYNOPSIS
    Generates per-instance 3proxy configuration for the proxy pool.

.DESCRIPTION
    Reads credentials.txt (one "username:password" per line) and writes:
      - config\proxy01.conf ... proxy30.conf   (3proxy config, absolute paths)
      - config\proxy01.users ... proxy30.users (per-instance user:CL:pass file)
    If credentials.txt does not exist it is created with the default
    pattern proxy1:pass1 .. proxy30:pass30.
    File permissions on credential-bearing files are restricted to the
    current user via icacls (best effort).

.PARAMETER Count
    Number of proxy instances. Default: 30.

.PARAMETER BasePort
    Port of the first instance. Default: 8001 (ports 8001..8030 for 30 instances).

.PARAMETER BindAddress
    Interface all proxies listen on. Default: 127.0.0.1 (loopback only).

.PARAMETER CredentialsFile
    Path to the credentials file. Default: <project>\credentials.txt

.PARAMETER RandomPass
    Regenerate credentials.txt with a fresh random password for EVERY
    instance, then regenerate configs + user files from it. Uses a safe
    alphanumeric charset (no : @ / whitespace) so passwords stay valid in
    URL form and in export-proxies.ps1. WARNING: existing credentials are
    overwritten and all running proxies must be restarted afterwards.

.PARAMETER PassLength
    Length of each random password when -RandomPass is used. Default: 16.

.PARAMETER LogRotation
    Log rotation interval appended to the 3proxy log directive. One of:
    "" (none, keep a single stable file), "c" (minutely), "H" (hourly),
    "D" (daily), "W" (weekly), "M" (monthly), "Y" (annually).
    Default: D (daily).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\generate.ps1

.EXAMPLE
    # Rotate passwords to fresh random ones (then restart the pool)
    powershell -ExecutionPolicy Bypass -File scripts\generate.ps1 -RandomPass
#>
[CmdletBinding()]
param(
    [int]$Count = 30,
    [int]$BasePort = 8001,
    [string]$BindAddress = "127.0.0.1",
    [string]$CredentialsFile = "",
    [switch]$RandomPass,
    [int]$PassLength = 16,
    [ValidateSet("", "c", "H", "D", "W", "M", "Y")]
    [string]$LogRotation = "D"
)

$ErrorActionPreference = "Stop"

$Root      = Split-Path $PSScriptRoot -Parent
$ConfigDir = Join-Path $Root "config"
$LogsDir   = Join-Path $Root "logs"
$RunDir    = Join-Path $Root "run"
if (-not $CredentialsFile) { $CredentialsFile = Join-Path $Root "credentials.txt" }

New-Item -ItemType Directory -Force -Path $ConfigDir, $LogsDir, $RunDir | Out-Null

# --- Random password generator (safe for URL form: no : @ / whitespace) ---
# Uses a crypto RNG to avoid the weak default pattern (proxy1:pass1 ...).
function New-SafePassword([int]$Length) {
    $chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789" # no 0/O/1/l/I, no symbols
    $bytes = New-Object byte[] $Length
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $sb = New-Object System.Text.StringBuilder $Length
    foreach ($b in $bytes) { [void]$sb.Append($chars[$b % $chars.Length]) }
    $sb.ToString()
}

# --- Load or create credentials ---
$creds = New-Object System.Collections.ArrayList
if ($RandomPass) {
    Write-Host "-RandomPass: generating fresh random credentials for $Count instances..." -ForegroundColor Cyan
    $lines = New-Object System.Collections.ArrayList
    for ($i = 1; $i -le $Count; $i++) {
        $u = "proxy${i}"
        $p = New-SafePassword $PassLength
        [void]$lines.Add("${u}:${p}")
        [void]$creds.Add(@($u, $p))
    }
    Set-Content -Path $CredentialsFile -Value $lines -Encoding Ascii
    Write-Host "Overwrote $CredentialsFile with $Count random credentials." -ForegroundColor Green
} elseif (Test-Path $CredentialsFile) {
    foreach ($line in Get-Content $CredentialsFile) {
        $t = $line.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        $parts = $t -split ":", 2
        if ($parts.Count -ne 2 -or $parts[0].Trim() -eq "") {
            throw "Invalid line in $CredentialsFile : '$line' (expected: username:password)"
        }
        [void]$creds.Add(@($parts[0].Trim(), $parts[1]))
    }
} else {
    Write-Host "credentials.txt not found. Creating default credentials: $CredentialsFile" -ForegroundColor Yellow
    $lines = New-Object System.Collections.ArrayList
    for ($i = 1; $i -le $Count; $i++) {
        [void]$lines.Add("proxy${i}:pass${i}")
    }
    Set-Content -Path $CredentialsFile -Value $lines -Encoding Ascii
    foreach ($l in $lines) {
        $parts = $l -split ":", 2
        [void]$creds.Add(@($parts[0], $parts[1]))
    }
}
if ($creds.Count -lt $Count) {
    throw "credentials.txt has $($creds.Count) entries but $Count instances are required. Add more lines or lower -Count."
}

# --- Generate per-instance config ---
$generated = New-Object System.Collections.ArrayList
for ($i = 1; $i -le $Count; $i++) {
    $name      = "proxy{0:D2}" -f $i
    $port      = $BasePort + ($i - 1)
    $user      = $creds[$i-1][0]
    $pass      = $creds[$i-1][1]
    $confPath  = Join-Path $ConfigDir "$name.conf"
    $usersPath = Join-Path $ConfigDir "$name.users"
    $logPath   = Join-Path $LogsDir "$name.log"
    $pidPath   = Join-Path $RunDir "$name.pid"

    # Per-instance credentials file (referenced from the config via $include)
    Set-Content -Path $usersPath -Value "${user}:CL:${pass}" -Encoding Ascii -NoNewline

    # Log line: append the rotation interval only when one was requested.
    # (A trailing empty token would confuse 3proxy's config parser.)
    if ($LogRotation) { $logLine = "log `"$logPath`" $LogRotation" }
    else              { $logLine = "log `"$logPath`"" }

    $cfg = @"
# windows-proxy-pool - $name - $BindAddress`:$port
# Generated by scripts\generate.ps1 from credentials.txt - DO NOT EDIT MANUALLY.
# Re-run generate.ps1 after changing credentials or moving this project folder.

# --- Authentication: Basic Auth (username/password) ---
auth strong
users `$"$usersPath"
allow *
deny *

# --- Logging (per-instance log file, daily rotation by default) ---
# Rotation interval ($LogRotation): "" = single stable file, D = daily,
# H = hourly, W = weekly, M = monthly, Y = annually.
$logLine
logformat "- +_L%t.%.  %N.%p %E %U %C:%c %R:%r %O %I %h %T"

# --- Runtime ---
pidfile "$pidPath"

# --- HTTP proxy service ---
# -i $BindAddress   : listen on loopback interface ONLY
# -p $port          : listen port
# -olSO_EXCLUSIVEADDRUSE : Windows: prevent another process from binding this port
proxy -p$port -i$BindAddress -olSO_EXCLUSIVEADDRUSE
"@
    Set-Content -Path $confPath -Value $cfg -Encoding Ascii
    [void]$generated.Add(@($name, $port, $user, $confPath))
}

# --- Restrict access to credential-bearing files (best effort) ---
$secureFiles = New-Object System.Collections.ArrayList
[void]$secureFiles.Add($CredentialsFile)
Get-ChildItem -Path $ConfigDir -Filter "*.users" -File | ForEach-Object { [void]$secureFiles.Add($_.FullName) }
Get-ChildItem -Path $ConfigDir -Filter "*.conf" -File  | ForEach-Object { [void]$secureFiles.Add($_.FullName) }
foreach ($f in $secureFiles) {
    try {
        & icacls $f /inheritance:r /grant:r "$($env:USERNAME):F" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning "icacls returned $LASTEXITCODE for $f" }
    } catch {
        Write-Warning "Could not restrict permissions on $f : $($_.Exception.Message)"
    }
}

# --- Summary ---
Write-Host ""
Write-Host ("{0,-10} {1,-7} {2,-12} {3}" -f "Instance", "Port", "User", "Config")
Write-Host ("{0,-10} {1,-7} {2,-12} {3}" -f "--------", "----", "----", "------")
foreach ($g in $generated) {
    Write-Host ("{0,-10} {1,-7} {2,-12} {3}" -f $g[0], $g[1], $g[2], $g[3])
}
Write-Host ""
Write-Host "Generated $($generated.Count) proxy configs in $ConfigDir" -ForegroundColor Green
Write-Host "Credentials file: $CredentialsFile  (permissions restricted to $env:USERNAME)"
Write-Host ("Log rotation: {0}" -f ($(if ($LogRotation) { "every $LogRotation" } else { "none (single file per instance)" })))
if ($RandomPass) {
    Write-Host "RandomPass mode: restart the pool to apply new credentials:" -ForegroundColor Yellow
    Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\restart.ps1"
} else {
    Write-Host "Next: powershell -ExecutionPolicy Bypass -File scripts\start.ps1"
}
