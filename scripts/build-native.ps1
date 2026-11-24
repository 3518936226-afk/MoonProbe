param([switch]$Test,[switch]$Oracle)
. "$PSScriptRoot\env.ps1"
Push-Location $ProjectRoot
try {
  if (!(Test-Path "$env:MOON_HOME\lib\core\_build\native\release\bundle\json\json.mi")) {
    Push-Location "$env:MOON_HOME\lib\core"
    try { & $Moon bundle --target native --warn-list '-a'; if ($LASTEXITCODE) { throw 'Core bundle failed' } } finally { Pop-Location }
  }
  $mode = if ($Test) { 'test' } else { 'build' }
  $args = @($mode,'--target','native','--release','--dry-run')
  $target = if ($Test) { 'engine' } elseif ($Oracle) { 'cmd/oracle' } else { 'cmd/moonprobe' }
  $args += $target
  $plan = & $Moon @args
  if ($LASTEXITCODE) { throw 'Compiler planning failed' }
  New-Item -ItemType Directory -Force -Path "$ProjectRoot\work\logs" | Out-Null
  $plan | Set-Content -LiteralPath "$ProjectRoot\work\logs\$mode-plan.log" -Encoding utf8
  foreach ($line in $plan) {
    $line = $line.Replace('$MOON_HOME', $env:MOON_HOME.Replace('\','/'))
    if ($line -match '^moonc ' ) { $line = "& '$env:MOON_HOME/bin/moonc.exe' " + $line.Substring(6) }
    if ($line -match '^moon generate-test-driver') {
      if ($line -match '--output-driver (\S+)') { New-Item -ItemType Directory -Force -Path (Split-Path $Matches[1] -Parent) | Out-Null }
      Invoke-Expression ("& '$Moon' " + $line.Substring(5))
      if ($LASTEXITCODE) { throw 'Test driver generation failed' }
    } elseif ($line -match 'moonc.exe.*(build-package|link-core)') {
      $line = $line -replace ' -all-pkgs \S+', ''
      if ($line -match ' -o (\S+)') { New-Item -ItemType Directory -Force -Path (Split-Path $Matches[1] -Parent) | Out-Null }
      Invoke-Expression $line
      if ($LASTEXITCODE) { throw 'MoonBit compilation failed' }
    }
  }
  # The official compiler unconditionally plans MSVC-only async runtime objects.
  # This synchronous CLI links the unmodified official runtime subset it uses.
  $generated = if ($Test) { '_build\native\release\test\engine\engine.whitebox_test.c' } elseif ($Oracle) { '_build\native\release\build\cmd\oracle\oracle.c' } else { '_build\native\release\build\cmd\moonprobe\moonprobe.c' }
  $out = if ($Test) { 'work\engine-tests.exe' } elseif ($Oracle) { 'work\oracle.exe' } else { 'work\bin\moonprobe.exe' }
  New-Item -ItemType Directory -Force -Path (Split-Path $out -Parent) | Out-Null
  $sources = @($generated,"$env:MOON_HOME\lib\runtime\runtime.c","$env:MOON_HOME\lib\runtime\env.c","$env:MOON_HOME\lib\runtime\utf.c","$env:MOON_HOME\lib\runtime\backtrace.c")
  if (!$Test) { $sources += $(if($Oracle){'cmd\oracle\native_io.c'}else{'cmd\moonprobe\native_io.c'}) }
  if (!$Test -and !$Oracle) { $sources += 'cmd\moonprobe\native_process.c' }
  & $Gcc '-O2' '-fwrapv' '-fno-strict-aliasing' '-ffp-contract=off' '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_SYSTEM' "-I$env:MOON_HOME\include" @sources '-lm' '-o' $out
  if ($LASTEXITCODE) { throw 'Native linking failed' }
  Write-Output (Join-Path $ProjectRoot $out)
} finally { Pop-Location }
