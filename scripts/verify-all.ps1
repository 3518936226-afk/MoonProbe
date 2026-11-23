param([string]$Python=$env:MOONPROBE_PYTHON,[string]$OutDir='')
. "$PSScriptRoot\env.ps1"
if(!$Python){$Python=(Get-Command python.exe -ErrorAction Stop).Source}
$env:PYTHONDONTWRITEBYTECODE='1';$env:PYTHONNOUSERSITE='1'
if(!$OutDir){$OutDir="$ProjectRoot\work\verification-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))"}
& "$PSScriptRoot\harness.ps1" -OutDir "$OutDir\harness"
& "$PSScriptRoot\build-native.ps1" -Oracle
& $Python "$PSScriptRoot\verify-depth.py" "$OutDir\independent"
if($LASTEXITCODE){throw 'Independent verification failed'}
& $Python "$PSScriptRoot\verify-mutations.py" "$OutDir\mutations"
if($LASTEXITCODE){throw 'Mutation verification failed'}
& "$PSScriptRoot\benchmark.ps1" -OutDir "$OutDir\benchmark"
Write-Output "FULL VERIFICATION PASSED: $OutDir"
