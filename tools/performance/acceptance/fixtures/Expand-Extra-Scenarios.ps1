#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputDirectory,
    [Parameter(Mandatory)][string]$ScenarioDirectory,
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [string[]]$GroupId=@(),
    [string]$BaseInputDirectory='',
    [string]$BoundaryInputDirectory='',
    [string]$HistoryInputDirectory=''
)
$ErrorActionPreference='Stop'
$inputRoot=[IO.Path]::GetFullPath($InputDirectory)
$baseRoot=if($BaseInputDirectory){[IO.Path]::GetFullPath($BaseInputDirectory)}else{$inputRoot}
$boundaryRoot=if($BoundaryInputDirectory){[IO.Path]::GetFullPath($BoundaryInputDirectory)}else{$baseRoot}
$historyRoot=if($HistoryInputDirectory){[IO.Path]::GetFullPath($HistoryInputDirectory)}else{$baseRoot}
$scenarioRoot=[IO.Path]::GetFullPath($ScenarioDirectory)
$evidenceRoot=[IO.Path]::GetFullPath($EvidenceDirectory)
$matrix=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'extra_scenarios.json') -Raw | ConvertFrom-Json -AsHashtable
$contracts=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'inputs.json') -Raw | ConvertFrom-Json -AsHashtable
$knownIds=@($matrix.groups | ForEach-Object {$_.id})
if($GroupId.Count -eq 0){$GroupId=$knownIds}
foreach($id in $GroupId){if($id -notin $knownIds){throw "Unknown extra group: $id"}}
$performanceTargets=(Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../../../docs/data/balance.json') -Raw | ConvertFrom-Json -AsHashtable).performance_targets
$targets=$performanceTargets.capture
if($targets.minimum_frame_samples -lt 1000 -or $targets.minimum_step_samples -lt 1000){throw 'Current full-capture minima must retain at least 1000 frames and complete steps.'}
$driverSource=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../operation_driver.gd') -Raw
$actionMatch=[regex]::Match($driverSource,'(?m)^const ACTIONS:[^\r\n=]+=\s*(\[[^\r\n]*\])')
if(-not $actionMatch.Success){throw 'Cannot verify the current original operation-driver interface.'}
$supportedActions=@('panel','floor','overview','pan','zoom','save')+@($actionMatch.Groups[1].Value | ConvertFrom-Json)
$loaded=@{}

function Read-Json([string]$Path){
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw "Original preparation report missing: $Path"}
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}
function Confirm-Hash([string]$Path,[string]$Expected){
    if($Expected -notmatch '^[0-9a-fA-F]{64}$' -or -not (Test-Path -LiteralPath $Path -PathType Leaf)){throw "Original file/hash missing: $Path"}
    $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ne $Expected.ToLowerInvariant()){throw "Prepared source identity changed: $Path"}
    return $actual
}
function Read-OriginalInput([string]$Id,[string]$SourceKind){
    $key="${SourceKind}:$Id"
    if($loaded.ContainsKey($key)){return $loaded[$key]}
    $contract=@($contracts.inputs | Where-Object {$_.id -eq $Id})
    if($contract.Count -ne 1){throw "Unknown/ambiguous input contract: $Id"}
    $contract=$contract[0]
    $expectedKind=switch($contract.mode){'base'{'base'} 'stability'{'operation'} 'maximum_upper'{'operation'} 'clinical_midstep'{'boundary'} 'day_boundary_before'{'boundary'} 'legal_history'{'history'} default{throw "Unsupported original input kind: $Id"}}
    if($SourceKind -ne $expectedKind){throw "Input source_kind mismatch: $Id / $SourceKind"}
    $folder=switch($SourceKind){'base'{$baseRoot} 'operation'{$inputRoot} 'boundary'{$boundaryRoot} 'history'{$historyRoot}}
    $inputPath=Join-Path $folder $contract.input_file
    $manifestPath=Join-Path $folder $contract.manifest_file
    $manifest=Read-Json $manifestPath
    $entry=$null
    $source=$null
    if($SourceKind -eq 'history'){
        # The original history report has outputs[], not ok/input_sha256/UUID.
        # Read its successful entry and base identity; do not mint a manifest.
        $source=Read-OriginalInput '160four' 'base'
        if($manifest.source_sha256 -ne $source.hash -or $manifest.content_fingerprint -ne $source.content_fingerprint){throw "History source/content identity mismatch: $Id"}
        $targetMib=if($Id -eq 'history_64mib'){64}else{128}
        $entries=@($manifest.outputs | Where-Object {[int]$_.target_mib -eq $targetMib})
        if($entries.Count -ne 1){throw "Original successful history entry missing/ambiguous: $Id"}
        $entry=$entries[0]
        if([IO.Path]::GetFileName([string]$entry.path) -ne $contract.input_file -or [IO.Path]::GetFileName([string]$entry.world_json) -ne $contract.world_json_file){throw "History output names disagree with original report: $Id"}
        if($manifest.preparation_only -ne $true -or -not $entry.Contains('validation') -or $entry.validation -ne '' -or $entry.original_facts_and_rng_preserved -isnot [bool] -or -not $entry.original_facts_and_rng_preserved -or $entry.present_actors -ne $source.population.present -or $entry.active_visits -le 0 -or $entry.added_archived_visits -le 0){throw "History facts/population qualification failed: $Id"}
        $hash=Confirm-Hash $inputPath $entry.sha256
        $worldJsonPath=Join-Path $folder $contract.world_json_file
        $worldJsonHash=Confirm-Hash $worldJsonPath $entry.world_json_sha256
        if((Get-Item -LiteralPath $inputPath).Length -ne $entry.fixture_file_bytes -or (Get-Item -LiteralPath $worldJsonPath).Length -ne $entry.canonical_world_json_bytes -or $entry.canonical_world_json_bytes -lt $contract.minimum_canonical_world_json_bytes){throw "History canonical/binary size mismatch: $Id"}
        $population=@{}
        foreach($field in $source.population.Keys){$population[$field]=$source.population[$field]}
        $population.present=[int]$entry.present_actors
        $hospitalId=$source.hospital_id
        $layout=$source.layout
        $contentFingerprint=$manifest.content_fingerprint
        $tick=$source.tick
    }else{
        if($manifest.ok -isnot [bool] -or -not $manifest.ok -or -not $manifest.Contains('validation') -or $manifest.validation -ne ''){throw "Original successful input manifest missing: $Id"}
        $hash=Confirm-Hash $inputPath $manifest.input_sha256
        $population=$manifest.population
        $hospitalId=[string]$manifest.hospital_id
        $contentFingerprint=[string]$manifest.content_fingerprint
        if($SourceKind -eq 'base'){
            $layout=[string]$manifest.layout
            $tick=[int]$manifest.source_tick
            if($manifest.id -ne $Id -or $layout -ne $contract.layout -or $population.present -ne $contract.actors -or $manifest.original_object_ids_and_definitions_preserved -ne $true){throw "Original complete base load not qualified: $Id"}
        }else{
            $source=Read-OriginalInput $contract.source 'base'
            if($manifest.source_sha256 -ne $source.hash -or $hospitalId -ne $source.hospital_id -or $contentFingerprint -ne $source.content_fingerprint){throw "Named input original source identity mismatch: $Id"}
            $layout=$source.layout
            $tick=[int]$manifest.tick
            if($SourceKind -eq 'boundary' -and $manifest.mode -ne $Id){throw "Named boundary mode mismatch: $Id"}
            if($SourceKind -eq 'operation' -and ($manifest.id -ne $Id -or $manifest.layout -ne $layout)){throw "Operation input identity mismatch: $Id"}
        }
    }
    $parsedUuid=[Guid]::Empty
    if(-not [Guid]::TryParse($hospitalId,[ref]$parsedUuid) -or [int]$population.present -le 0 -or [string]::IsNullOrEmpty($contentFingerprint)){throw "Actual population/UUID/content identity not qualified: $Id"}
    if($population.Contains('unowned') -and @($population.unowned).Count -ne 0){throw "Unowned present actors in original input: $Id"}
    if($Id -in 'stability_a','stability_b'){
        if($manifest.details.actual_rooms -ne 65 -or @($manifest.details.rotation_preflight).Count -ne 2 -or @($manifest.details.rotation_preflight | Where-Object {-not $_.ok}).Count){throw "Original bidirectional room preflight missing: $Id"}
    }
    if($Id -eq 'maximum_upper'){
        if($manifest.details.target_floor -ne 5 -or @($manifest.details.construction_order_ids).Count -ne 9 -or -not $manifest.details.original_load_and_traffic_retained -or -not $manifest.details.maximum_preview.ok -or $manifest.details.maximum_preview.price -ne 364850){throw 'Original fifth-floor construction evidence incomplete'}
    }
    if($Id -eq 'clinical_midstep'){
        $w=$manifest.witness
        if($w.owner -ne 'session' -or $w.kind -notin @('outpatient','surgery') -or [string]::IsNullOrEmpty($w.id) -or $w.remaining_ticks -lt 64 -or $w.remaining_ticks -ge $w.total_ticks){throw 'Original unfinished clinical Session witness missing'}
    }
    if($Id -eq 'day_boundary_before'){
        if($manifest.pre_boundary_margin_ticks -ne 64 -or $manifest.target_executed_tick -ne $tick+64 -or $manifest.target_completed_tick -ne $manifest.target_executed_tick+1 -or $manifest.target_day_index -lt 2){throw 'Original day boundary fields are inconsistent'}
    }
    $value=@{id=$Id;source_kind=$SourceKind;path=[IO.Path]::GetFullPath($inputPath);manifest_path=[IO.Path]::GetFullPath($manifestPath);manifest=$manifest;entry=$entry;hash=$hash;population=$population;hospital_id=$hospitalId;layout=$layout;content_fingerprint=$contentFingerprint;tick=$tick}
    if($source){$value.source_input_sha256=$source.hash;$value.source_manifest_path=$source.manifest_path}
    if($SourceKind -eq 'history'){$value.world_json_path=$worldJsonPath;$value.world_json_sha256=$worldJsonHash;$value.canonical_world_json_bytes=$entry.canonical_world_json_bytes;$value.fixture_file_bytes=$entry.fixture_file_bytes}
    $loaded[$key]=$value
    return $value
}

