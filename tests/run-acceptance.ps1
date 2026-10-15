#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('core','clinical','staff','operations','growth','space')][string[]]$Suite = @('core','clinical','staff','operations','growth','space'),
    [Alias('Case')][string[]]$CaseId = @(),
    [string]$Godot = 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
if ($CaseId.Count -gt 0 -and ($Suite.Count -ne 1 -or $Suite[0] -notin @('operations','space','clinical'))) {
    throw 'Case selection requires one operations, space, or supported clinical suite.'
}
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runId = [Guid]::NewGuid().ToString('N')
$target = Join-Path $repo ('.cache/acceptance/' + $runId)
New-Item -ItemType Directory -Path $target -Force | Out-Null
$paths = @(& git -c core.quotePath=false -C $repo ls-files --cached --others --exclude-standard | Sort-Object -Unique)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate acceptance source.' }
$identity = foreach ($relative in $paths) {
    $source = Join-Path $repo $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    $destination = Join-Path $target $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
    [ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$native = Join-Path $repo 'game/platform/windows/bin/oddly_good_platform.windows.x86_64.dll'
if (-not (Test-Path -LiteralPath $native -PathType Leaf)) { throw 'Build the platform library before acceptance.' }
$nativeTarget = Join-Path $target 'game/platform/windows/bin'
New-Item -ItemType Directory -Force -Path $nativeTarget,(Join-Path $target '.godot/imported') | Out-Null
Copy-Item -LiteralPath $native -Destination $nativeTarget
# Reuse imported immutable assets; editor state and hospital data are never copied.
Get-ChildItem -LiteralPath (Join-Path $repo '.godot/imported') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $target '.godot/imported')
}
$project = Join-Path $target 'project.godot'
$profile = 'OddlyGoodHospital Acceptance ' + $runId
$configuration = [IO.File]::ReadAllText($project)
$configuration.Replace('config/custom_user_dir_name="oddly-good-hospital"',('config/custom_user_dir_name="' + $profile + '"')) | Set-Content -LiteralPath $project -Encoding utf8NoBOM
$importArguments = @('--headless','--editor','--path',$target,'--import','--quit')
$arguments = @('--headless','--path',$target,'--script','res://tests/acceptance/runner.gd','--') + $Suite
foreach ($selectedCase in $CaseId) { $arguments += '--case=' + $selectedCase }
[ordered]@{
    head=(& git -C $repo rev-parse HEAD); cwd=$repo; project=$target; profile=$profile
    engine=$Godot; engine_sha256=(Get-FileHash -LiteralPath $Godot -Algorithm SHA256).Hash
    native_sha256=(Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash
    import_arguments=$importArguments; test_arguments=$arguments; source=$identity
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $target 'source-identity.json') -Encoding utf8NoBOM
Write-Output "ACCEPTANCE_PROJECT=$target"
$importLog = Join-Path $target 'import.log'
& $Godot @importArguments *> $importLog
$importExit = $LASTEXITCODE
if ($importExit -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR:|Parse Error:|ERROR:' -Quiet)) {
    Get-Content -LiteralPath $importLog -Tail 40
    throw "Acceptance import failed: exit=$importExit log=$importLog"
}
$testLog = Join-Path $target 'execution.log'
& $Godot @arguments *> $testLog
$testExit = $LASTEXITCODE
$scriptErrors = [bool](Select-String -LiteralPath $testLog -Pattern 'SCRIPT ERROR:|Parse Error:|ERROR:' -Quiet)
[ordered]@{import_exit=$importExit;test_exit=$testExit;script_errors=$scriptErrors;log=$testLog} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $target 'execution-status.json') -Encoding utf8NoBOM
Get-Content -LiteralPath $testLog
if ($testExit -ne 0 -or $scriptErrors) { throw "Acceptance failed: exit=$testExit log=$testLog" }
Write-Output "ACCEPTANCE_PASS=$target"
