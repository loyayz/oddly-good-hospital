#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Godot,
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateSet('Base','Boundaries','History','All')][string]$Mode='Base',
    [ValidateSet('all','160four','320four','640wide','wide160','tall640')][string]$CaseId='all',
    [string]$SourceInput='',
    [ValidateRange(1,86400)][int]$MaximumRealSeconds=3600,
    [switch]$Plan
)
$ErrorActionPreference='Stop'
$preparedProject=[IO.Path]::GetFullPath($Project)
$outputRoot=[IO.Path]::GetFullPath($OutputDirectory)
$enginePath=[IO.Path]::GetFullPath($Godot)
if(-not (Test-Path -LiteralPath (Join-Path $preparedProject 'project.godot') -PathType Leaf)){throw "Prepared Godot project missing: $preparedProject"}
if(-not (Test-Path -LiteralPath $enginePath -PathType Leaf)){throw "Godot executable missing: $enginePath"}
if($SourceInput -and $CaseId -eq 'all'){throw 'SourceInput belongs to one actual case; specify CaseId.'}
if($SourceInput){$SourceInput=[IO.Path]::GetFullPath($SourceInput)}
if(-not $Plan){New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null}

function Invoke-Preparation([string]$Name,[string]$Script,[string[]]$UserArguments){
    $launchArguments=@('--headless','--path',$preparedProject,'--script',$Script,'--')+$UserArguments
    if($Plan){[ordered]@{name=$Name;executable=$enginePath;arguments=$launchArguments} | ConvertTo-Json -Depth 8; return}
    $logPath=Join-Path $outputRoot ($Name+'.log')
    if(Test-Path -LiteralPath $logPath){throw "Preparation log already exists: $logPath"}
    & $enginePath @launchArguments *> $logPath
    if($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $logPath -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)){
        Get-Content -LiteralPath $logPath -Tail 30
        throw "Preparation incomplete: $Name; preserve original log $logPath"
    }
}

if($Mode -in 'Base','All'){
    $userArguments=@("--case=$CaseId","--output-dir=$outputRoot",'--maximum-steps=4000',"--maximum-real-seconds=$MaximumRealSeconds")
    if($SourceInput){$userArguments+="--source-input=$SourceInput"}
    Invoke-Preparation ('base-'+$CaseId) 'res://tools/performance/acceptance/fixtures/prepare_inputs.gd' $userArguments
}
if($Mode -in 'Boundaries','All'){
    $baselinePath=Join-Path $outputRoot '160four.input.bin'
    if(-not $Plan -and -not (Test-Path -LiteralPath $baselinePath -PathType Leaf)){throw 'Prepare the genuine 160four input before named boundaries.'}
    foreach($boundary in 'clinical_midstep','day_boundary_before'){
        $targetPath=Join-Path $outputRoot ($boundary+'.input.bin')
        Invoke-Preparation $boundary 'res://tools/performance/acceptance/fixtures/prepare_boundary.gd' @(
            "--mode=$boundary","--input=$baselinePath","--output=$targetPath",'--maximum-steps=18000',"--maximum-real-seconds=$MaximumRealSeconds")
    }
    $dualSources=@(@{id='dual_a';source='160four'},@{id='dual_b';source='320four'})
    $dualRows=@()
    foreach($entry in $dualSources){
        $sourcePath=Join-Path $outputRoot ($entry.source+'.input.bin')
        $targetPath=Join-Path $outputRoot ($entry.id+'.input.bin')
        if($Plan){[ordered]@{copy_original_input=$sourcePath;to=$targetPath;rewrite_ids=$false} | ConvertTo-Json; continue}
        $metadataPath=Join-Path $outputRoot ($entry.source+'.manifest.json')
        if(-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or -not (Test-Path -LiteralPath $metadataPath -PathType Leaf)){throw "Missing actual source and successful manifest: $($entry.source)"}
        $metadata=Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        if(-not $metadata.ok -or (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $metadata.input_sha256){throw "Source identity changed: $sourcePath"}
        if(Test-Path -LiteralPath $targetPath){throw "Dual input already exists: $targetPath"}
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath
        $dualRows+= [ordered]@{id=$entry.id;input_path=$targetPath;hospital_id=$metadata.hospital_id;population=$metadata.population;sha256=$metadata.input_sha256}
    }
    if(-not $Plan){
        if($dualRows[0].hospital_id -eq $dualRows[1].hospital_id){throw 'Dual inputs must retain distinct original UUID hospitals.'}
        [ordered]@{schema_version=1;preparation_only=$true;inputs=$dualRows;next_operation='Original Library.create and Snapshot commits in isolated formal profile; original checkpoint/continue for switch.'} |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputRoot 'dual-plan.json') -Encoding utf8NoBOM
    }
}
if($Mode -in 'History','All'){
    $baselinePath=Join-Path $outputRoot '160four.input.bin'
    Invoke-Preparation 'history-size' 'res://tools/performance/acceptance/fixtures/legal_history_size.gd' @("--input=$baselinePath","--output-dir=$outputRoot")
}

# Preparation is a separate process. No Release sample or performance pass is
# inferred from this command. All outputs keep their original runtime evidence.
