#Requires -Version 5.1
<#
.SYNOPSIS
    Restarts all proxy instances (stop, then start).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\restart.ps1
#>
[CmdletBinding()]
param(
    [int]$Count = 30,
    [int]$BasePort = 8001,
    [string]$BindAddress = "127.0.0.1"
)

Write-Host "=== Stopping all proxies ===" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "stop.ps1") -Count $Count

Write-Host ""
Write-Host "=== Starting all proxies ===" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "start.ps1") -Count $Count -BasePort $BasePort -BindAddress $BindAddress

# Refresh the exported proxy list after the restart (idempotent).
Write-Host ""
Write-Host "=== Exporting proxy list ===" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "export-proxies.ps1") -Count $Count -BasePort $BasePort -BindAddress $BindAddress
