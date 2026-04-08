@echo off
title Claude Bridge
echo ================================================
echo  Claude Bridge - Starting...
echo  This window must stay open for Claude to work.
echo  Press Ctrl+C to stop.
echo ================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-bridge.ps1"
pause
