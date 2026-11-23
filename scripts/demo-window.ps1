$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$project=Split-Path $PSScriptRoot -Parent
$env:TEMP="$project\work\tmp"; $env:TMP=$env:TEMP
$exe="$project\work\bin\moonprobe.exe"
$spec="$project\examples\extract-deadline.json"
$demoDir="$project\work\live-demo-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmss'))"
New-Item -ItemType Directory -Force -Path $demoDir | Out-Null
$NL=[Environment]::NewLine
$script:transcript=[System.Collections.Generic.List[object]]::new()
function CallNative([string[]]$Arguments) {
  $p=[Diagnostics.ProcessStartInfo]::new();$p.FileName=$exe;$p.UseShellExecute=$false;$p.CreateNoWindow=$true;$p.RedirectStandardOutput=$true;$p.RedirectStandardError=$true
  foreach($v in $Arguments){$p.ArgumentList.Add($v)}
  $process=[Diagnostics.Process]::Start($p);$raw=$process.StandardOutput.ReadToEnd();$err=$process.StandardError.ReadToEnd();$process.WaitForExit()
  $script:transcript.Add(@{args=$Arguments;exit_code=$process.ExitCode;stdout=$raw;stderr=$err})
  $script:transcript | ConvertTo-Json -Depth 50 | Set-Content "$demoDir\transcript.json" -Encoding utf8NoBOM
  if(!$raw){throw $err}
  return @{code=$process.ExitCode;data=($raw|ConvertFrom-Json)}
}
$form=[Windows.Forms.Form]::new();$form.Text='MoonProbe Native Demonstration';$form.ClientSize=[Drawing.Size]::new(1040,740);$form.StartPosition='CenterScreen';$form.BackColor=[Drawing.Color]::FromArgb(16,22,36)
$title=[Windows.Forms.Label]::new();$title.Text='MoonProbe | Native reliability testing';$title.Font=[Drawing.Font]::new('Consolas',22,[Drawing.FontStyle]::Bold);$title.ForeColor=[Drawing.Color]::White;$title.SetBounds(24,18,990,42);$form.Controls.Add($title)
$subtitle=[Windows.Forms.Label]::new();$subtitle.Text='Live local command output | synthetic fixtures | no network';$subtitle.Font=[Drawing.Font]::new('Consolas',12);$subtitle.ForeColor=[Drawing.Color]::LightSkyBlue;$subtitle.SetBounds(26,65,990,26);$form.Controls.Add($subtitle)
$status=[Windows.Forms.Label]::new();$status.Text='Ready to inspect, detect, shrink and replay';$status.Font=[Drawing.Font]::new('Consolas',14);$status.ForeColor=[Drawing.Color]::Aquamarine;$status.SetBounds(24,105,990,32);$form.Controls.Add($status)
$box=[Windows.Forms.TextBox]::new();$box.Multiline=$true;$box.ReadOnly=$true;$box.ScrollBars='Vertical';$box.BackColor=[Drawing.Color]::FromArgb(23,34,55);$box.ForeColor=[Drawing.Color]::FromArgb(225,234,249);$box.Font=[Drawing.Font]::new('Consolas',12);$box.SetBounds(24,150,992,510);$box.Text='inspect -> generate/execute -> shrink -> replay buggy/fixed'+$NL+$NL+'This window runs the actual shipped Native executable.'+$NL+'Full command output and exit codes are archived.'+$NL+$NL+'Expected: buggy=1, fixed replay=0.'+$NL+'Synthetic fixtures only; external human verification pending.';$form.Controls.Add($box)
$button=[Windows.Forms.Button]::new();$button.Text='Start live demonstration';$button.Font=[Drawing.Font]::new('Consolas',12);$button.SetBounds(24,680,300,36);$form.Controls.Add($button)
$timer=[Windows.Forms.Timer]::new();$timer.Interval=8000;$script:phase=0
function StepDemo {
  try {
    switch($script:phase){
      0 { $r=CallNative -Arguments @('inspect',$spec);if($r.code -ne 0){throw 'inspect failed'};$status.Text='01 Inspect contract | exit 0';$box.Text='$ moonprobe inspect examples/extract-deadline.json'+$NL+$NL+(@{name=$r.data.name;mode=$r.data.mode;date_enum=$r.data.input_schema.properties.date.enum;required_output=$r.data.output_schema.required;schema_fingerprint=$r.data.schema_fingerprint}|ConvertTo-Json -Depth 20) }
      1 { $r=CallNative -Arguments @('test',$spec,'--mock','buggy','--seed','20261123','--cases','32','--out',"$demoDir\buggy");if($r.code -ne 1){throw 'buggy expected exit 1'};$report=Get-Content "$demoDir\buggy\report.json" -Raw|ConvertFrom-Json;$first=$report.corpus[0];$status.Text='02 Find and shrink injected fault | expected exit 1';$box.Text='$ moonprobe test ... --mock buggy --seed 20261123 --cases 32'+$NL+$NL+(@{passed=$report.passed;failed=$report.failed;signature=$first.signature;original_input=$first.original_input;reduced_input=$first.reduced_input;original_bytes=$first.shrink.original_bytes;reduced_bytes=$first.shrink.reduced_bytes}|ConvertTo-Json -Depth 20) }
      2 { $r=CallNative -Arguments @('replay',$spec,"$demoDir\buggy\corpus",'--mock','buggy');if($r.code -ne 1){throw 'buggy replay expected exit 1'};$status.Text='03 Replay the same corpus on buggy | expected exit 1';$box.Text='$ moonprobe replay ... --mock buggy'+$NL+$NL+(@{passed=$r.data.passed;failed=$r.data.failed;first_result=$r.data.results[0]}|ConvertTo-Json -Depth 20) }
      3 { $r=CallNative -Arguments @('replay',$spec,"$demoDir\buggy\corpus",'--mock','fixed');if($r.code -ne 0){throw 'fixed replay expected exit 0'};$status.Text='04 Replay with fixed adapter | exit 0';$box.Text='$ moonprobe replay ... --mock fixed'+$NL+$NL+(@{passed=$r.data.passed;failed=$r.data.failed;first_result=$r.data.results[0]}|ConvertTo-Json -Depth 20)+$NL+$NL+'Only the adapter version changed.'+$NL+'Public CI and independent human verification remain pending.';$timer.Stop();@{passed=$true;binary_sha256=(Get-FileHash $exe).Hash;directory=$demoDir}|ConvertTo-Json|Set-Content "$demoDir\complete.json" -Encoding utf8NoBOM }
    }
    $script:phase++
  }catch{$status.Text='DEMO FAILED';$box.Text=$_.ToString();$timer.Stop()}
}
$timer.Add_Tick({StepDemo})
$button.Add_Click({$button.Enabled=$false;StepDemo;$timer.Start()})
$form.Add_FormClosed({$timer.Stop();$timer.Dispose()})
[void]$form.ShowDialog()
