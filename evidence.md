# ccrcas - Development Log

## Session: Initial Project Creation

### Goal
Create a project that sets up Claude Code to run as a Windows service using SrvAny, running as a local user, with a directory for config and authentication files.

### Decisions Made

#### 1. Service Architecture
- Windows service named **ClaudeCode** using **srvany-ng** (open-source replacement for legacy SrvAny)
- Runs under a dedicated local user account (`claude-svc`)
- Install directory: `C:\ClaudeCode` (configurable)
- Separate workspace directory: `C:\ClaudeCodeWorkspace` (configurable)
- Wrapper batch script sets `HOME` and `USERPROFILE` to the service config directory so Claude Code reads tokens/config from there instead of a user profile

#### 2. SrvAny vs srvany-ng
- Original `srvany.exe` from the Windows Server 2003 Resource Kit is hard to find and discontinued
- Switched to **[srvany-ng](https://github.com/birkett/srvany-ng)** -- open-source, MIT-licensed, drop-in replacement, maintained, works on modern Windows
- Decision: do NOT bundle the binary in the repo; users download it from GitHub releases
- Install script auto-detects `srvany-ng.exe` next to the script, falls back to `srvany.exe`

#### 3. Authentication: OAuth with Google
- Claude Code authenticates via browser-based OAuth (Google sign-in)
- A Windows service cannot open a browser, so authentication must be done interactively first
- Created `authenticate.ps1` to handle this:
  1. Opens a `runas` prompt as the service user
  2. User runs `claude auth login` (browser opens for Google OAuth)
  3. After auth, script copies OAuth tokens from the service user's profile into the service config directory
- OAuth refresh tokens allow the service to re-authenticate without a browser, until the refresh token expires/is revoked

#### 4. Workspace Trust Problem
- Claude Code prompts "workspace not trusted" when entering a new directory for the first time
- This blocks the service since it can't prompt interactively
- **Research findings** (August 2026):
  - There is **no `--trust` CLI flag** -- this is an open feature request ([#45298](https://github.com/anthropics/claude-code/issues/45298), [#53606](https://github.com/anthropics/claude-code/issues/53606))
  - Trust decisions are per-workspace, tied to the git repo root or starting directory
  - Trust config is NOT stored in a pre-writable format
  - `permissions.allow` rules in `.claude/settings.json` only take effect AFTER the trust dialog is accepted
- **Available workarounds**:
  - `-p` (non-interactive/print mode): bypasses trust dialog entirely -- best fit for a service
  - `--dangerously-skip-permissions`: too broad, skips ALL permission checks
  - Interactive trust during `authenticate.ps1` setup: manual, fragile
- **Unresolved**: which approach to default to. `-p` is the pragmatic choice for service use.

#### 5. File Ownership
- Install script sets `claude-svc` as owner of both `C:\ClaudeCode` and `C:\ClaudeCodeWorkspace`
- Uses `takeown` + `icacls /setowner` + `icacls /grant (OI)(CI)F` for full control with inheritance
- Strips `.\` prefix from service user name for icacls compatibility

### Files Created

| File | Purpose |
|---|---|
| `install-service.ps1` | Creates the ClaudeCode Windows service, directories, registry entries, sets ownership |
| `uninstall-service.ps1` | Stops and removes the service, optionally removes all files |
| `authenticate.ps1` | Interactive OAuth login as service user, copies tokens to service config |
| `claude-code-wrapper.bat` | Template wrapper that srvany-ng executes; sets HOME, cd to workspace, logs output |
| `config/COPY-YOUR-FILES-HERE.txt` | Instructions for the config directory |
| `config/.claude/.gitkeep` | Preserves directory structure in git |
| `.gitignore` | Excludes credentials, logs, and srvany binaries |
| `README.md` | Step-by-step setup guide |

### Git History

1. `3f052bb` - Initial project: install/uninstall scripts, wrapper, config templates, README
2. `018a9e7` - Add OAuth (Google sign-in) authentication support with authenticate.ps1
3. `2ab970a` - Switch from legacy srvany.exe to srvany-ng
4. `8066316` - Set service user as owner of install directory
5. `da408e0` - Add separate workspace directory and workspace trust setup

### Open Questions

- Should `-p` (non-interactive mode) be the default for `ClaudeArgs` to avoid workspace trust prompts?
- What specific Claude Code mode/arguments are needed for the intended service use case?
- How to handle OAuth token expiry gracefully (auto-restart? alert?)
