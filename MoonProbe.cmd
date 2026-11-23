@echo off
setlocal
set "TEMP=%~dp0work\tmp"
set "TMP=%TEMP%"
if not exist "%~dp0work\bin\moonprobe.exe" (
  echo Build first: pwsh -NoProfile -File scripts\build-native.ps1
  exit /b 3
)
"%~dp0work\bin\moonprobe.exe" %*
exit /b %ERRORLEVEL%
