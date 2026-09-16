#Requires -Version 5.1
<#
.SYNOPSIS
    Interactive manager for the FAi Proxy Pool.

.DESCRIPTION
    Shows a menu and runs the pool scripts. The menu stays open after
    every operation so the user can run another one without opening a
    new PowerShell window. Sub-scripts run in child powershell.exe
    processes so the menu survives even if one of them exits.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\menu.ps1
#>
[CmdletBinding()]
param(
    [int]$Count = 30,
    [int]$BasePort = 8001,
    [string]$BindAddress = "127.0.0.1"
)

$Scripts = $PSScriptRoot
$poolParams = @("-Count", "$Count", "-BasePort", "$BasePort", "-BindAddress", "$BindAddress")
$countOnly  = @("-Count", "$Count")

function Invoke-PoolScript {
    param([string]$Name, [string[]]$Params)
    $path = Join-Path $Scripts $Name
    $all = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $path) + $Params
    & powershell.exe @all
}

function Show-Banner {
    Write-Host ""
    Write-Host "========================================"
    Write-Host " FAi Proxy Pool Manager"
    Write-Host "========================================"
    Write-Host ""
    Write-Host " [1] Start"
    Write-Host " [2] Stop"
    Write-Host " [3] Restart"
    Write-Host " [4] Status"
    Write-Host " [5] Test"
    Write-Host " [6] Export Proxy List"
    Write-Host " [7] Exit"
    Write-Host ""
}

do {
    Show-Banner
    $choice = Read-Host "Select"

    switch ($choice) {
        "1" { Invoke-PoolScript "run.ps1"            $poolParams }
        "2" { Invoke-PoolScript "stop.ps1"           $countOnly }
        "3" { Invoke-PoolScript "restart.ps1"        $poolParams }
        "4" { Invoke-PoolScript "status.ps1"         $poolParams }
        "5" { Invoke-PoolScript "test.ps1"           $poolParams }
        "6" { Invoke-PoolScript "export-proxies.ps1" $poolParams }
        "7" { Write-Host "Bye." }
        default { Write-Host "Invalid choice. Please select 1-7." -ForegroundColor Yellow }
    }

    if ($choice -ne "7") {
        Write-Host ""
        Read-Host "Press Enter to return to the menu"
    }
} while ($choice -ne "7")
