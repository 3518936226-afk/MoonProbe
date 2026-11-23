param([string]$OutDir = '')
. "$PSScriptRoot\env.ps1"
if (!$OutDir) { $OutDir="$ProjectRoot\work\benchmark-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Push-Location $ProjectRoot
try {
  $results=@()
  foreach ($workload in @('generate','execute','shrink')) {
    $raw = & "$ProjectRoot\work\bin\moonprobe.exe" bench "$ProjectRoot\examples\extract-deadline.json" --workload $workload --repeat 20
    if ($LASTEXITCODE) { throw "Benchmark failed: $workload" }
    $raw | Set-Content "$OutDir\$workload.json" -Encoding utf8NoBOM
    $sample=$raw | ConvertFrom-Json
    if ($sample.samples -ne 30 -or $sample.raw_ns.Count -ne 30 -or $sample.median_ns -le 0) { throw "Invalid benchmark samples: $workload" }
    $results += $sample
    Write-Output "$workload median=$($sample.median_ns) ns p95=$($sample.p95_ns) ns"
  }
  $comparison=& "$ProjectRoot\work\bin\moonprobe.exe" bench "$ProjectRoot\examples\extract-deadline.json" --workload compare --repeat 20
  if($LASTEXITCODE){throw 'Algorithm comparison failed'}
  $comparison | Set-Content "$OutDir\comparison.json" -Encoding utf8NoBOM
  @{utc=[DateTime]::UtcNow.ToString('o');source_commit=(& git rev-parse HEAD);toolchain=(& $Moon version --all);compiler=(& $Gcc --version | Select-Object -First 1);platform=[Environment]::OSVersion.VersionString;architecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();build_mode='release -O2, synchronous runtime subset';results=$results} | ConvertTo-Json -Depth 40 | Set-Content "$OutDir\summary.json" -Encoding utf8NoBOM
} finally { Pop-Location }