# Resolve all selected original inputs and operations before writing anything.
$prepared=@()
foreach($group in $matrix.groups){
    if($group.id -notin $GroupId){continue}
    $source=Read-OriginalInput $group.input_id $group.source_kind
    if($source.layout -ne $group.layout){throw "Actual source layout mismatch: $($group.id)"}
    $settings=[ordered]@{}
    foreach($key in $matrix.defaults.Keys){$settings[$key]=$matrix.defaults[$key]}
    foreach($key in $group.Keys){$settings[$key]=$group[$key]}
    $settings.actors=[int]$source.population.present
    $settings.actual_start_population=$source.population
    $settings.hospital_id=$source.hospital_id
    $settings.content_fingerprint=$source.content_fingerprint
    $settings.input_path=$source.path
    $settings.input_sha256=$source.hash
    $settings.input_manifest_path=$source.manifest_path
    $settings.input_manifest_source_kind=$source.source_kind
    $settings.input_manifest_entry=if($source.source_kind -eq 'history'){@{target_mib=$source.entry.target_mib;source_sha256=$source.source_input_sha256;world_json_path=$source.world_json_path;world_json_sha256=$source.world_json_sha256;canonical_world_json_bytes=$source.canonical_world_json_bytes;fixture_file_bytes=$source.fixture_file_bytes;active_visits=$source.entry.active_visits;added_archived_visits=$source.entry.added_archived_visits;identity_basis='Original history outputs entry plus verified unchanged base UUID/population; consumer independently validates binary facts.'}}else{@{id=$source.id;tick=$source.tick}}
    if($source.Contains('source_manifest_path')){$settings.source_manifest_path=$source.source_manifest_path}
    if($group.input_id -eq 'tall640'){
        $preflightPath=Join-Path $inputRoot 'maximum_tall.preflight.json'
        $preflight=Read-Json $preflightPath
        if(-not $preflight.ok -or $preflight.source_sha256 -ne $source.hash -or $preflight.content_fingerprint -ne $source.content_fingerprint -or @($preflight.observations).Count -ne 2 -or @($preflight.observations | Where-Object {-not $_.readonly -or -not $_.outcome_matches}).Count){throw 'Original tall correctness preflight source/outcomes do not match this input'}
        $settings.input_preflight_path=$preflightPath
    }
    if($group.required_session_from_input){$settings.required_session=$source.manifest.witness}
    $settings.Remove('required_session_from_input')
    $settings.minimum_frame_samples=[int]$targets.minimum_frame_samples
    $settings.minimum_step_samples=[int]$targets.minimum_step_samples
    $settings.run_id=[Guid]::NewGuid().ToString()
    $settings.group_id=$group.id
    $settings.output_dir=Join-Path $evidenceRoot ($group.id+'-'+$settings.run_id)
    if($group.preview_threshold_key){
        if(-not $performanceTargets.metrics.Contains($group.preview_threshold_key)){throw "Unknown original preview threshold key: $($group.preview_threshold_key)"}
        $settings.preview_threshold_ms=$performanceTargets.metrics[$group.preview_threshold_key]
    }
    $operations=@($group.operations)
    if($group.Contains('preview_series')){
        $series=$group.preview_series
        if([int]$series.count -lt 20 -or $series.operation.action -ne 'preview_input' -or $series.operation.cancel_after -ne $true){throw "Independent cancelled preview series needs at least 20 real requests: $($group.id)"}
        $operations+=@{id=($series.id_prefix+'-initial-cancel');action='cancel_build_preview';after_real_seconds=0}
        for($index=1;$index -le [int]$series.count;$index++){
            $request=[ordered]@{}
            foreach($key in $series.operation.Keys){$request[$key]=$series.operation[$key]}
            $request.id=('{0}-{1:d2}' -f $series.id_prefix,$index)
            $request.preview_request_index=$index
            $request.preview_job_cache_class='new_job_after_original_cancel'
            $request.preview_process_cache_class=if($index -eq 1){'first_measured_request_after_original_control_preparation'}else{'later_process_reuse_with_new_job'}
            $request.preview_statistical_cohort=if($index -eq 1){'first_process_request'}else{'later_process_reuse_job_cold'}
            $dimensionIndex=if($request.field -eq 'height'){1}else{0}
            if([int]$request.initial_value -eq [int]$request.size[$dimensionIndex]){throw "Preview must really change its measured dimension: $($request.id)"}
            $operations+=$request
        }
        $operations+=@($group.trailing_operations)
        $settings.preview_sample_qualification='At least 20 complete independent OS-input requests. All jobs cold; first-process request separate. Configuration counts are not measured completions or displayed endpoints.'
    }
    $settings.Remove('preview_series')
    $settings.Remove('trailing_operations')
    $expandedOperations=@()
    $operationIds=@{}
    $manualSaveIds=@{}
    $currentHospital=$source.hospital_id
    foreach($operation in $operations){
        if([string]::IsNullOrEmpty($operation.id) -or $operationIds.ContainsKey($operation.id)){throw "Empty/duplicate actual operation id: $($group.id)"}
        if($operation.action -notin $supportedActions){throw "Action is not supported by the current original driver: $($operation.action)"}
        $operationIds[$operation.id]=$true
        $expanded=[ordered]@{}
        foreach($key in $operation.Keys){$expanded[$key]=$operation[$key]}
        if($operation.action -eq 'save'){$manualSaveIds[$operation.id]=$true}
        if($operation.required_session_from_input){$expanded.required_session=$source.manifest.witness}
        $expanded.Remove('required_session_from_input')
        if($operation.boundary_from_input){
            if($source.id -ne 'day_boundary_before'){throw 'Day boundary operation needs its real named source'}
            foreach($key in @('target_executed_tick','target_completed_tick','target_day_index')){$expanded[$key]=$source.manifest[$key]}
            if([int]$settings.warmup_minimum_actual_steps -ge [int]$source.manifest.pre_boundary_margin_ticks){throw 'Warmup already consumes the entire named boundary margin'}
        }
        $expanded.Remove('boundary_from_input')
        if($operation.Contains('seed_input_id')){
            $kind=if($operation.seed_source_kind){$operation.seed_source_kind}else{$group.source_kind}
            $seed=Read-OriginalInput $operation.seed_input_id $kind
            if($seed.hospital_id -eq $currentHospital){throw 'Library seed must retain a genuinely distinct original hospital UUID'}
            if($seed.content_fingerprint -ne $source.content_fingerprint){throw 'Seed and source must use the same actual content identity'}
            $expanded.input_path=$seed.path
            $expanded.seed_input_sha256=$seed.hash
            $expanded.seed_hospital_id=$seed.hospital_id
            $expanded.seed_population=$seed.population
            $expanded.seed_manifest_path=$seed.manifest_path
        }
        if($operation.Contains('hospital_input_id')){
            $kind=if($operation.hospital_source_kind){$operation.hospital_source_kind}else{$group.source_kind}
            $target=Read-OriginalInput $operation.hospital_input_id $kind
            if($target.hospital_id -eq $currentHospital){throw "Switch must change actual hospital UUID: $($operation.id)"}
            if($target.content_fingerprint -ne $source.content_fingerprint){throw 'Switch inputs must use the same actual content identity'}
            $expanded.hospital_id=$target.hospital_id
            $expanded.target_input_sha256=$target.hash
            $expanded.target_population=$target.population
            $expanded.target_manifest_path=$target.manifest_path
            if($operation.snapshot_operation_id){
                if(-not $manualSaveIds.ContainsKey($operation.snapshot_operation_id)){throw "Snapshot must refer to an earlier actual manual-save operation: $($operation.id)"}
            }else{$expanded.snapshot_id=''} # Stability returns keep the original latest committed checkpoint.
            $currentHospital=$target.hospital_id
        }
        $expandedOperations+=$expanded
    }
    $settings.operations=$expandedOperations
    $targetPath=Join-Path $scenarioRoot ($group.id+'.json')
    if(Test-Path -LiteralPath $targetPath){throw "Preserve existing configuration: $targetPath"}
    $prepared+=@{settings=$settings;target_path=$targetPath}
}
$indexPath=Join-Path $scenarioRoot 'extra-index.json'
if(Test-Path -LiteralPath $indexPath){throw "Preserve existing configuration index: $indexPath"}
New-Item -ItemType Directory -Force -Path $scenarioRoot | Out-Null
$rows=@()
foreach($item in $prepared){
    $settings=$item.settings
    $settings | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $item.target_path -Encoding utf8NoBOM
    $rows+=[ordered]@{group_id=$settings.group_id;scenario=$item.target_path;source_kind=$settings.source_kind;actual_start_population=$settings.actual_start_population;hospital_id=$settings.hospital_id;input_sha256=$settings.input_sha256;input_manifest_path=$settings.input_manifest_path;output_dir=$settings.output_dir}
}
[ordered]@{schema_version=1;groups=$rows;qualification='Unexecuted operation configurations. Original reports/source hashes, owner receipts, work/wait gates, actual snapshot witnesses, OS input, displayed endpoints, full metric populations and independent correctness/resource evidence remain required.'} |
    ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $indexPath -Encoding utf8NoBOM
$rows | ConvertTo-Json -Depth 8
