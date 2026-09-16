#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the 3proxy binary used by windows-proxy-pool.

.DESCRIPTION
    Downloads the official 3proxy Windows build from GitHub releases,
    extracts it and places 3proxy.exe (plus companion DLLs) into bin\.
    Also creates the config\, logs\ and run\ directories.

.PARAMETER Version
    3proxy release version to download. Default: 0.9.8.

.PARAMETER Arch
    Binary architecture: x64, x86 or arm64. Auto-detected when empty.

.PARAMETER Force
    Re-download and re-extract even if bin\3proxy.exe already exists.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\install.ps1
#>
[CmdletBinding()]
param(
    [string]$Version = "0.9.8",
    [string]$Arch = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# --- Resolve project paths ---
$Root   = Split-Path $PSScriptRoot -Parent
$Tools  = Join-Path $Root "tools"
$Bin    = Join-Path $Root "bin"
$Config = Join-Path $Root "config"
$Logs   = Join-Path $Root "logs"
$Run    = Join-Path $Root "run"
$Exe    = Join-Path $Bin "3proxy.exe"

# --- Detect CPU architecture if not specified ---
if (-not $Arch) {
    $native = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $native = $env:PROCESSOR_ARCHITEW6432 }
    switch ($native) {
        "AMD64" { $Arch = "x64" }
        "ARM64" { $Arch = "arm64" }
        default { $Arch = "x86" }
    }
}

if (Test-Path $Exe) {
    if (-not $Force) {
        Write-Host "3proxy.exe already installed: $Exe" -ForegroundColor Green
        Write-Host "Use -Force to reinstall."
        exit 0
    }
    Write-Host "Reinstalling (Force) ..."
}

# Ensure directory layout
New-Item -ItemType Directory -Force -Path $Tools, $Bin, $Config, $Logs, $Run | Out-Null

# --- Download ---
$ZipName    = "3proxy-$Version-$Arch.zip"
$ZipPath    = Join-Path $Tools $ZipName
$ExtractDir = Join-Path $Tools "3proxy-$Version-$Arch"
$Url        = "https://github.com/3proxy/3proxy/releases/download/$Version/$ZipName"

if (Test-Path $ZipPath) {
    Write-Host "Using cached archive: $ZipPath"
} else {
    Write-Host "Downloading $Url ..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url -OutFile $ZipPath -UseBasicParsing
    Write-Host "Downloaded $ZipPath"
}

# --- Extract ---
if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
Write-Host "Extracting to $ExtractDir ..."
Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

$found = Get-ChildItem -Path $ExtractDir -Recurse -Filter "3proxy.exe" -File | Select-Object -First 1
if (-not $found) {
    throw "3proxy.exe was not found inside $ZipPath. The archive layout may have changed."
}

# Copy the exe and any DLLs sitting next to it (plugins / runtime libs)
$srcDir = $found.DirectoryName
Get-ChildItem -Path $srcDir -File | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $Bin -Force
}
Write-Host "Installed 3proxy from $srcDir into $Bin" -ForegroundColor Green

if (-not (Test-Path $Exe)) { throw "Installation failed: $Exe was not created." }

Write-Host ""
Write-Host "Installation complete." -ForegroundColor Green
Write-Host "Next steps:"
Write-Host "  1. powershell -ExecutionPolicy Bypass -File scripts\generate.ps1"
Write-Host "  2. powershell -ExecutionPolicy Bypass -File scripts\start.ps1"
Write-Host "  3. powershell -ExecutionPolicy Bypass -File scripts\test.ps1"
