@echo off
REM ============================================================
REM Claude Code Service Wrapper (Template)
REM ============================================================
REM This is a reference template. The install script generates
REM a configured version at C:\ClaudeCode\claude-code-wrapper.bat
REM with paths filled in from your installation.
REM
REM srvany-ng executes this script to start Claude Code.
REM ============================================================

SET INSTALL_DIR=C:\ClaudeCode
SET WORKSPACE_DIR=C:\ClaudeCodeWorkspace

REM Redirect HOME so Claude Code reads OAuth tokens and config
REM from the service directory instead of a user profile.
SET HOME=%INSTALL_DIR%\config
SET USERPROFILE=%INSTALL_DIR%\config
SET CLAUDE_CONFIG_DIR=%INSTALL_DIR%\config\.claude

REM Uncomment to use an API key instead of OAuth:
REM SET ANTHROPIC_API_KEY=sk-ant-api03-...

REM Uncomment if behind a corporate proxy:
REM SET HTTPS_PROXY=http://proxy.corp:8080
REM SET NODE_EXTRA_CA_CERTS=C:\certs\corp-ca.pem

REM Change to the workspace directory where Claude Code operates.
cd /d "%WORKSPACE_DIR%"

SET LOG_DIR=%INSTALL_DIR%\logs
SET LOG_FILE=%LOG_DIR%\claude-code-%DATE:~-4%%DATE:~4,2%%DATE:~7,2%.log

echo [%DATE% %TIME%] Starting Claude Code service in %WORKSPACE_DIR% >> "%LOG_FILE%" 2>&1
claude >> "%LOG_FILE%" 2>&1
echo [%DATE% %TIME%] Claude Code exited with code %ERRORLEVEL% >> "%LOG_FILE%" 2>&1
