#requires -Version 7.0
[CmdletBinding()]
param([string]$Godot = 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$project = Join-Path $repo '.cache/validation/stage03-benchmark-project'
$output = Join-Path $repo '.build/stage03/benchmark'
$logs = Join-Path $repo '.cache/validation/stage03-build'
if (-not (Test-Path -LiteralPath $Godot)) { throw "Godot not found: $Godot" }
New-Item -ItemType Directory -Force -Path $project,$output,$logs | Out-Null
foreach ($name in @('game','assets')) { Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $project -Recurse -Force }
foreach ($name in @('docs/data','tools/benchmarks')) {
    $target = Join-Path $project $name
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $repo $name) -File | Copy-Item -Destination $target -Force
}
$config = [IO.File]::ReadAllText((Join-Path $repo 'project.godot'))
$config = $config.Replace('res://game/app/main.tscn','res://tools/benchmarks/kernel_capture.tscn').Replace('config/custom_user_dir_name="oddly-good-hospital"','config/custom_user_dir_name="oddly-good-hospital-stage03-benchmark"')
[IO.File]::WriteAllText((Join-Path $project 'project.godot'),$config,[Text.UTF8Encoding]::new($false))
$presets = [IO.File]::ReadAllText((Join-Path $repo 'export_presets.cfg')).Replace('name="Windows Stage01"','name="Windows Kernel Benchmark"').Replace('tools/*,','').Replace('debug/export_console_wrapper=0','debug/export_console_wrapper=1')
$presets = $presets.Replace('.cache/tools/godot-4.7.2/templates/',((Join-Path $repo '.cache/tools/godot-4.7.2/templates/') -replace '\\','/'))
[IO.File]::WriteAllText((Join-Path $project 'export_presets.cfg'),$presets,[Text.UTF8Encoding]::new($false))
& $Godot --headless --path $project --import *> (Join-Path $logs 'benchmark-import.log')
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath (Join-Path $logs 'benchmark-import.log') -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) { throw "Benchmark import failed: $logs/benchmark-import.log" }
& $Godot --headless --path $project --export-release 'Windows Kernel Benchmark' (Join-Path $output 'kernel-benchmark.exe') *> (Join-Path $logs 'benchmark-export.log')
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath (Join-Path $logs 'benchmark-export.log') -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) { throw "Benchmark export failed: $logs/benchmark-export.log" }
$sources = @(rg --files game tools/benchmarks docs/data -g '*.gd' -g '*.json' -g '*.tscn')
if ($LASTEXITCODE -ne 0) { throw 'Source identity lookup failed.' }
$identity = foreach ($relative in ($sources | Sort-Object)) {
    [ordered]@{path=($relative -replace '\\','/');sha256=(Get-FileHash -LiteralPath (Join-Path $repo $relative) -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$artifacts = foreach ($name in @('kernel-benchmark.exe','kernel-benchmark.pck','oddly_good_platform.windows.x86_64.dll')) {
    $file = Join-Path $output $name
    [ordered]@{path=$name;bytes=(Get-Item -LiteralPath $file).Length;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()}
}
[ordered]@{version='0.3.0-stage03';engine=(& $Godot --version);source_head=(& git -C $repo rev-parse HEAD);captured_utc=[DateTime]::UtcNow.ToString('o');sources=@($identity);files=@($artifacts)} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'build-identity.json') -Encoding utf8NoBOM
Write-Output "BENCHMARK_RELEASE=$output"
