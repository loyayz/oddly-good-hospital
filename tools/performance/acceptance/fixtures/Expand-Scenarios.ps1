#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputDirectory,
    [Parameter(Mandatory)][string]$ScenarioDirectory,
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [string[]]$GroupId=@('B1','B3','D1','D3','C320','W160','T640')
)
$ErrorActionPreference='Stop'
$inputRoot=[IO.Path]::GetFullPath($InputDirectory)
$scenarioRoot=[IO.Path]::GetFullPath($ScenarioDirectory)
$evidenceRoot=[IO.Path]::GetFullPath($EvidenceDirectory)
$matrix=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'scenarios.json') -Raw | ConvertFrom-Json -AsHashtable
$balancePath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../docs/data/balance.json'))
$currentTargets=(Get-Content -LiteralPath $balancePath -Raw | ConvertFrom-Json).performance_targets.capture
$knownIds=@($matrix.groups | ForEach-Object { $_.id })
foreach($requestedId in $GroupId){if($requestedId -notin $knownIds){throw "Unknown group: $requestedId"}}
New-Item -ItemType Directory -Force -Path $scenarioRoot | Out-Null
$rows=@()
foreach($group in $matrix.groups){
    if($group.id -notin $GroupId){continue}
    $sourcePath=Join-Path $inputRoot $group.input_file
    $manifestPath=Join-Path $inputRoot ($group.input_id+'.manifest.json')
    if(-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "Actual generated input/manifest missing: $sourcePath"}
    $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if(-not $manifest.ok -or $manifest.population.present -ne $group.actors -or $manifest.layout -ne $group.layout){throw "Input is not the requested actual load: $sourcePath"}
    $actualHash=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actualHash -ne $manifest.input_sha256){throw "Input changed after preparation: $sourcePath"}
    $scenarioSettings=[ordered]@{}
    foreach($key in $matrix.defaults.Keys){$scenarioSettings[$key]=$matrix.defaults[$key]}
    foreach($key in $group.Keys){$scenarioSettings[$key]=$group[$key]}
    $runId=[Guid]::NewGuid().ToString()
    $scenarioSettings.run_id=$runId
    $scenarioSettings.group_id=$group.id
    $scenarioSettings.input_path=[IO.Path]::GetFullPath($sourcePath)
    $scenarioSettings.input_sha256=$actualHash
    $scenarioSettings.input_manifest_path=[IO.Path]::GetFullPath($manifestPath)
    $scenarioSettings.output_dir=Join-Path $evidenceRoot ($group.id+'-'+$runId)
    $scenarioSettings.minimum_frame_samples=[int]$currentTargets.minimum_frame_samples
    $scenarioSettings.minimum_step_samples=[int]$currentTargets.minimum_step_samples
    $targetPath=Join-Path $scenarioRoot ($group.id+'.json')
    if(Test-Path -LiteralPath $targetPath){throw "Scenario already exists; choose a fresh directory: $targetPath"}
    $scenarioSettings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $targetPath -Encoding utf8NoBOM
    $rows+= [ordered]@{group_id=$group.id;scenario=$targetPath;input_sha256=$actualHash;output_dir=$scenarioSettings.output_dir}
}
[ordered]@{schema_version=1;groups=$rows;qualification='Unexecuted configs; UI independently validates facts, actual population/floors and all visible density/sample evidence.'} |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $scenarioRoot 'index.json') -Encoding utf8NoBOM
$rows | ConvertTo-Json -Depth 5
