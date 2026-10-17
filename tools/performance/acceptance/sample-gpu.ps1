#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$TargetPid,
    [Parameter(Mandatory)][long]$TargetStartUtcTicks,
    [Parameter(Mandatory)][string]$Output,
    [Parameter(Mandatory)][string]$StopPath,
    [ValidateRange(250,10000)][int]$IntervalMs = 1000
)
$ErrorActionPreference = 'Stop'
function Counter-Value($Instance,[string]$Name) {
    $property=$Instance.CimInstanceProperties[$Name]
    if($null -eq $property -or $null -eq $property.Value){return $null}
    return [long]$property.Value
}
if(Test-Path -LiteralPath $Output){throw 'GPU evidence already exists; use a new output path.'}
$writer = [IO.StreamWriter]::new($Output,$false,[Text.UTF8Encoding]::new($false))
try {
    while (-not (Test-Path -LiteralPath $StopPath)) {
        $started = [Diagnostics.Stopwatch]::GetTimestamp()
        try {
            $target = Get-Process -Id $TargetPid -ErrorAction Stop
            if ($target.StartTime.ToUniversalTime().Ticks -ne $TargetStartUtcTicks) { break }
            # The class name and properties were verified from local CIM metadata.
            # Keep each PID/LUID/physical-adapter instance separate. These are
            # aggregate OS counters, never allocation identities or net bytes.
            $instances = @(Get-CimInstance -Namespace root/cimv2 -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory -Filter "Name LIKE 'pid_$($TargetPid)_%'" -ErrorAction Stop |
                Where-Object { $_.Name -match "^pid_$($TargetPid)_" } |
                ForEach-Object {
                    [ordered]@{instance=$_.Name;dedicated_usage=(Counter-Value $_ 'DedicatedUsage');shared_usage=(Counter-Value $_ 'SharedUsage');local_usage=(Counter-Value $_ 'LocalUsage');nonlocal_usage=(Counter-Value $_ 'NonLocalUsage');total_committed=(Counter-Value $_ 'TotalCommitted');provider_timestamp_perftime=(Counter-Value $_ 'Timestamp_PerfTime');provider_frequency_perftime=(Counter-Value $_ 'Frequency_PerfTime')}
                })
            $row = [ordered]@{kind='gpu_process_memory';pid=$TargetPid;qpc_before=$started;qpc_after=[Diagnostics.Stopwatch]::GetTimestamp();status=if($instances.Count){'observed'}else{'missing_instance'};instances=$instances;scope='OS PID/adapter aggregate; allocation identity and cross-process dedup unavailable'}
        } catch {
            $row = [ordered]@{kind='gpu_process_memory';pid=$TargetPid;qpc_before=$started;qpc_after=[Diagnostics.Stopwatch]::GetTimestamp();status='unavailable';error=$_.Exception.Message;instances=@()}
        }
        $writer.WriteLine(($row | ConvertTo-Json -Depth 8 -Compress)); $writer.Flush()
        $elapsedMs = ([Diagnostics.Stopwatch]::GetTimestamp()-$started)*1000.0/[Diagnostics.Stopwatch]::Frequency
        Start-Sleep -Milliseconds ([Math]::Max(1,$IntervalMs-[int]$elapsedMs))
    }
} finally { $writer.Dispose() }
