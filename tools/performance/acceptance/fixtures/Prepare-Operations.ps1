#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Godot,
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$InputDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateSet('all','stability_a','stability_b','maximum_upper','preview_tall')][string]$CaseId='all',
    [ValidateRange(1,86400)][int]$MaximumRealSeconds=3600,
    [ValidateRange(1,1000000)][int]$MaximumSteps=40000,
    [switch]$Plan
)
$ErrorActionPreference='Stop'
$enginePath=[IO.Path]::GetFullPath($Godot)
$preparedProject=[IO.Path]::GetFullPath($Project)
$inputRoot=[IO.Path]::GetFullPath($InputDirectory)
$outputRoot=[IO.Path]::GetFullPath($OutputDirectory)
if(-not (Test-Path -LiteralPath $enginePath -PathType Leaf)){throw "Godot executable unavailable: $enginePath"}
if(-not (Test-Path -LiteralPath (Join-Path $preparedProject 'project.godot') -PathType Leaf)){throw "Prepared project unavailable: $preparedProject"}
if(-not $Plan){New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null}
$cases=@(
    @{id='stability_a';mode='stability';source='160four'},
    @{id='stability_b';mode='stability';source='320four'},
    @{id='maximum_upper';mode='maximum_upper';source='160four'},
    @{id='preview_tall';mode='preview_tall';source='tall640'}
)
foreach($entry in $cases){
    if($CaseId -ne 'all' -and $CaseId -ne $entry.id){continue}
    $sourcePath=Join-Path $inputRoot ($entry.source+'.input.bin')
    $manifestPath=Join-Path $inputRoot ($entry.source+'.manifest.json')
    if(-not $Plan){
        if(-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "Successful original source missing: $($entry.source)"}
        $source=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if(-not $source.ok -or (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $source.input_sha256){throw "Original source identity changed: $sourcePath"}
    }
    $launchArguments=@('--headless','--path',$preparedProject,'--script','res://tools/performance/acceptance/fixtures/prepare_operations.gd','--',
        "--mode=$($entry.mode)","--id=$($entry.id)","--input=$sourcePath","--output-dir=$outputRoot",
        "--maximum-real-seconds=$MaximumRealSeconds","--maximum-steps=$MaximumSteps")
    if($entry.id -eq 'preview_tall'){
        $launchArguments=@('--headless','--path',$preparedProject,'--script','res://tools/performance/acceptance/fixtures/preflight_maximum_tall.gd','--',
            "--input=$sourcePath",('--output='+(Join-Path $outputRoot 'maximum_tall.preflight.json')))
    }
    if($Plan){[ordered]@{id=$entry.id;executable=$enginePath;arguments=$launchArguments}|ConvertTo-Json -Depth 8;continue}
    $logPath=Join-Path $outputRoot ($entry.id+'.preparation.log')
    if(Test-Path -LiteralPath $logPath){throw "Preserve prior attempt and choose a fresh directory: $logPath"}
    & $enginePath @launchArguments *> $logPath
    if($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $logPath -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)){
        Get-Content -LiteralPath $logPath -Tail 25
        throw "Original preparation incomplete: $($entry.id); original log retained at $logPath"
    }
}
