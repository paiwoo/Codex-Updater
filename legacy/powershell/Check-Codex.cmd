@echo off
chcp 65001 >nul
title Codex Update Verification
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Sta -ExecutionPolicy Bypass -File "%~dp0Update-Codex.ps1" -VerifyOnly
echo.
pause
