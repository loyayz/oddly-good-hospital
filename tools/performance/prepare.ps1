#requires -Version 7.0
[CmdletBinding()]
param([string]$Godot='C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe',[string]$Output='')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$id=[Guid]::NewGuid().ToString('N')
$target=if($Output){[IO.Path]::GetFullPath($Output)}else{Join-Path $repo ('.cache/performance/'+$id)}
if(Test-Path -LiteralPath $target){throw "Performance project already exists: $target"}
New-Item -ItemType Directory -Path $target | Out-Null
$paths=@(& git -c core.quotePath=false -C $repo ls-files --cached --others --exclude-standard)
if($LASTEXITCODE -ne 0){throw 'Cannot enumerate performance sources'}
$source=foreach($relative in $paths | Sort-Object -Unique){
    if($relative -notmatch '^(game/|content/|assets/|tools/performance/|tests/acceptance/clinical_timing\.gd$|project\.godot$|export_presets\.cfg$)'){continue}
    $path=Join-Path $repo $relative
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){continue}
    $destination=Join-Path $target $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $path -Destination $destination
    [ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$native=Join-Path $repo 'game/platform/windows/bin/oddly_good_platform.windows.x86_64.dll'
$nativeTarget=Join-Path $target 'game/platform/windows/bin'
New-Item -ItemType Directory -Force -Path $nativeTarget,(Join-Path $target '.godot/imported') | Out-Null
Copy-Item -LiteralPath $native -Destination $nativeTarget
$mathNative=Join-Path (Split-Path -Parent $native) 'libgmp-10.dll'
Copy-Item -LiteralPath $mathNative -Destination $nativeTarget
$mpfrNative=Join-Path (Split-Path -Parent $native) 'libmpfr-6.dll'
Copy-Item -LiteralPath $mpfrNative -Destination $nativeTarget
$runtimeHashes=@{}
foreach($name in 'libgcc_s_seh-1.dll','libwinpthread-1.dll'){
    $runtimePath=Join-Path (Split-Path -Parent $native) $name
    Copy-Item -LiteralPath $runtimePath -Destination $nativeTarget
    $runtimeHashes[$name]=(Get-FileHash -LiteralPath $runtimePath).Hash
}
Get-ChildItem -LiteralPath (Join-Path $repo '.godot/imported') -File | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $target '.godot/imported')}
$project=Join-Path $target 'project.godot'
$profile='OddlyGoodHospital Performance '+$id
[IO.File]::ReadAllText($project).Replace('config/custom_user_dir_name="oddly-good-hospital"',('config/custom_user_dir_name="'+$profile+'"')) | Set-Content -LiteralPath $project -Encoding utf8NoBOM
$presets=Join-Path $target 'export_presets.cfg'
$templateRoot=(Join-Path $repo '.cache/tools/godot-4.7.2/templates').Replace('\','/')
[IO.File]::ReadAllText($presets).Replace('.cache/tools/godot-4.7.2/templates',$templateRoot) | Set-Content -LiteralPath $presets -Encoding utf8NoBOM
$arguments=@('--headless','--editor','--path',$target,'--import','--quit')
[ordered]@{head=(& git -C $repo rev-parse HEAD);project=$target;profile=$profile;source=$source;engine=$Godot;engine_sha256=(Get-FileHash -LiteralPath $Godot).Hash;native_sha256=(Get-FileHash -LiteralPath $native).Hash;gmp_sha256=(Get-FileHash -LiteralPath $mathNative).Hash;mpfr_sha256=(Get-FileHash -LiteralPath $mpfrNative).Hash;runtime_sha256=$runtimeHashes;import_arguments=$arguments} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $target 'source-identity.json') -Encoding utf8NoBOM
$log=Join-Path $target 'import.log'
& $Godot @arguments *> $log
if($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)){Get-Content -LiteralPath $log -Tail 25; throw "Performance project import failed: $log"}
Write-Output "PERFORMANCE_PROJECT=$target"
