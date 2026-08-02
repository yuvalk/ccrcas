#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes the ClaudeCode Windows service.
.DESCRIPTION
    Stops the service if running, deletes the service registration,
    and optionally removes the install directory.
.PARAMETER InstallDir
    The install directory to optionally clean up. Defaults to C:\ClaudeCode.
.PARAMETER RemoveFiles
    If specified, deletes the entire install directory including config and logs.
#>

param(
    [string]$InstallDir = "C:\ClaudeCode",
    [switch]$RemoveFiles
)

$ServiceName = "ClaudeCode"

Write-Host "=== Claude Code Service Uninstaller ===" -ForegroundColor Cyan
Write-Host ""

# Check if service exists
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "Service '$ServiceName' not found. Nothing to uninstall." -ForegroundColor Yellow
    if ($RemoveFiles -and (Test-Path $InstallDir)) {
        Write-Host "Removing install directory: $InstallDir" -ForegroundColor Yellow
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Host "[OK] Directory removed" -ForegroundColor Green
    }
    exit 0
}

# Stop the service if running
if ($service.Status -eq 'Running') {
    Write-Host "Stopping service '$ServiceName' ..." -ForegroundColor Yellow
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 2
    Write-Host "[OK] Service stopped" -ForegroundColor Green
}

# Delete the service
Write-Host "Removing service '$ServiceName' ..." -ForegroundColor Yellow
$result = & sc.exe delete $ServiceName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to delete service: $result"
    exit 1
}
Write-Host "[OK] Service removed" -ForegroundColor Green

# Optionally remove files
if ($RemoveFiles) {
    if (Test-Path $InstallDir) {
        Write-Host "Removing install directory: $InstallDir ..." -ForegroundColor Yellow
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Host "[OK] Directory removed" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "Install directory preserved: $InstallDir" -ForegroundColor DarkYellow
    Write-Host "To also remove files, re-run with -RemoveFiles" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "Uninstall complete." -ForegroundColor Cyan
