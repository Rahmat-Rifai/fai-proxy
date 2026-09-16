#Requires -Version 5.1
<#
.SYNOPSIS
    Cleans up old rotated logs and stale runtime files.

.DESCRIPTION
    The 3proxy log directive rotates logs per-instance (daily by default).
    Over time logs\ accumulates many rotated files. This script deletes
    rotated log files older than a retention period and removes stale PID
    files from run\ for proxies that are no longer running.

    Run this on a schedule (daily) or manually. It never touches active
    log files (files currently in use by a running proxy are skipped) and
    it never touches proxy-list.txt or credentials.

.PARAMETER RetentionDays
    Delete rotated log files older than this many days. Default: 30.

.PARAMETER MaxLogSizeMB
    Additionally: any rotated log file larger than this many MB is
    deleted regardless of age (a guard against one huge log). Default: 200.

.PARAMETER Count
    Number of proxy instances. Default: 30.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\cleanup-logs.ps1

.EXAMPLE
    # aggressive retention: keep 7 days only
    powershell -ExecutionPolicy Bypass -File scripts\cleanup-logs.ps1 -RetentionDays 7
#>
[CmdletBinding()]
param(
    [int]$RetentionDays = 30,
    [int]$MaxLogSizeMB = 200,
    [int]$Count = 30
)

$ErrorActionPreference = "Continue"

$Root   = Split-Path $PSScriptRoot -Parent
$LogsDir = Join-Path $Root "logs"
$RunDir  = Join-Path $Root "run"

if (-not (Test-Path $LogsDir)) {
    Write-Host "No logs directory: $LogsDir" -ForegroundColor Yellow
    exit 0
}

$cutoff = (Get-Date).AddDays(-$RetentionDays)
$sizeCutoff = $MaxLogSizeMB * 1MB

# --- 1. Rotated log files: any *.log.* (3proxy appends a rotation suffix -
#    .1, .2, or a date - whatever scheme the version uses, the glob catches it) ---
$removed = 0; $sizeRemoved = 0; $bytesFreed = 0
Get-ChildItem -Path $LogsDir -File -Filter "*.log.*" -ErrorAction SilentlyContinue | ForEach-Object {
    $delete = $false
    if ($_.LastWriteTime -lt $cutoff) {
        $delete = $true
        $removed++
    } elseif ($_.Length -gt $sizeCutoff) {
        $delete = $true
        $sizeRemoved++
    }
    if ($delete) {
        $bytesFreed += $_.Length
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
}

# --- 2. Stale PID files (process no longer alive) ---
$stalePids = 0
Get-ChildItem -Path $RunDir -File -Filter "*.pid" -ErrorAction SilentlyContinue | ForEach-Object {
    $pidVal = (Get-Content $_.FullName -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($pidVal) {
        if (-not (Get-Process -Id $pidVal -ErrorAction SilentlyContinue)) {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            $stalePids++
        }
    } else {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        $stalePids++
    }
}

$freedMB = [math]::Round($bytesFreed / 1MB, 2)
Write-Host ""
Write-Host "Cleanup complete." -ForegroundColor Green
Write-Host "  Rotated logs removed by age : $removed"
Write-Host "  Rotated logs removed by size: $sizeRemoved"
Write-Host "  Stale PID files removed     : $stalePids"
Write-Host "  Disk freed                  : ${freedMB} MB"
