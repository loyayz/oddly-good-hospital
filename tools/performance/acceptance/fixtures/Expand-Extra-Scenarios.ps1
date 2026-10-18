#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputDirectory,
    [Parameter(Mandatory)][string]$ScenarioDirectory,
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [string[]]$GroupId=@('STABILITY','PREVIEW85','PREVIEW96FAIL','PREVIEW96UPPER'),
    [string]$BaseInputDirectory=''
)
$ErrorActionPreference='Stop'
$inputRoot=[IO.Path]::GetFullPath($InputDirectory)
$baseRoot=if($BaseInputDirectory){[IO.Path]::GetFullPath($BaseInputDirectory)}else{$inputRoot}
$scenarioRoot=[IO.Path]::GetFullPath($ScenarioDirectory)
$evidenceRoot=[IO.Path]::GetFullPath($EvidenceDirectory)
$matrix=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'extra_scenarios.json') -Raw | ConvertFrom-Json -AsHashtable
$knownIds=@($matrix.groups | ForEach-Object {$_.id})
foreach($id in $GroupId){if($id -notin $knownIds){throw "Unknown extra group: $id"}}
$balancePath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../docs/data/balance.json'))
$targets=(Get-Content -LiteralPath $balancePath -Raw | ConvertFrom-Json).performance_targets.capture
$loaded=@{}
function Read-OriginalInput([string]$Id){
    if($loaded.ContainsKey($Id)){return $loaded[$Id]}
    $folder=if($Id -eq 'tall640'){$baseRoot}else{$inputRoot}
    $inputPath=Join-Path $folder ($Id+'.input.bin')
    $manifestPath=Join-Path $folder ($Id+'.manifest.json')
    if(-not (Test-Path -LiteralPath $inputPath -PathType Leaf) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "Generated input/manifest missing: $Id"}
    $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $hash=(Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if(-not $manifest.ok -or $hash -ne $manifest.input_sha256 -or [int]$manifest.population.present -le 0){throw "Input identity/actual population not qualified for current runner: $Id"}
    if($Id -in 'stability_a','stability_b'){
        if($manifest.details.actual_rooms -ne 65 -or @($manifest.details.rotation_preflight).Count -ne 2 -or @($manifest.details.rotation_preflight|Where-Object {-not $_.ok}).Count){throw "Original bidirectional room preflight missing: $Id"}
    }
    if($Id -eq 'maximum_upper'){
        if($manifest.details.target_floor -ne 5 -or @($manifest.details.construction_order_ids).Count -ne 9 -or -not $manifest.details.original_load_and_traffic_retained -or -not $manifest.details.maximum_preview.ok -or $manifest.details.maximum_preview.price -ne 364850){throw 'Original fifth-floor construction evidence incomplete'}
    }
    if($Id -eq 'tall640'){
        $preflightPath=Join-Path $inputRoot 'maximum_tall.preflight.json'
        if(-not (Test-Path -LiteralPath $preflightPath -PathType Leaf)){throw 'Run the isolated original tall correctness preflight before expanding its maximum-preview scenes'}
        $preflight=Get-Content -LiteralPath $preflightPath -Raw | ConvertFrom-Json
        if(-not $preflight.ok -or $preflight.source_sha256 -ne $hash -or @($preflight.observations).Count -ne 2){throw 'Original tall maximum preflight source/outcomes do not match this input'}
    }
    $loaded[$Id]=@{path=[IO.Path]::GetFullPath($inputPath);manifest_path=[IO.Path]::GetFullPath($manifestPath);manifest=$manifest;hash=$hash}
    return $loaded[$Id]
}
New-Item -ItemType Directory -Force -Path $scenarioRoot | Out-Null
$rows=@()
foreach($group in $matrix.groups){
    if($group.id -notin $GroupId){continue}
    $source=Read-OriginalInput $group.input_id
    if($source.manifest.layout -ne $group.layout){throw "Actual layout mismatch: $($group.id)"}
    $settings=[ordered]@{}
    foreach($key in $matrix.defaults.Keys){$settings[$key]=$matrix.defaults[$key]}
    foreach($key in $group.Keys){$settings[$key]=$group[$key]}
    $settings.actors=[int]$source.manifest.population.present
    $settings.input_path=$source.path
    $settings.input_sha256=$source.hash
    $settings.input_manifest_path=$source.manifest_path
    if($group.input_id -eq 'tall640'){$settings.input_preflight_path=Join-Path $inputRoot 'maximum_tall.preflight.json'}
    $settings.minimum_frame_samples=[int]$targets.minimum_frame_samples
    $settings.minimum_step_samples=[int]$targets.minimum_step_samples
    $settings.run_id=[Guid]::NewGuid().ToString()
    $settings.group_id=$group.id
    $settings.output_dir=Join-Path $evidenceRoot ($group.id+'-'+$settings.run_id)
    $expandedOperations=@()
    foreach($operation in $group.operations){
        $expanded=[ordered]@{}
        foreach($key in $operation.Keys){$expanded[$key]=$operation[$key]}
        if($operation.ContainsKey('seed_input_id')){
            $seed=Read-OriginalInput $operation.seed_input_id
            if($seed.manifest.hospital_id -eq $source.manifest.hospital_id){throw 'Library seed must retain a genuinely distinct original hospital UUID'}
            $expanded.input_path=$seed.path
            $expanded.seed_input_sha256=$seed.hash
            $expanded.seed_hospital_id=$seed.manifest.hospital_id
        }
        if($operation.ContainsKey('hospital_input_id')){
            $target=Read-OriginalInput $operation.hospital_input_id
            $expanded.hospital_id=$target.manifest.hospital_id
            $expanded.snapshot_id='' # Original latest committed checkpoint, never the initial seed on return.
        }
        $expandedOperations+=$expanded
    }
    $settings.operations=$expandedOperations
    $targetPath=Join-Path $scenarioRoot ($group.id+'.json')
    if(Test-Path -LiteralPath $targetPath){throw "Preserve existing configuration: $targetPath"}
    $settings | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $targetPath -Encoding utf8NoBOM
    $rows+=[ordered]@{group_id=$group.id;scenario=$targetPath;actual_start_population=$settings.actors;input_sha256=$source.hash;output_dir=$settings.output_dir}
}
[ordered]@{schema_version=1;groups=$rows;qualification='Unexecuted operation configurations; original preparation, owner receipts, actual work gate, OS-input/displayed endpoints and full metric populations remain required.'} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $scenarioRoot 'extra-index.json') -Encoding utf8NoBOM
$rows | ConvertTo-Json -Depth 5
