param([string]$OutDir = '')
. "$PSScriptRoot\env.ps1"
if (!$OutDir) { $OutDir = "$ProjectRoot\work\harness-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Push-Location $ProjectRoot
$checks = [System.Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Condition) {
  $checks.Add(@{ id=$Name; status= $(if ($Condition) {'passed'} else {'failed'}) })
  if (!$Condition) { throw "Check failed: $Name" }
}
function Invoke-Probe([string]$Name,[string[]]$Arguments,[int]$Expected) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = "$ProjectRoot\work\bin\moonprobe.exe"
  $psi.WorkingDirectory = $ProjectRoot
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  foreach ($argument in $Arguments) { $psi.ArgumentList.Add($argument) }
  $process = [System.Diagnostics.Process]::Start($psi)
  $stdout = $process.StandardOutput.ReadToEndAsync()
  $stderr = $process.StandardError.ReadToEndAsync()
  if (!$process.WaitForExit(30000)) { $process.Kill($true); throw "Timeout: $Name" }
  $text = $stdout.GetAwaiter().GetResult()
  $errorText = $stderr.GetAwaiter().GetResult()
  $text | Set-Content -LiteralPath "$OutDir\$Name.stdout.log" -Encoding utf8
  $errorText | Set-Content -LiteralPath "$OutDir\$Name.stderr.log" -Encoding utf8
  $checks.Add(@{id=$Name;status=$(if($process.ExitCode -eq $Expected){'passed'}else{'failed'});expected_exit=$Expected;actual_exit=$process.ExitCode;command=@($psi.FileName)+$Arguments})
  if ($process.ExitCode -ne $Expected) { throw "$Name expected $Expected got $($process.ExitCode): $errorText" }
  return $text
}
try {
  & $Moon fmt --check 2>&1 | Tee-Object -FilePath "$OutDir\format.log"
  Check 'format' ($LASTEXITCODE -eq 0)
  & $Moon check --target native --deny-warn 2>&1 | Tee-Object -FilePath "$OutDir\check.log"
  Check 'typecheck' ($LASTEXITCODE -eq 0)
  & "$PSScriptRoot\build-native.ps1" 2>&1 | Tee-Object -FilePath "$OutDir\build.log"
  Check 'native-build' $?
  & "$PSScriptRoot\build-native.ps1" -Test 2>&1 | Tee-Object -FilePath "$OutDir\test-build.log"
  Check 'native-test-build' $?
  $metadata = Get-Content '_build\native\release\test\engine\__whitebox_test_info.json' -Raw | ConvertFrom-Json
  $number = $metadata.tests.'engine_wbtest.mbt'.Count
  $unit = & "$ProjectRoot\work\engine-tests.exe" "engine_wbtest.mbt:0-$number"
  $unit | Set-Content "$OutDir\unit-tests.log" -Encoding utf8
  $results = @($unit | Where-Object { $_ -like '{*' } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object type -EQ 'result')
  Check 'unit-results-count' ($results.Count -eq $number -and $number -ge 13)
  foreach ($result in $results) { Check "unit-$($result.index)" ($result.message -eq '') }
  $spec = "$ProjectRoot\examples\extract-deadline.json"
  $null = Invoke-Probe 'inspect' @('inspect',$spec) 0
  $null = Invoke-Probe 'buggy' @('test',$spec,'--mock','buggy','--seed','20261123','--cases','32','--out',"$OutDir\buggy") 1
  $null = Invoke-Probe 'buggy-repeat' @('test',$spec,'--mock','buggy','--seed','20261123','--cases','32','--out',"$OutDir\buggy-repeat") 1
  $null = Invoke-Probe 'fixed' @('test',$spec,'--mock','fixed','--seed','20261123','--cases','32','--out',"$OutDir\fixed") 0
  $buggy = Get-Content "$OutDir\buggy\report.json" -Raw | ConvertFrom-Json
  $fixed = Get-Content "$OutDir\fixed\report.json" -Raw | ConvertFrom-Json
  Check '32-cases' ($buggy.results.Count -eq 32 -and $fixed.results.Count -eq 32)
  Check 'determinism' ((Get-FileHash "$OutDir\buggy\report.json").Hash -eq (Get-FileHash "$OutDir\buggy-repeat\report.json").Hash)
  Check 'fixed-all-pass' ($fixed.failed -eq 0)
  $invalid = @($buggy.results | Where-Object { $null -ne $_.case.expected })
  Check 'invalid-zero-calls' ($invalid.Count -gt 0 -and @($invalid | Where-Object called -EQ $true).Count -eq 0)
  $first = $buggy.corpus[0]
  Check 'signature' ($first.signature.stage -eq 'OUTPUT_SCHEMA' -and $first.signature.code -eq 'REQUIRED' -and $first.signature.path -eq '/deadline')
  Check 'shrinking' ($first.shrink.reduced_bytes -lt $first.shrink.original_bytes -and @($first.reduced_input.PSObject.Properties).Count -eq 1 -and $first.reduced_input.date -eq '2024-02-29')
  $null = Invoke-Probe 'replay-buggy' @('replay',$spec,"$OutDir\buggy\corpus",'--mock','buggy') 1
  $null = Invoke-Probe 'replay-fixed' @('replay',$spec,"$OutDir\buggy\corpus",'--mock','fixed') 0
  $null = Invoke-Probe 'missing-file' @('inspect',"$OutDir\not-found.json") 3
  $null = Invoke-Probe 'bad-args' @('test',$spec,'--cases','201','--out',"$OutDir\bad") 2
  $null = Invoke-Probe 'duplicate-option' @('test',$spec,'--cases','1','--cases','2','--out',"$OutDir\bad") 2
  '{"name":' | Set-Content "$OutDir\malformed.json" -Encoding utf8NoBOM
  $null = Invoke-Probe 'malformed-json' @('inspect',"$OutDir\malformed.json") 2
  '{"name":"x","adapter_id":"echo","input_schema":{"type":"object","format":"date"}}' | Set-Content "$OutDir\unsupported.json" -Encoding utf8NoBOM
  $null = Invoke-Probe 'unsupported-schema' @('inspect',"$OutDir\unsupported.json") 2
  '{"name":"a","name":"b"}' | Set-Content "$OutDir\duplicate.json" -Encoding utf8NoBOM
  $null = Invoke-Probe 'duplicate-key' @('inspect',"$OutDir\duplicate.json") 2
  [IO.File]::WriteAllBytes("$OutDir\invalid-utf8.json",[byte[]]@(255,254,255))
  $null = Invoke-Probe 'invalid-utf8' @('inspect',"$OutDir\invalid-utf8.json") 2
  [IO.File]::WriteAllText("$OutDir\too-large.json",('x' * 1048577))
  $null = Invoke-Probe 'file-budget' @('inspect',"$OutDir\too-large.json") 2
  New-Item -ItemType Directory -Force -Path "$OutDir\corrupt" | Out-Null
  $corpus=Get-Content "$OutDir\buggy\corpus\entries.json" -Raw | ConvertFrom-Json
  $corpus.entries[0].schema_fingerprint='mismatch'
  $corpus | ConvertTo-Json -Depth 40 -Compress | Set-Content "$OutDir\corrupt\entries.json" -Encoding utf8NoBOM
  $null = Invoke-Probe 'fingerprint-mismatch' @('replay',$spec,"$OutDir\corrupt",'--mock','fixed') 2
  $null = Invoke-Probe 'no-overwrite' @('test',$spec,'--out',"$OutDir\fixed") 2
  'not a directory' | Set-Content "$OutDir\blocked-output" -Encoding utf8NoBOM
  $null = Invoke-Probe 'write-error' @('test',$spec,'--out',"$OutDir\blocked-output") 3
  $null = Invoke-Probe 'unicode-path' @('test',"$ProjectRoot\examples\echo.json",'--out',"$OutDir\中文目录") 0
  $commit = & git rev-parse HEAD
  $summary = @{status='passed';source_commit=$commit;utc=[DateTime]::UtcNow.ToString('o');unit_groups=$number;checks=$checks;demo=@{cases=32;failed=$buggy.failed;passed=$buggy.passed;adapter_calls=$buggy.adapter_calls;original_bytes=$first.shrink.original_bytes;reduced_bytes=$first.shrink.reduced_bytes;reduction_ratio=$first.shrink.reduction_ratio}}
  $summary | ConvertTo-Json -Depth 50 | Set-Content "$OutDir\summary.json" -Encoding utf8NoBOM
  Write-Output "HARNESS PASSED: $($checks.Count) checks; $OutDir"
} catch {
  @{status='failed';error=$_.ToString();checks=$checks} | ConvertTo-Json -Depth 50 | Set-Content "$OutDir\summary.json" -Encoding utf8NoBOM
  throw
} finally { Pop-Location }
