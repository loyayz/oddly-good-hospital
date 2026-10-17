#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Etl,
    [Parameter(Mandatory)][string]$Schema,
    [Parameter(Mandatory)][string]$Output,
    [string]$EventIds=''
)
$ErrorActionPreference='Stop'
if(-not $IsWindows -or [IntPtr]::Size -ne 8){throw 'Windows x64 PowerShell is required.'}
$etlPath=(Resolve-Path -LiteralPath $Etl).Path
$schemaPath=(Resolve-Path -LiteralPath $Schema).Path
$outputPath=[IO.Path]::GetFullPath($Output)
$metadataPath=$outputPath+'.meta.json'
if((Test-Path -LiteralPath $outputPath) -or (Test-Path -LiteralPath $metadataPath)){throw 'Use new output and metadata paths; existing evidence is immutable.'}
if(-not (Test-Path -LiteralPath (Split-Path -Parent $outputPath) -PathType Container)){throw 'Output parent must already exist.'}
$sourceHash=(Get-FileHash -LiteralPath $etlPath -Algorithm SHA256).Hash.ToLowerInvariant()
$schemaHash=(Get-FileHash -LiteralPath $schemaPath -Algorithm SHA256).Hash.ToLowerInvariant()
$selectedIds=[Collections.Generic.List[int]]::new()
if($EventIds){
    foreach($part in $EventIds.Split(',')){
        [ushort]$id=0
        if(-not [ushort]::TryParse($part.Trim(),[ref]$id)){throw 'EventIds must be comma-separated decimal IDs in 0..65535.'}
        if(-not $selectedIds.Contains([int]$id)){$selectedIds.Add([int]$id)}
    }
}
$readerPath=Join-Path $PSScriptRoot 'decode-etl.cs'
$readerHash=(Get-FileHash -LiteralPath $readerPath -Algorithm SHA256).Hash.ToLowerInvariant()
if('HospitalRawEtlReader' -as [type]){throw 'Use a fresh pwsh process to compile and identify this reader source.'}
Add-Type -Path $readerPath
$definitions=[Collections.Generic.List[HospitalRawEtlReader+EventSchema]]::new()
$schemaRows=@(Get-Content -LiteralPath $schemaPath -Raw|ConvertFrom-Json -AsHashtable)
foreach($row in $schemaRows){
    if($null -eq $row.Id -or $null -eq $row.Version){throw 'Schema requires exact Id and Version.'}
    $task=if($null -ne $row.Task.Value){[int]$row.Task.Value}else{-1}
    $opcode=if($null -ne $row.Opcode.Value){[int]$row.Opcode.Value}else{-1}
    $definitions.Add([HospitalRawEtlReader+EventSchema]::new([int]$row.Id,[int]$row.Version,$task,$opcode,[string]$row.Task.Name,[string]$row.Template))
}
$result=$null;$errorText=$null
try{$result=[HospitalRawEtlReader]::Read($etlPath,$outputPath,$definitions.ToArray(),$selectedIds.ToArray())}
catch{$errorText=$_.Exception.Message}
$afterHash=(Get-FileHash -LiteralPath $etlPath -Algorithm SHA256).Hash.ToLowerInvariant()
if($afterHash -ne $sourceHash){$errorText='ETL changed during offline read.'}
$schemaAfter=(Get-FileHash -LiteralPath $schemaPath -Algorithm SHA256).Hash.ToLowerInvariant()
if($schemaAfter -ne $schemaHash){$errorText='Provider schema changed during offline read.'}
if((Get-FileHash -LiteralPath $readerPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $readerHash){$errorText='Reader source changed after compilation.'}
$metadata=@{
    schema_version=1;kind='offline_raw_etl_decode';status=if($errorText){'incomplete'}else{$result.Status}
    etl_path=$etlPath;etl_sha256=$sourceHash;etl_sha256_after=$afterHash
    schema_path=$schemaPath;schema_sha256=$schemaHash;schema_sha256_after=$schemaAfter
    reader_path=$readerPath;reader_sha256=$readerHash
    wrapper_path=$PSCommandPath;wrapper_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    output=$outputPath;output_sha256=if(Test-Path -LiteralPath $outputPath){(Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()}else{$null}
    provider_guid='802ec45a-1e99-4b83-9920-87c98277ba9d'
    process_trace_mode='EVENT_RECORD|RAW_TIMESTAMP';process_trace_mode_bits='0x10001000'
    raw_timestamp_is_unconverted_header_timestamp=$true
    qpc_ticks_are_raw_header_timestamp=if($result){$result.RawQpcValid}else{$false}
    qpc_frequency=if($result -and $result.RawQpcValid){$result.TraceHeader['perf_frequency']}else{$null}
    raw_qpc_valid=if($result){$result.RawQpcValid}else{$false}
    selected_event_ids=$selectedIds.ToArray()
    sequence_basis='1-based ordinal of all DxgKrnl records, including filtered-out records'
    selection_scope=if($selectedIds.Count){'only selected IDs decoded; not all provider events'}else{'all DxgKrnl records decoded'}
    result=$result;tool_error=$errorText;layout=[HospitalRawEtlReader]::Layout()
    scope='readability/typed fields only; not allocation ledger or residency acceptance'
}
[IO.File]::WriteAllText($metadataPath,($metadata|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
Write-Output ('RAW_ETL_DECODE='+($metadata|Select-Object status,output,raw_qpc_valid,qpc_frequency|ConvertTo-Json -Compress))
if($errorText -or -not $result -or $result.Status -ne 'decoded'){exit 2}
exit 0
