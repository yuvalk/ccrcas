#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs Claude Code as a Windows service using SrvAny.
.DESCRIPTION
    Creates a Windows service named "ClaudeCode" that runs Claude Code
    via SrvAny from the Windows Server 2003 Resource Kit.
.PARAMETER SrvAnyPath
    Full path to srvany.exe. Defaults to searching common locations.
.PARAMETER ServiceUser
    Local user account to run the service as (e.g., ".\claude-svc").
    If omitted, runs as LocalSystem (not recommended).
.PARAMETER ServicePassword
    Password for the service user account.
.PARAMETER InstallDir
    Directory where the service files and config will live.
    Defaults to C:\ClaudeCode.
.PARAMETER ClaudeExePath
    Full path to the claude.exe CLI binary.
    If omitted, attempts to find it in PATH or common install locations.
.PARAMETER ClaudeArgs
    Arguments to pass to claude.exe. Defaults to "--print" for non-interactive mode.
#>

param(
    [string]$SrvAnyPath,
    [string]$ServiceUser,
    [string]$ServicePassword,
    [string]$InstallDir = "C:\ClaudeCode",
    [string]$ClaudeExePath,
    [string]$ClaudeArgs = ""
)

$ServiceName = "ClaudeCode"
$ServiceDisplayName = "Claude Code Service"
$ServiceDescription = "Runs Anthropic Claude Code CLI as a Windows service"

