#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Authenticates Claude Code for the service account using Anthropic OAuth (Google sign-in).
.DESCRIPTION
    Claude Code uses browser-based OAuth when authenticating with an Anthropic account
    (e.g., sign in with Google). A Windows service cannot open a browser, so this script
    handles the interactive authentication step:

    1. Opens an interactive command prompt as the service user
    2. The user completes "claude auth login" in that prompt (browser opens for Google OAuth)
    3. After successful auth, copies the resulting OAuth tokens into the service config directory

    Run this script once during initial setup, and again whenever tokens expire and
    cannot be refreshed automatically.
.PARAMETER ServiceUser
    The local service account (e.g., "claude-svc"). Do not include domain prefix.
.PARAMETER InstallDir
    Service install directory. Defaults to C:\ClaudeCode.
.PARAMETER SkipInteractive
    Skip the interactive login step. Use this if you already authenticated as the
    service user and just want to copy the tokens.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceUser,
    [string]$InstallDir = "C:\ClaudeCode",
    [switch]$SkipInteractive
)

$ServiceName = "ClaudeCode"
$ConfigDir = "$InstallDir\config"
$ClaudeConfigDir = "$ConfigDir\.claude"

Write-Host "=== Claude Code OAuth Authentication ===" -ForegroundColor Cyan
Write-Host ""

# Resolve the service user's profile directory
$userProfile = "C:\Users\$ServiceUser"
$userClaudeDir = "$userProfile\.claude"

if (-not $SkipInteractive) {
    Write-Host "This will open an interactive command prompt as '$ServiceUser'." -ForegroundColor Yellow
    Write-Host "In that prompt, run:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    claude auth login" -ForegroundColor White
    Write-Host ""
    Write-Host "A browser window will open for Google OAuth sign-in." -ForegroundColor Yellow
    Write-Host "Complete the sign-in, then close the command prompt when done." -ForegroundColor Yellow
    Write-Host ""

    $confirm = Read-Host "Press Enter to continue (or 'q' to quit)"
    if ($confirm -eq 'q') { exit 0 }

    # Launch interactive cmd as the service user
    Write-Host "Opening command prompt as '$ServiceUser' ..." -ForegroundColor Yellow
    Write-Host "(You may be prompted for the service account password)" -ForegroundColor DarkYellow
    Write-Host ""

    try {
        $process = Start-Process -FilePath "runas.exe" `
            -ArgumentList "/user:$env:COMPUTERNAME\$ServiceUser", "cmd.exe /K echo Ready. Run: claude auth login" `
            -PassThru -Wait
    } catch {
        Write-Error "Failed to launch interactive prompt: $_"
        Write-Host ""
        Write-Host "Alternative: open a regular cmd and run:" -ForegroundColor Yellow
        Write-Host "    runas /user:$ServiceUser cmd" -ForegroundColor White
        Write-Host "Then in that window run 'claude auth login' and complete the OAuth flow." -ForegroundColor Yellow
        exit 1
    }

    Write-Host ""
    Write-Host "Interactive session closed." -ForegroundColor Green
}

# --- Copy tokens to service config directory ---

Write-Host ""
Write-Host "Looking for OAuth tokens in $userClaudeDir ..." -ForegroundColor Yellow

if (-not (Test-Path $userClaudeDir)) {
    Write-Error "Claude config directory not found at $userClaudeDir"
    Write-Host "The authentication may not have completed successfully." -ForegroundColor Red
    Write-Host ""
    Write-Host "Possible causes:" -ForegroundColor Yellow
    Write-Host "  - The service user's profile hasn't been created yet (log in to Windows as that user first)"
    Write-Host "  - 'claude auth login' was not run or did not complete"
    Write-Host "  - Claude Code stores config elsewhere on this system"
    exit 1
}

# Find auth-related files
$authFiles = @(
    "credentials.json",
    "auth.json",
    ".credentials.json"
)

$found = @()
foreach ($f in $authFiles) {
    $path = Join-Path $userClaudeDir $f
    if (Test-Path $path) {
        $found += $path
    }
}

# Also look for any OAuth token files
$tokenFiles = Get-ChildItem -Path $userClaudeDir -Filter "*.json" -ErrorAction SilentlyContinue
foreach ($tf in $tokenFiles) {
    if ($tf.FullName -notin $found) {
        $found += $tf.FullName
    }
}

if ($found.Count -eq 0) {
    Write-Error "No credential or token files found in $userClaudeDir"
    Write-Host "Run 'claude auth login' as the service user and try again." -ForegroundColor Red
    exit 1
}

Write-Host "Found $($found.Count) config file(s) to copy:" -ForegroundColor Green
foreach ($f in $found) {
    Write-Host "  $(Split-Path $f -Leaf)" -ForegroundColor White
}

# Ensure target directory exists
if (-not (Test-Path $ClaudeConfigDir)) {
    New-Item -ItemType Directory -Path $ClaudeConfigDir -Force | Out-Null
}

# Copy files
Write-Host ""
Write-Host "Copying to $ClaudeConfigDir ..." -ForegroundColor Yellow
foreach ($f in $found) {
    $dest = Join-Path $ClaudeConfigDir (Split-Path $f -Leaf)
    Copy-Item -Path $f -Destination $dest -Force
    Write-Host "  [OK] $(Split-Path $f -Leaf)" -ForegroundColor Green
}

# Also copy any subdirectories (projects, etc.)
$subDirs = Get-ChildItem -Path $userClaudeDir -Directory -ErrorAction SilentlyContinue
foreach ($sd in $subDirs) {
    $destDir = Join-Path $ClaudeConfigDir $sd.Name
    Copy-Item -Path $sd.FullName -Destination $destDir -Recurse -Force
    Write-Host "  [OK] $($sd.Name)\" -ForegroundColor Green
}

# Set permissions
Write-Host ""
Write-Host "Setting file permissions ..." -ForegroundColor Yellow
& icacls $ClaudeConfigDir /grant "${ServiceUser}:(OI)(CI)RX" /T /Q 2>&1 | Out-Null
Write-Host "[OK] Permissions set for $ServiceUser" -ForegroundColor Green

# --- Restart service if running ---

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq 'Running') {
    Write-Host ""
    $restart = Read-Host "Service is running. Restart to pick up new credentials? (y/N)"
    if ($restart -eq 'y') {
        Restart-Service -Name $ServiceName
        Write-Host "[OK] Service restarted" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Authentication Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "OAuth tokens have been copied to the service config directory."
Write-Host "The service will use these tokens to authenticate with Anthropic."
Write-Host ""
Write-Host "If tokens expire and auto-refresh fails, re-run this script."
Write-Host ""
