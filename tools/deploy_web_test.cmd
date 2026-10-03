@echo off
setlocal

where pwsh.exe >nul 2>&1
if errorlevel 1 goto no_pwsh

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy_web_test.ps1" %*
set "exitCode=%ERRORLEVEL%"

if not "%exitCode%"=="0" echo Deployment failed with exit code %exitCode%.
if "%exitCode%"=="0" echo Deployment completed successfully.
pause
exit /b %exitCode%

:no_pwsh
echo PowerShell 7 pwsh.exe is not found in PATH.
echo Install PowerShell 7 and run this file again.
pause
exit /b 1
