# Claude Code as a Windows Service (ccrcas)

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) as a Windows service using **SrvAny** from the Windows Server Resource Kit. The service runs under a dedicated local user account, with configuration and credentials isolated in a known directory.

## Prerequisites

1. **Windows 10/11 or Windows Server 2016+**
2. **Claude Code CLI** installed and working from a regular command prompt
   - Verify: open `cmd` and run `claude --version`
   - Install: `npm install -g @anthropic-ai/claude-code` (requires Node.js 18+)
3. **SrvAny.exe** from the Windows Server 2003 Resource Kit Tools
   - Download the Resource Kit, or obtain `srvany.exe` separately
   - Place it next to the install script or note its full path
4. **Administrator access** on the target machine
5. **A valid Anthropic API key** or existing Claude Code authentication

## Directory Layout

After installation, `C:\ClaudeCode` (configurable) will contain:

```
C:\ClaudeCode\
  srvany.exe                    # Service helper binary
  claude-code-wrapper.bat       # Wrapper script invoked by SrvAny
  config\                       # Acts as HOME for the service process
    .claude\                    # Claude Code configuration
      credentials.json          # Your API credentials (copy here)
      settings.json             # Your Claude Code settings (copy here)
  logs\                         # Service log output
    claude-code-YYYYMMDD.log
```

## Step-by-Step Installation

### Step 1: Create a Local Service Account (Recommended)

Open an **elevated PowerShell** or **Computer Management** console:

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

### Step 2: Run the Install Script

Open an **elevated PowerShell** prompt and navigate to the project directory:

```powershell
cd C:\path\to\ccrcas

# Basic install (will prompt for password)
.\install-service.ps1 -ServiceUser ".\claude-svc"

# Full options example
.\install-service.ps1 `
    -SrvAnyPath "C:\tools\srvany.exe" `
    -ServiceUser ".\claude-svc" `
    -ServicePassword "YourStrongPassword123!" `
    -InstallDir "C:\ClaudeCode" `
    -ClaudeExePath "C:\Users\you\AppData\Roaming\npm\claude.cmd" `
    -ClaudeArgs "--print"
```

#### Install Script Parameters

| Parameter | Default | Description |
|---|---|---|
| `-SrvAnyPath` | Auto-detect | Full path to `srvany.exe` |
| `-ServiceUser` | LocalSystem | Account to run the service as (e.g., `.\claude-svc`) |
| `-ServicePassword` | *(prompt)* | Password for the service account |
| `-InstallDir` | `C:\ClaudeCode` | Where service files, config, and logs live |
| `-ClaudeExePath` | Auto-detect | Full path to the `claude` CLI binary |
| `-ClaudeArgs` | *(empty)* | Arguments passed to `claude` (e.g., `--print`) |

### Step 3: Copy Your Configuration and Credentials

Copy your Claude Code authentication into the service's config directory:

```powershell
# Copy the entire .claude directory
Copy-Item -Recurse "$env:USERPROFILE\.claude\*" "C:\ClaudeCode\config\.claude\"
```

**Or**, if you prefer using an API key directly, edit the wrapper script:

```batch
REM In C:\ClaudeCode\claude-code-wrapper.bat, add before the claude command:
SET ANTHROPIC_API_KEY=sk-ant-api03-...
```

### Step 4: Verify File Permissions

Ensure the service account can read the config directory:

```powershell
icacls "C:\ClaudeCode" /grant "claude-svc:(OI)(CI)RX" /T
```

This grants read and execute permissions recursively.

### Step 5: Start the Service

```powershell
# Start the service
net start ClaudeCode

# Verify it is running
Get-Service ClaudeCode
```

You can also start/stop from the Services GUI (`services.msc`).

### Step 6: Check the Logs

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

## Uninstalling

```powershell
# Remove the service (keeps config and logs)
.\uninstall-service.ps1

# Remove the service AND all files
.\uninstall-service.ps1 -RemoveFiles
```

## Troubleshooting

### Service fails to start immediately (Error 1053)

SrvAny expects the wrapped application to keep running. If `claude` exits immediately, the service will report a timeout. Common causes:

- **Missing credentials**: Verify `C:\ClaudeCode\config\.claude\credentials.json` exists and is valid
- **Missing API key**: Set `ANTHROPIC_API_KEY` in the wrapper batch file
- **Wrong executable path**: Check the registry at `HKLM\SYSTEM\CurrentControlSet\Services\ClaudeCode\Parameters` that `Application` points to the correct wrapper

### Service starts but claude errors appear in logs

Check `C:\ClaudeCode\logs\` for the latest log file. Common issues:

- **Authentication failure**: Re-authenticate by running `claude` interactively as the service user, then copy the updated credentials
- **Network/proxy**: If behind a corporate proxy, add `SET HTTPS_PROXY=...` to the wrapper batch file
- **Node.js not in PATH**: The service runs with a minimal environment. Add the full path to `node.exe` parent directory to the system PATH, or set it in the wrapper

### How to re-authenticate

If credentials expire, re-authenticate as the service user:

```powershell
# Open a shell as the service user
runas /user:claude-svc cmd

# In that shell, run claude to authenticate
claude auth login

# Copy the updated credentials back
copy "%USERPROFILE%\.claude\credentials.json" "C:\ClaudeCode\config\.claude\"
```

Then restart the service: `net stop ClaudeCode && net start ClaudeCode`

### Verifying the registry configuration

The install script writes SrvAny parameters to the registry. To inspect:

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
SET ANTHROPIC_API_KEY=sk-ant-...
SET HTTPS_PROXY=http://proxy.corp:8080
SET NODE_EXTRA_CA_CERTS=C:\certs\corp-ca.pem
```

## How It Works

1. **SrvAny** is a generic service wrapper: Windows SCM starts `srvany.exe`, which reads `Application` and `AppDirectory` from its registry `Parameters` subkey and launches that process
2. The `Application` points to `claude-code-wrapper.bat`, which sets environment variables (`HOME`, `CLAUDE_CONFIG_DIR`) so Claude Code reads config from the service directory instead of a user profile
3. Claude Code runs with the credentials and settings found in `C:\ClaudeCode\config\.claude\`
4. Output is redirected to daily log files in `C:\ClaudeCode\logs\`

## Security Notes

- **Never commit credentials** to version control. The `.gitignore` in this repo excludes credential files
- Use a **dedicated service account** with minimal privileges rather than LocalSystem
- Restrict file permissions on `C:\ClaudeCode\config\` to the service account and administrators only
- Rotate API keys periodically and update them in the service config directory

## License

MIT
