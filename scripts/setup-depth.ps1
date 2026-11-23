param([string]$Python=$env:MOONPROBE_PYTHON)
. "$PSScriptRoot\env.ps1"
if(!$Python){$Python=(Get-Command python.exe -ErrorAction Stop).Source}
$env:PYTHONDONTWRITEBYTECODE='1';$env:PYTHONNOUSERSITE='1';$env:PIP_CACHE_DIR="$ProjectRoot\work\pip-cache"
& $Python -c 'import sys; assert sys.version_info[:2]==(3,12), "Pinned development wheels require Python 3.12 x64 on Windows"'
if($LASTEXITCODE){throw 'Unsupported development Python'}
& $Python -m pip install --require-hashes --target "$ProjectRoot\work\oracle-deps" --report "$ProjectRoot\work\oracle-install.json" -r "$ProjectRoot\requirements-oracle.txt"
if($LASTEXITCODE){throw 'Independent reference installation failed'}
