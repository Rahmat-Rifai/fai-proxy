#Requires -Version 5.1
<#
.SYNOPSIS
    Rotates all proxy credentials to fresh random passwords.

.DESCRIPTION
    Production-safe credential rotation:
      1. Stops the whole pool (scripts\stop.ps1) so no proxy serves with
         the old credentials while they are being replaced.
      2. Regenerates credentials.txt with fresh random passwords and
         rewrites config\*.conf + config\*.users (scripts\generate.ps1
         -RandomPass).
      3. Restarts the pool (scripts\start.ps1) and exports the proxy list.
      4. Runs a full health test (scripts\test.ps1).

    The old proxy-list.txt is deleted before regeneration so a stale list
    with old credentials can never be served.

.PARAMETER Count
    Number of proxy instances. Default: 30.

.PARAMETER BasePort
    Port of the first instance. Default: 8001.

.PARAMETER BindAddress
    Interface the proxies listen on. Default: 127.0.0.1.

.PARAMETER PassLength
    Length of each new random password. Default: 16.

.PARAMETER SkipTest
    Skip the final full test (faster rotation; run test.ps1 later).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\rotate-credentials.ps1
#>
[CmdletBinding()]
param(
    [int]$Count = 30,
    [int]$BasePort = 8001,
    [string]$BindAddress = "127.0.0.1",
    [int]$PassLength = 16,
    [switch]$SkipTest
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$ProxyList = Join-Path $Root "proxy-list.txt"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Rotating proxy credentials" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# --- 1. Stop the pool so old credentials are never served mid-rotation ---
Write-Host ""
Write-Host "[1/4] Stopping pool..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "stop.ps1") -Count $Count

# Remove the stale proxy list so a file with old credentials never lingers.
if (Test-Path $ProxyList) {
    Remove-Item $ProxyList -Force
    Write-Host "Removed stale $ProxyList" -ForegroundColor Yellow
}

# --- 2. Generate fresh random credentials + rewrite configs ---
Write-Host ""
Write-Host "[2/4] Generating random credentials..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "generate.ps1") -Count $Count -BasePort $BasePort -BindAddress $BindAddress -RandomPass -PassLength $PassLength

# --- 3. Start the pool with the new credentials ---
Write-Host ""
Write-Host "[3/4] Starting pool with new credentials..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "start.ps1") -Count $Count -BasePort $BasePort -BindAddress $BindAddress

# --- 4. Full health test ---
if ($SkipTest) {
    Write-Host ""
    Write-Host "[4/4] Skipping test (-SkipTest). Run scripts\test.ps1 to verify." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "[4/4] Testing pool..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "test.ps1") -Count $Count -BasePort $BasePort -BindAddress $BindAddress
}

Write-Host ""
Write-Host "Rotation complete." -ForegroundColor Green
Write-Host "New credentials are in $Root\credentials.txt (restricted permissions)."
Write-Host "Update any downstream consumers that hardcoded old proxy passwords." -ForegroundColor Yellow
