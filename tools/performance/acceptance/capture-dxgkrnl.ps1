#requires -Version 7.0
[CmdletBinding()]
param(
    [int]$TargetPid=0,
    [string]$TargetIdentityPath='',
    [string]$ReadyPath='',
    [Parameter(Mandatory)][string]$Output,
    [Parameter(Mandatory)][string]$StopPath,
    [ValidateRange(1,18000)][int]$TimeoutSeconds=900
)
# Opt-in separate resource trace. No calls are made merely by inspecting this file.
# Provider events remain system-wide because cross-process sharing must be joined.
$ErrorActionPreference='Stop'
$destination=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $destination){throw 'Use a new immutable trace directory.'}
New-Item -ItemType Directory -Path $destination | Out-Null
$target=$null;$targetStart=$null
if($TargetPid -gt 0){$target=Get-Process -Id $TargetPid -ErrorAction Stop;$targetStart=$target.StartTime.ToUniversalTime().Ticks}
elseif(-not $TargetIdentityPath){throw 'Supply TargetPid or a future owned target identity file.'}
$session='HospitalAlloc-'+[Guid]::NewGuid().ToString('N')
$started=$false;$failure=$null;$final=$null;$startedBeforeTarget=$TargetPid -eq 0
$provider=Get-WinEvent -ListProvider Microsoft-Windows-DxgKrnl
$events=@($provider.Events | Where-Object {$_.Task.Name -match 'Allocation|VidMmMakeResident|VidMmEvict|Device|Adapter|Segment' -or $_.Id -in @(110,367,371,373)})
[long]$mask=0
foreach($event in $events){foreach($keyword in $event.Keywords){$mask=$mask -bor $keyword.Value}}
if($mask -eq 0){throw 'No memory-event keyword metadata; refuse to invent a provider mask.'}
$keywordText='0x'+$mask.ToString('x16')
@($events | Select-Object Id,Version,Task,Opcode,Keywords,Template) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $destination 'provider-schema.json') -Encoding utf8NoBOM
try {
    if(-not ('HospitalTraceStatus' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'trace-status.cs')}
    $arguments=@('start',$session,'-ets','-o',(Join-Path $destination 'dxgkrnl.etl'),'-p',$provider.Id.ToString(),$keywordText,'5','-ct','perf','-bs','64','-nb','64','256')
    & logman @arguments *> (Join-Path $destination 'logman-start.log')
    if($LASTEXITCODE -ne 0){throw "Owned allocation trace could not start; logman exit $LASTEXITCODE"}
    $started=$true;$begin=[Diagnostics.Stopwatch]::GetTimestamp()
    if($ReadyPath){@{ready=$true;session=$session;qpc_ticks=$begin;qpc_frequency=[Diagnostics.Stopwatch]::Frequency;started_before_target=$startedBeforeTarget}|ConvertTo-Json|Set-Content -LiteralPath $ReadyPath -Encoding utf8NoBOM}
    while(-not (Test-Path -LiteralPath $StopPath)){
        if($null -eq $target -and $TargetIdentityPath -and (Test-Path -LiteralPath $TargetIdentityPath)){
            try{$identity=Get-Content -LiteralPath $TargetIdentityPath -Raw|ConvertFrom-Json -AsHashtable}catch{$identity=$null}
            if($identity){$TargetPid=[int]$identity.pid;$target=Get-Process -Id $TargetPid -ErrorAction Stop;$targetStart=[long]$identity.start_utc_ticks}
        }
        if($target){
            $target.Refresh()
            if($target.HasExited){break}
            if($target.StartTime.ToUniversalTime().Ticks -ne $targetStart){throw 'Target identity changed.'}
        }
        if(([Diagnostics.Stopwatch]::GetTimestamp()-$begin)/[Diagnostics.Stopwatch]::Frequency -gt $TimeoutSeconds){throw 'Allocation trace watchdog expired.'}
        Start-Sleep -Milliseconds 100
    }
} catch {$failure=$_.Exception.Message}
finally {
    if($started){$final=[HospitalTraceStatus]::Read($session,$true)}
    @{kind='dxgkrnl_allocation_trace';session=$session;target_pid=$TargetPid;target_start_utc_ticks=$targetStart;started_before_target=$startedBeforeTarget;qpc_frequency=[Diagnostics.Stopwatch]::Frequency;session_clock='performance_counter';provider_guid=$provider.Id.ToString();keyword_mask=$keywordText;events_selected=@($events | ForEach-Object {"$($_.Id):$($_.Version)"});all_processes_for_shared_aliases=$true;trace_final=$final;error=$failure;allocation_ledger_complete=$false;provider_metadata_does_not_prove_events_emitted=$true} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $destination 'trace.json') -Encoding utf8NoBOM
}
if($failure -or $final.code -ne 0){[Console]::Error.WriteLine(($failure ?? 'ETW final stop/statistics unavailable.'));exit 2}
Write-Output "ALLOCATION_TRACE=$destination"
