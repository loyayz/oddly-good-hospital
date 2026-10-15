#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateRange(4,28)][int]$Stage)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$name = 'stage{0:d2}-{1}' -f $Stage,[DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')
$target = Join-Path $repo ('.cache/validation/' + $name)
New-Item -ItemType Directory -Path $target -Force | Out-Null
Push-Location $repo
try {
    # Validate the precise index candidate while other stage work remains unstaged.
    $prefix = $target.Replace('\','/') + '/'
    & git checkout-index --all ('--prefix=' + $prefix)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot prepare the indexed source candidate.' }
} finally {
    Pop-Location
}
$native = Join-Path $repo 'game/platform/windows/bin/oddly_good_platform.windows.x86_64.dll'
if (-not (Test-Path -LiteralPath $native)) { throw 'Build the Windows platform bridge before functional validation.' }
$nativeTarget = Join-Path $target 'game/platform/windows/bin'
New-Item -ItemType Directory -Path $nativeTarget -Force | Out-Null
Copy-Item -LiteralPath $native -Destination $nativeTarget -Force
$projectFile = Join-Path $target 'project.godot'
$configuration = [IO.File]::ReadAllText($projectFile)
$profile = 'OddlyGoodHospital Stage{0:d2} 验收 {1}' -f $Stage,$name
$configuration.Replace('config/custom_user_dir_name="oddly-good-hospital"',('config/custom_user_dir_name="{0}"' -f $profile)) | Set-Content -LiteralPath $projectFile -Encoding utf8NoBOM
Write-Output "VALIDATION_PROJECT=$target"
