#requires -Version 7.0
[CmdletBinding()]
param([string]$Profile = 'OddlyGoodHospital Stage01 验收', [ValidatePattern('^[a-z0-9-]+$')][string]$ValidationName = 'runtime-project')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$target = Join-Path (Join-Path $repo '.cache/validation') $ValidationName
New-Item -ItemType Directory -Force -Path $target | Out-Null
foreach ($name in @('game','assets')) {
    Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $target -Recurse -Force
}
$dataTarget = Join-Path $target 'docs/data'
New-Item -ItemType Directory -Force -Path $dataTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'docs/data/content-catalog.json'),(Join-Path $repo 'docs/data/balance.json'),(Join-Path $repo 'docs/data/clinical-layouts.json') -Destination $dataTarget -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'verify-stage01-runtime.gd') -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'verify-stage01-storage.gd') -Destination $target -Force
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'verify-stage01-ui.gd')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'verify-stage01-ui.gd') -Destination $target -Force }
$config = Get-Content -LiteralPath (Join-Path $repo 'project.godot') -Raw
$config.Replace('config/custom_user_dir_name="oddly-good-hospital"',('config/custom_user_dir_name="{0}"' -f $Profile)) | Set-Content -LiteralPath (Join-Path $target 'project.godot') -Encoding utf8NoBOM
Write-Output "VALIDATION_PROJECT=$target"
