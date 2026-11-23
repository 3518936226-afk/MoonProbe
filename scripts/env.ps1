$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$ProjectRoot = Split-Path $PSScriptRoot -Parent
if (!$env:MOON_HOME) { $env:MOON_HOME = "$ProjectRoot\toolchain" }
$env:TEMP = "$ProjectRoot\work\tmp"
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
$env:PATH = "$env:MOON_HOME\bin;C:\mingw64\bin;$env:PATH"
$Moon = Join-Path $env:MOON_HOME 'bin\moon.exe'
$Gcc = (Get-Command gcc.exe -ErrorAction Stop).Source
