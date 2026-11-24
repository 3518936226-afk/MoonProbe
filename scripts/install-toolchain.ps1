param([string]$ArchiveDir='')
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$project=Split-Path $PSScriptRoot -Parent
$env:TEMP="$project\work\tmp"; $env:TMP=$env:TEMP
New-Item -ItemType Directory -Force -Path $env:TEMP,"$project\work\downloads" | Out-Null
$lock=Get-Content "$project\toolchain.lock.json" -Raw | ConvertFrom-Json
$destination="$project\toolchain"
if (Test-Path "$destination\bin\moon.exe") { throw 'Toolchain already exists. Keep it; use a fresh project directory to install a second toolchain.' }
foreach ($archive in $lock.archives) {
  $file = if ($ArchiveDir) { Join-Path $ArchiveDir $archive.name } else { "$project\work\downloads\$($archive.name)" }
  if (!(Test-Path -LiteralPath $file)) {
    if ($ArchiveDir) { throw "Missing offline archive: $file" }
    & curl.exe -4 -fL --retry 3 --connect-timeout 15 --max-time 300 $archive.url -o $file
    if ($LASTEXITCODE) { throw "Download failed: $($archive.name)" }
  }
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant() -ne $archive.sha256) { throw "SHA256 mismatch: $file. Refusing replacement; use original verified offline archives." }
  $target = if ($archive.name -eq 'core.zip') { "$destination\lib" } else { $destination }
  Expand-Archive -LiteralPath $file -DestinationPath $target -Force
}
$env:MOON_HOME=$destination
$env:PATH="$destination\bin;$env:PATH"
Push-Location "$destination\lib\core"
try { & "$destination\bin\moon.exe" bundle --target native --warn-list '-a'; if ($LASTEXITCODE) { throw 'Native core bundling failed' } } finally { Pop-Location }
& "$destination\bin\moon.exe" version --all
