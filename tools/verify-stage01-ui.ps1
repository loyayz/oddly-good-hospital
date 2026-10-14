#requires -Version 7.0
[CmdletBinding()]
param([string]$ProjectPath = '.cache/validation/runtime-r6', [string]$Godot = 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe', [ValidateSet('full','startup')][string]$Case = 'full')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$project = [IO.Path]::GetFullPath((Join-Path $repo $ProjectPath))
$output = Join-Path $repo ('.cache/validation/Stage01 验收 UI/component-' + [Guid]::NewGuid().ToString())
$appData = Join-Path $output 'APPDATA'
New-Item -ItemType Directory -Force -Path $appData | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'verify-stage01-ui.gd') -Destination $project -Force
$info = [Diagnostics.ProcessStartInfo]::new($Godot)
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
$info.WorkingDirectory = $repo
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.Environment['APPDATA'] = $appData
foreach ($argument in @('--path',$project,'--position','-10000,-10000','--script','res://verify-stage01-ui.gd','--',('--runtime-evidence=' + (Join-Path $project 'runtime-evidence.json')),("--case=$Case"))) { $info.ArgumentList.Add($argument) }
$process = [Diagnostics.Process]::Start($info)
$stdout = $process.StandardOutput.ReadToEndAsync()
$stderr = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit(60000)) { Stop-Process -Id $process.Id -Force; $process.WaitForExit(); throw 'UI component probe timed out' }
$stdout.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $output 'stdout.log') -Encoding utf8NoBOM
$stderr.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $output 'stderr.log') -Encoding utf8NoBOM
Write-Output "UI_COMPONENT_EXIT=$($process.ExitCode); REPORT=$(Join-Path $appData 'evidence/ui-evidence.json'); OUTPUT=$output"
exit $process.ExitCode
