# Claude Code as a Windows Service (ccrcas)

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) as a Windows service using **[srvany-ng](https://github.com/birkett/srvany-ng)** (an open-source, maintained replacement for the legacy SrvAny from the Windows Server Resource Kit). The service runs under a dedicated local user account and authenticates with Anthropic via **OAuth (Google account sign-in)**.

Configuration and OAuth tokens are isolated in a dedicated service directory (`C:\ClaudeCode` by default), so the service runs independently of any user session.

## Prerequisites

1. **Windows 10/11 or Windows Server 2016+**
2. **Claude Code CLI** installed and working from a regular command prompt
   - Verify: open `cmd` and run `claude --version`
   - Install: `npm install -g @anthropic-ai/claude-code` (requires Node.js 18+)
3. **srvany-ng.exe** — download from [GitHub releases](https://github.com/birkett/srvany-ng/releases)
   - Grab the latest `.zip`, extract `x64\srvany-ng.exe` (or `x86\` for 32-bit systems)
   - Place `srvany-ng.exe` next to the install script or note its full path
4. **Administrator access** on the target machine
5. **An Anthropic account** with Google sign-in (OAuth) configured

## Project Files

| File | Purpose |
|---|---|
| `install-service.ps1` | Creates the ClaudeCode Windows service, directories, and registry entries |
| `uninstall-service.ps1` | Removes the service (optionally removes all files) |
| `authenticate.ps1` | Handles interactive OAuth login and copies tokens to the service directory |
| `claude-code-wrapper.bat` | Template wrapper script that srvany-ng executes |

## Directory Layout

After installation, `C:\ClaudeCode` (configurable) will contain:

```
C:\ClaudeCode\                    # Install directory (service binaries + config)
  srvany-ng.exe                  # Service helper binary (from GitHub)
  claude-code-wrapper.bat       # Wrapper script invoked by srvany-ng
  config\                       # Acts as HOME for the service process
    .claude\                    # Claude Code config + OAuth tokens
      credentials.json          # OAuth tokens (created by authenticate.ps1)
      settings.json             # Claude Code settings
  logs\                         # Service log output
    claude-code-YYYYMMDD.log

C:\ClaudeCodeWorkspace\           # Workspace directory (where Claude Code operates)
```

## Step-by-Step Installation

### Step 1: Create a Local Service Account

Open an **elevated PowerShell** prompt:

```powershell
# Create a local user for the service
net user claude-svc "YourStrongPassword123!" /add /comment:"Claude Code service account"

# Prevent the password from expiring
wmic useraccount where "Name='claude-svc'" set PasswordExpires=FALSE
```

Then grant the **Log on as a service** right:

1. Open `secpol.msc` (Local Security Policy)
2. Navigate to **Local Policies > User Rights Assignment**
3. Double-click **Log on as a service**
4. Click **Add User or Group**, type `claude-svc`, click OK
5. Click OK to save

> **Important:** Log in to Windows as `claude-svc` at least once (e.g., via RDP or `runas`) so that Windows creates the user profile directory. This is required before running `authenticate.ps1`.

### Step 2: Run the Install Script

Open an **elevated PowerShell** prompt and navigate to the project directory:

```powershell
cd C:\path\to\ccrcas

# Basic install (will prompt for password)
.\install-service.ps1 -ServiceUser ".\claude-svc"

# Full options example
.\install-service.ps1 `
    -SrvAnyPath "C:\path\to\srvany-ng.exe" `
    -ServiceUser ".\claude-svc" `
    -ServicePassword "YourStrongPassword123!" `
    -InstallDir "C:\ClaudeCode" `
    -WorkspaceDir "C:\ClaudeCodeWorkspace" `
    -ClaudeExePath "C:\Users\you\AppData\Roaming\npm\claude.cmd" `
    -ClaudeArgs "--print"
```

#### Install Script Parameters

| Parameter | Default | Description |
|---|---|---|
| `-SrvAnyPath` | Auto-detect | Full path to `srvany-ng.exe` |
| `-ServiceUser` | LocalSystem | Account to run the service as (e.g., `.\claude-svc`) |
| `-ServicePassword` | *(prompt)* | Password for the service account |
| `-InstallDir` | `C:\ClaudeCode` | Where service files, config, and logs live |
| `-WorkspaceDir` | `C:\ClaudeCodeWorkspace` | Working directory where Claude Code operates |
| `-ClaudeExePath` | Auto-detect | Full path to the `claude` CLI binary |
| `-ClaudeArgs` | *(empty)* | Arguments passed to `claude` (e.g., `--print`) |

### Step 3: Authenticate with Anthropic (OAuth / Google)

Claude Code authenticates via a browser-based OAuth flow (Google sign-in). Since a Windows service cannot open a browser, you must authenticate interactively first, then copy the tokens to the service directory.

The `authenticate.ps1` script handles this:

```powershell
# Run from an elevated PowerShell prompt
.\authenticate.ps1 -ServiceUser "claude-svc"
```

**What this does:**

1. Opens a command prompt running as the `claude-svc` user
2. You run `claude auth login` — a browser opens for Google OAuth sign-in
3. You sign in with your Google account linked to your Anthropic account
4. You `cd` into the workspace directory and run `claude` to **trust the workspace** when prompted (then exit)
5. After completing both steps, close the command prompt
6. The script copies the resulting OAuth tokens and workspace trust settings from `claude-svc`'s profile into `C:\ClaudeCode\config\.claude\`
7. Sets file permissions so the service can read the tokens

> **Note:** Claude Code stores OAuth refresh tokens that allow it to obtain new access tokens automatically. As long as the refresh token remains valid, the service can authenticate without user interaction.

> **Important:** You must trust the workspace directory during this step. If you skip it, the service will fail with a "workspace not trusted" error because it cannot prompt interactively.

#### Manual alternative

If the script doesn't work in your environment, you can do it manually:

```powershell
# Open a shell as the service user
runas /user:claude-svc cmd

# In that prompt:
claude auth login
# Complete the Google OAuth flow in the browser

# Then trust the workspace:
cd C:\ClaudeCodeWorkspace
claude
# Accept the workspace trust prompt, then exit claude

exit
```

Then copy the tokens to the service directory:

```powershell
Copy-Item -Recurse "C:\Users\claude-svc\.claude\*" "C:\ClaudeCode\config\.claude\" -Force
icacls "C:\ClaudeCode" /grant "claude-svc:(OI)(CI)RX" /T
```

### Step 4: Start the Service

```powershell
# Start the service
net start ClaudeCode

# Verify it is running
Get-Service ClaudeCode
```

You can also start/stop from the Services GUI (`services.msc`).

### Step 5: Check the Logs

```powershell
# View today's log
Get-Content "C:\ClaudeCode\logs\claude-code-*.log" -Tail 50
```

## Managing the Service

### Start / Stop / Restart

```powershell
net start ClaudeCode
net stop ClaudeCode

# Or via PowerShell cmdlets
Start-Service ClaudeCode
Stop-Service ClaudeCode
Restart-Service ClaudeCode
```

### Set to Start Automatically on Boot

```powershell
Set-Service -Name ClaudeCode -StartupType Automatic
```

### View Service Status

```powershell
Get-Service ClaudeCode | Format-List *
```

### View Event Log Entries

```powershell
Get-EventLog -LogName System -Source "Service Control Manager" |
    Where-Object { $_.Message -like "*ClaudeCode*" } |
    Select-Object -First 10
```

## Re-authenticating (Token Refresh)

OAuth tokens expire. Claude Code automatically refreshes tokens using the stored refresh token when possible. If auto-refresh fails (e.g., the refresh token was revoked, or the Google session expired), you need to re-authenticate:

```powershell
# Re-run the authentication script
.\authenticate.ps1 -ServiceUser "claude-svc"
```

The script will detect if the service is running and offer to restart it after copying new tokens.

### Signs that re-authentication is needed

Check the service logs for messages like:
- `Authentication failed`
- `Token expired`
- `401 Unauthorized`
- `Please log in`

## Uninstalling

```powershell
# Remove the service (keeps config and logs)
.\uninstall-service.ps1

# Remove the service AND all files
.\uninstall-service.ps1 -RemoveFiles
```

## Troubleshooting

### Service fails to start immediately (Error 1053)

srvany-ng expects the wrapped application to keep running. If `claude` exits immediately, the service will report a timeout. Common causes:

- **Missing OAuth tokens**: Run `authenticate.ps1` to complete the Google sign-in flow
- **Expired tokens**: Re-authenticate with `authenticate.ps1 -ServiceUser "claude-svc"`
- **Wrong executable path**: Check the registry (see below) that `Application` points to the correct wrapper

### Service starts but auth errors appear in logs

Check `C:\ClaudeCode\logs\` for the latest log file. Common issues:

- **OAuth token expired**: Re-run `authenticate.ps1`
- **Network/proxy**: If behind a corporate proxy, edit `C:\ClaudeCode\claude-code-wrapper.bat` and uncomment/set `HTTPS_PROXY`
- **Node.js not in PATH**: The service runs with a minimal environment. Add the full path to `node.exe` parent directory to the system PATH, or set it in the wrapper

### User profile not created

If `authenticate.ps1` fails with "Claude config directory not found", the service user's Windows profile hasn't been created yet. Log in to Windows as `claude-svc` at least once:

```powershell
runas /user:claude-svc cmd
# Just typing 'exit' is enough - the profile is created on first login
```

### Verifying the registry configuration

The install script writes srvany-ng parameters to the registry. To inspect:

```powershell
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\ClaudeCode\Parameters"
```

You should see:

| Value | Expected |
|---|---|
| `Application` | `C:\ClaudeCode\claude-code-wrapper.bat` |
| `AppDirectory` | `C:\ClaudeCode` |

### Environment variables in the wrapper

Edit `C:\ClaudeCode\claude-code-wrapper.bat` to add any environment variables the service needs:

```batch
SET HTTPS_PROXY=http://proxy.corp:8080
SET NODE_EXTRA_CA_CERTS=C:\certs\corp-ca.pem
```

## How It Works

1. **srvany-ng** is a generic service wrapper: Windows SCM starts `srvany-ng.exe`, which reads `Application` and `AppDirectory` from its registry `Parameters` subkey and launches that process
2. The `Application` points to `claude-code-wrapper.bat`, which overrides `HOME` and `USERPROFILE` to point at the service directory, so Claude Code reads OAuth tokens from there instead of a user profile
3. **OAuth flow**: `authenticate.ps1` runs the browser-based Google sign-in interactively as the service user, then copies the resulting tokens (including the refresh token) into the service config directory
4. At runtime, Claude Code uses the stored refresh token to obtain fresh access tokens automatically, without needing a browser
5. Output is redirected to daily log files in `C:\ClaudeCode\logs\`

## Security Notes

- **Never commit OAuth tokens** to version control. The `.gitignore` in this repo excludes credential files
- Use a **dedicated service account** with minimal privileges rather than LocalSystem
- Restrict file permissions on `C:\ClaudeCode\config\` to the service account and administrators only
- The OAuth refresh token grants ongoing access to the Anthropic API on behalf of the signed-in Google account. Protect it like a password
- If you suspect token compromise, revoke access from your [Google account security settings](https://myaccount.google.com/permissions) and re-authenticate

## License

MIT
