@echo off
REM ============================================================
REM Claude Code Service Wrapper (Template)
REM ============================================================
REM This is a reference template. The install script generates
REM a configured version at C:\ClaudeCode\claude-code-wrapper.bat
REM with paths filled in from your installation.
REM
REM SrvAny executes this script to start Claude Code.
REM ============================================================

SET INSTALL_DIR=C:\ClaudeCode
SET CLAUDE_HOME=%INSTALL_DIR%\config
SET HOME=%INSTALL_DIR%\config
SET CLAUDE_CONFIG_DIR=%INSTALL_DIR%\config\.claude

SET LOG_DIR=%INSTALL_DIR%\logs
SET LOG_FILE=%LOG_DIR%\claude-code-%DATE:~-4%%DATE:~4,2%%DATE:~7,2%.log

echo [%DATE% %TIME%] Starting Claude Code service >> "%LOG_FILE%" 2>&1
claude >> "%LOG_FILE%" 2>&1