function Find-SrvAny {
    $searchPaths = @(
        "$PSScriptRoot\srvany.exe",
        "C:\Program Files (x86)\Windows Resource Kits\Tools\srvany.exe",
        "C:\Program Files\Windows Resource Kits\Tools\srvany.exe",
        "$env:SystemRoot\srvany.exe"
    )
    foreach ($p in $searchPaths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Find-ClaudeExe {
    $candidate = Get-Command "claude" -ErrorAction SilentlyContinue
    if ($candidate) { return $candidate.Source }

    $searchPaths = @(
        "$env:LOCALAPPDATA\Programs\claude-code\claude.exe",
        "$env:APPDATA\npm\claude.cmd",
        "$env:ProgramFiles\nodejs\claude.cmd"
    )
    foreach ($p in $searchPaths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# --- Preflight checks ---

Write-Host "=== Claude Code Service Installer ===" -ForegroundColor Cyan
Write-Host ""

# Locate srvany.exe
if (-not $SrvAnyPath) {
    $SrvAnyPath = Find-SrvAny
}
if (-not $SrvAnyPath -or -not (Test-Path $SrvAnyPath)) {
    Write-Error "srvany.exe not found. Provide -SrvAnyPath or place srvany.exe next to this script."
    exit 1
}
Write-Host "[OK] srvany.exe found: $SrvAnyPath" -ForegroundColor Green

# Locate claude.exe
if (-not $ClaudeExePath) {
    $ClaudeExePath = Find-ClaudeExe
}
if (-not $ClaudeExePath -or -not (Test-Path $ClaudeExePath)) {
    Write-Error "claude.exe not found. Provide -ClaudeExePath or ensure Claude Code is installed and in PATH."
    exit 1
}
Write-Host "[OK] Claude CLI found: $ClaudeExePath" -ForegroundColor Green

# Check for existing service
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Error "Service '$ServiceName' already exists. Run uninstall-service.ps1 first."
    exit 1
}

# --- Create directory structure ---

Write-Host ""
Write-Host "Creating directory structure at $InstallDir ..." -ForegroundColor Yellow

$dirs = @(
    $InstallDir,
    "$InstallDir\config",
    "$InstallDir\config\.claude",
    "$InstallDir\logs"
)
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

# Copy srvany.exe into the install directory
Copy-Item -Path $SrvAnyPath -Destination "$InstallDir\srvany.exe" -Force
Write-Host "[OK] Directory structure created" -ForegroundColor Green

# --- Create the wrapper batch file ---

$wrapperPath = "$InstallDir\claude-code-wrapper.bat"
$wrapperContent = @"
@echo off
REM Claude Code Service Wrapper
REM This script is invoked by SrvAny to start Claude Code.

SET CLAUDE_HOME=$InstallDir\config
SET HOME=$InstallDir\config
SET CLAUDE_CONFIG_DIR=$InstallDir\config\.claude

REM Log output
SET LOG_DIR=$InstallDir\logs
SET LOG_FILE=%LOG_DIR%\claude-code-%DATE:~-4%%DATE:~4,2%%DATE:~7,2%.log

echo [%DATE% %TIME%] Starting Claude Code service >> "%LOG_FILE%" 2>&1
"$ClaudeExePath" $ClaudeArgs >> "%LOG_FILE%" 2>&1
"@
Set-Content -Path $wrapperPath -Value $wrapperContent -Encoding ASCII
Write-Host "[OK] Wrapper script created: $wrapperPath" -ForegroundColor Green

# --- Create the Windows service ---

Write-Host ""
Write-Host "Creating Windows service '$ServiceName' ..." -ForegroundColor Yellow

$srvanyDest = "$InstallDir\srvany.exe"
$scArgs = @("create", $ServiceName, "binPath=", "`"$srvanyDest`"", "start=", "demand", "DisplayName=", "`"$ServiceDisplayName`"")
$result = & sc.exe $scArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create service: $result"
    exit 1
}
Write-Host "[OK] Service created" -ForegroundColor Green

# Set description
& sc.exe description $ServiceName "$ServiceDescription" | Out-Null

# Set failure recovery: restart after 60 seconds on first three failures
& sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
Write-Host "[OK] Failure recovery configured (restart after 60s)" -ForegroundColor Green

# --- Configure service user ---

if ($ServiceUser) {
    if (-not $ServicePassword) {
        $securePass = Read-Host -Prompt "Enter password for $ServiceUser" -AsSecureString
        $ServicePassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
        )
    }
    & sc.exe config $ServiceName obj= "$ServiceUser" password= "$ServicePassword" | Out-Null
    Write-Host "[OK] Service configured to run as: $ServiceUser" -ForegroundColor Green

    # Grant logon-as-a-service right
    Write-Host "     (Ensure '$ServiceUser' has 'Log on as a service' right via Local Security Policy)" -ForegroundColor DarkYellow
} else {
    Write-Host "[WARN] No service user specified - service will run as LocalSystem." -ForegroundColor DarkYellow
    Write-Host "       Consider using -ServiceUser for better security." -ForegroundColor DarkYellow
}

# --- Set SrvAny registry parameters ---

Write-Host ""
Write-Host "Configuring SrvAny registry parameters ..." -ForegroundColor Yellow

$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName\Parameters"
New-Item -Path $regPath -Force | Out-Null
New-ItemProperty -Path $regPath -Name "Application" -Value $wrapperPath -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regPath -Name "AppDirectory" -Value $InstallDir -PropertyType String -Force | Out-Null
Write-Host "[OK] Registry parameters set" -ForegroundColor Green

# --- Create placeholder config files ---

$configReadme = "$InstallDir\config\COPY-YOUR-FILES-HERE.txt"
if (-not (Test-Path $configReadme)) {
    $configText = @"
Claude Code Service - Configuration Directory
==============================================

Copy your Claude Code configuration and authentication files here.

This directory acts as HOME for the Claude Code process.

Files you may need to copy from your user profile:

  .claude/                 - Claude Code configuration directory
    settings.json          - Claude Code settings
    credentials.json       - API authentication credentials
    projects/              - Project-specific settings

  .claude.json             - Additional Claude config (if present)

The original files are typically found in:
  %USERPROFILE%\.claude\

After copying, ensure file permissions allow the service account to read them.
"@
    Set-Content -Path $configReadme -Value $configText -Encoding UTF8
}
Write-Host "[OK] Config placeholder created" -ForegroundColor Green

# --- Summary ---

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Installation Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Install directory : $InstallDir"
Write-Host "Service name      : $ServiceName"
Write-Host "Wrapper script    : $wrapperPath"
Write-Host "Config directory  : $InstallDir\config"
Write-Host "Log directory     : $InstallDir\logs"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Copy your .claude/ folder into $InstallDir\config\"
Write-Host "  2. Verify credentials in $InstallDir\config\.claude\"
Write-Host "  3. Start the service:"
Write-Host "       net start $ServiceName"
Write-Host "  4. Check logs at $InstallDir\logs\"
Write-Host ""
