#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string]$Pack,
    [string]$Runner = (Join-Path $PSScriptRoot 'launch.tscn'),
    [string[]]$GameArguments = @(),
    [Parameter(Mandatory)][string]$Scenario,
    [Parameter(Mandatory)][string]$Output,
    [string]$PresentMon = 'C:/code/loyayz/oddly-good-hospital/.cache/performance-preflight/PresentMon-2.3.1-x64.exe',
    [ValidateRange(20,1000)][int]$PollMs = 100,
    [ValidateRange(10,18000)][int]$TimeoutSeconds = 900,
    [ValidateRange(1,60)][int]$TailTimeoutSeconds = 15,
    [ValidateRange(10,1800)][int]$ExitTimeoutSeconds = 300,
    [ValidateRange(0,9223372036854775807)][long]$AbortWorkingSetBytes = 0,
    [switch]$NoGpuCounters,
    [switch]$AllocationTrace
)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows x64 is required.' }
$outputRoot = [IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $outputRoot) { throw 'Use a new output directory; captures are immutable.' }
$exePath = (Resolve-Path -LiteralPath $Exe).Path
$presentPath = (Resolve-Path -LiteralPath $PresentMon).Path
$scenarioPath = (Resolve-Path -LiteralPath $Scenario).Path
$packPath = (Resolve-Path -LiteralPath $Pack).Path
$runnerPath = (Resolve-Path -LiteralPath $Runner).Path
$sourceExePath=$exePath;$sourcePackPath=$packPath;$sourceProductRoot=Split-Path -Parent $sourceExePath
if($outputRoot.StartsWith($sourceProductRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Capture output cannot be inside its source product directory.'}
if((Split-Path -Parent $packPath) -ne $sourceProductRoot -or [IO.Path]::GetFileNameWithoutExtension($exePath) -ne [IO.Path]::GetFileNameWithoutExtension($packPath)){throw 'The product must have its original same-name PCK beside the executable.'}
$scenarioData = Get-Content -LiteralPath $scenarioPath -Raw | ConvertFrom-Json -AsHashtable
if([long]$scenarioData.minimum_frame_samples -lt 1 -or [long]$scenarioData.minimum_step_samples -lt 1){throw 'Scenario sample minima are required; the runner must verify them against content.'}
if(-not $scenarioData.name){$scenarioData.name=$scenarioData.run_id}
$scenarioData.run_id=[Guid]::NewGuid().ToString('N')
if([long]$scenarioData.minimum_capture_real_seconds -ge $TimeoutSeconds){throw 'Overall watchdog must exceed required capture duration plus startup/exit time.'}
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$scenarioData.output_dir=$outputRoot
$scenarioData.input_path=(Resolve-Path -LiteralPath $scenarioData.input_path).Path
$scenarioCopy=Join-Path $outputRoot 'scenario.json'
[IO.File]::WriteAllText($scenarioCopy,($scenarioData | ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
$GameArguments=@($GameArguments | ForEach-Object {$_.Replace('{scenario}',$scenarioCopy)})
if(-not $GameArguments.Count){$GameArguments=@('--',('--config='+$scenarioCopy))}
if(@($GameArguments|Where-Object {$_ -in @('--headless','--fixed-fps','--path','--main-pack','--script')}).Count){throw 'Use the original Release unit with its startup scene override; editor/CLI-script substitutes are forbidden.'}
$runtimeRoot=Join-Path $outputRoot 'product';New-Item -ItemType Directory -Path $runtimeRoot|Out-Null
$copyManifest=@(foreach($file in Get-ChildItem -LiteralPath $sourceProductRoot -File -Recurse){
    $relative=[IO.Path]::GetRelativePath($sourceProductRoot,$file.FullName)
    if($relative -ieq 'override.cfg'){continue}
    $destination=Join-Path $runtimeRoot $relative
    $beforeHash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)|Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination
    $copiedHash=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    $afterHash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if($beforeHash -ne $copiedHash -or $beforeHash -ne $afterHash){throw "Product identity changed while copying $relative"}
    @{relative_path=$relative;source=$file.FullName;copy=$destination;bytes=$file.Length;sha256=$copiedHash}
})
[IO.File]::WriteAllText((Join-Path $outputRoot 'product-copy.json'),($copyManifest|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$exePath=Join-Path $runtimeRoot (Split-Path -Leaf $sourceExePath)
$packPath=Join-Path $runtimeRoot (Split-Path -Leaf $sourcePackPath)
$sceneLiteral=ConvertTo-Json -InputObject ($runnerPath.Replace('\','/')) -Compress
$profileLiteral=ConvertTo-Json -InputObject ('OddlyGoodHospital Formal '+$scenarioData.run_id) -Compress
$override="[application]`nrun/main_scene=$sceneLiteral`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=$profileLiteral`n"
$overrideNext=Join-Path $runtimeRoot 'override.cfg.next'
[IO.File]::WriteAllText($overrideNext,$override,[Text.UTF8Encoding]::new($false))
[IO.File]::Move($overrideNext,(Join-Path $runtimeRoot 'override.cfg'))
$launchHashes=@{}
foreach($path in @($sourceExePath,$sourcePackPath,$exePath,$packPath,(Join-Path $runtimeRoot 'override.cfg'),$presentPath,$scenarioCopy,$scenarioData.input_path)+(Get-ChildItem -LiteralPath $PSScriptRoot -File|Where-Object {$_.Extension -in @('.gd','.tscn','.ps1','.py','.cs')}|ForEach-Object FullName)){
    $launchHashes[$path]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
$frequency = [Diagnostics.Stopwatch]::Frequency
$sessionName = 'HospitalFormal-' + [Guid]::NewGuid().ToString('N')
$owned = @(); $game = $null; $present = $null; $gpu = $null; $allocation = $null; $traceStopped = $false
$memory = [IO.StreamWriter]::new((Join-Path $outputRoot 'process.ndjson'),$false,[Text.UTF8Encoding]::new($false))
$anchors = [IO.StreamWriter]::new((Join-Path $outputRoot 'control-anchors.ndjson'),$false,[Text.UTF8Encoding]::new($false))
$generation = 0; $phase = 'launch'; $windowStart = $null; $windowEnd = $null
$selectedChain = $null; $frameStarts = [Collections.Generic.List[double]]::new()
$seenDisplays = [Collections.Generic.HashSet[string]]::new(); $csvHeader = $null
$readyPath = Join-Path $outputRoot 'ready.json'; $controlPath = Join-Path $outputRoot 'control.json'
$startAck = $null; $stopAck = $null; $exceptionText = $null; $timedOut = $false
$traceFinal = $null; $forced = [Collections.Generic.List[string]]::new()
$commandTimes=@{}; $lastDisplayEnd=0.0; $tailAckQpc=$null; $ackBounds=[Collections.Generic.List[object]]::new()
$inputRequests=[Collections.Generic.HashSet[string]]::new()
$controller=[Diagnostics.Process]::GetCurrentProcess();$controllerCpuBegin=$controller.TotalProcessorTime.TotalSeconds;$controllerPeak=0L
function Qpc { [Diagnostics.Stopwatch]::GetTimestamp() }
function Save-Json($Path,$Value) { [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false)) }
function Start-Owned([string]$Path,[string[]]$Arguments,[string]$Stem,[bool]$Visible) {
    $info = [Diagnostics.ProcessStartInfo]::new($Path)
    $info.UseShellExecute=$false; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $info.CreateNoWindow = -not $Visible
    $info.WindowStyle = if($Visible){[Diagnostics.ProcessWindowStyle]::Normal}else{[Diagnostics.ProcessWindowStyle]::Hidden}
    $info.WorkingDirectory = Split-Path -Parent $exePath
    foreach($argument in $Arguments){$info.ArgumentList.Add($argument)}
    $info.Environment['OGH_CAPTURE_DIR']=$outputRoot
    $info.Environment['OGH_SCENARIO_PATH']=(Join-Path $outputRoot 'scenario.json')
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$info
    if(-not $process.Start()){throw "Cannot launch $Path"}
    $record=@{process=$process;path=$Path;arguments=@($Arguments);start_utc_ticks=$process.StartTime.ToUniversalTime().Ticks;stem=$Stem;out_task=$process.StandardOutput.ReadLineAsync();err_task=$process.StandardError.ReadLineAsync();out_done=$false;err_done=$false;out_writer=[IO.StreamWriter]::new((Join-Path $outputRoot $(if($Stem -eq 'presentmon'){'presentmon.csv'}else{$Stem+'.stdout.log'})),$false,[Text.UTF8Encoding]::new($false));err_writer=[IO.StreamWriter]::new((Join-Path $outputRoot ($Stem+'.stderr.log')),$false,[Text.UTF8Encoding]::new($false))}
    $record.observed_peak_working_set_bytes=0L;$record.last_cpu_seconds=0.0
    return $record
}
function Pump($Record) {
    try {
        if(-not $Record.process.HasExited){
            $Record.process.Refresh()
            $Record.observed_peak_working_set_bytes=[Math]::Max([long]$Record.observed_peak_working_set_bytes,[long]$Record.process.PeakWorkingSet64)
            $Record.last_cpu_seconds=$Record.process.TotalProcessorTime.TotalSeconds
        }
    } catch {$Record.sampling_error=$_.Exception.Message}
    foreach($stream in @('out','err')){
        for($batch=0;$batch -lt 256 -and -not $Record[($stream+'_done')] -and $Record[($stream+'_task')].IsCompleted;$batch++){
            $line=$Record[($stream+'_task')].GetAwaiter().GetResult()
            if($null -eq $line){$Record[($stream+'_done')]=$true;break}
            $isCsv = $Record.stem -eq 'presentmon' -and $stream -eq 'out'
            if(-not $isCsv -or $line.StartsWith('Application,') -or ($script:csvHeader -and $line.Split(',').Length -eq $script:csvHeader.Length)){
                $Record[($stream+'_writer')].WriteLine($line)
            } else {$Record.err_writer.WriteLine('NONCSV_STDOUT: '+$line)}
            if($Record.stem -eq 'presentmon' -and $stream -eq 'out'){
                if($line.StartsWith('Application,')){$script:csvHeader=$line.Split(',')}
                elseif($null -ne $script:csvHeader){
                    $cells=$line.Split(',')
                    if($cells.Length -eq $script:csvHeader.Length){
                        $row=@{};for($c=0;$c -lt $cells.Length;$c++){$row[$script:csvHeader[$c].ToLowerInvariant()]=$cells[$c]}
                        if($row.processid -eq [string]$game.process.Id -and $row.dropped -eq '0'){
                            $duration=0.0;$until=0.0;$presentQpc=0.0
                            if([double]::TryParse($row.msbetweendisplaychange,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$duration) -and [double]::TryParse($row.msuntildisplayed,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$until) -and [double]::TryParse($row.qpctime,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$presentQpc) -and $duration -gt 0){
                                $end=$presentQpc+$until*$frequency/1000.0;$begin=$end-$duration*$frequency/1000.0
                                if($null -eq $script:selectedChain){$script:selectedChain=$row.swapchainaddress}
                                $key=$row.swapchainaddress+':'+$end.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
                                if($row.swapchainaddress -eq $script:selectedChain -and $script:seenDisplays.Add($key)){$script:frameStarts.Add($begin);$script:lastDisplayEnd=$end}
                            }
                        }
                    }
                }
            }
            $Record[($stream+'_task')]=$(if($stream -eq 'out'){$Record.process.StandardOutput.ReadLineAsync()}else{$Record.process.StandardError.ReadLineAsync()})
        }
        $Record[($stream+'_writer')].Flush()
    }
}
function Count-WindowFrames($FrameStarts, [long]$WindowStart, [hashtable]$State) {
    # The CSV collector appends observations; their timestamps need not arrive
    # in order. Each original start is counted once against the fixed boundary.
    if (-not $State.ContainsKey('window_start') -or $State.window_start -ne $WindowStart) {
        $State.window_start=$WindowStart; $State.cursor=0; $State.count=0L
    }
    for (; $State.cursor -lt $FrameStarts.Count; $State.cursor++) {
        if ($FrameStarts[$State.cursor] -ge $WindowStart) { $State.count++ }
    }
    return [long]$State.count
}
function Send-Control([string]$Next) {
    $script:generation++
    $before=Qpc
    $value=@{phase=$Next;generation=$script:generation;qpc_before_write=$before;qpc_frequency=$frequency}
    $temporary=$controlPath+'.next'
    Save-Json $temporary $value
    [IO.File]::Move($temporary,$controlPath,$true)
    $after=Qpc
    $anchors.WriteLine((@{kind='command';phase=$Next;generation=$script:generation;qpc_before=$before;qpc_after=$after} | ConvertTo-Json -Compress));$anchors.Flush()
    $script:commandTimes[$script:generation]=$before
    return $before
}
function Accept-Ack($Ready,[string]$State) {
    $observed=Qpc
    if($Ready.pid -ne $game.process.Id -or [long]$Ready.qpc_frequency -ne $frequency -or $null -eq $Ready.qpc_ticks){throw 'ACK PID/native QPC identity differs from owned capture.'}
    $lower=[long]$commandTimes[$generation];$native=[long]$Ready.qpc_ticks
    if($native -lt $lower -or $native -gt $observed){throw 'Native ACK QPC is outside its external command/read bracket.'}
    $record=@{kind='ack';phase=$State;generation=$generation;engine_us=$Ready.engine_us;qpc_ticks=$native;qpc_before=$lower;qpc_after=$observed;uncertainty_ticks=$observed-$lower;qpc_frequency=$frequency}
    $ackBounds.Add($record);$anchors.WriteLine(($record|ConvertTo-Json -Compress));$anchors.Flush()
    return $native
}
function Pump-Input {
    $path=Join-Path $outputRoot 'input-request.json'
    if(-not (Test-Path -LiteralPath $path)){return}
    try{$request=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable}catch{return}
    if($request.status -ne 'armed' -or -not $request.id -or -not $inputRequests.Add([string]$request.id)){return}
    $before=Qpc;$ok=$true;$failure=$null;$actualFields=@()
    try {
        if($request.pid -ne $game.process.Id){throw 'Input request PID is not the owned game.'}
        if(-not $request.fields -or $request.fields.Count -gt 8){throw 'Expected 1..8 bounded input fields.'}
        foreach($field in $request.fields){
            if($field.client_point.Count -ne 2){throw 'Physical client point must have two coordinates.'}
            $screenPoint=[HospitalInput]::ClickClient($game.process.Id,[int]$field.client_point[0],[int]$field.client_point[1])
            $actualFields+=@{name=$field.name;client_point=$field.client_point;screen_point=$screenPoint}
            [HospitalInput]::ReplaceText($game.process.Id,[string]$field.text)
        }
    } catch {$ok=$false;$failure=$_.Exception.Message}
    $ack=@{id=$request.id;ok=$ok;error=$failure;pid=$game.process.Id;send_begin_qpc=$before;send_end_qpc=(Qpc);qpc_frequency=$frequency;actual_fields=$actualFields;source='Windows ClientToScreen and SendInput; foreground owned PID and physical client bounds checked'}
    $next=Join-Path $outputRoot 'input-ack.json.next';Save-Json $next $ack
    [IO.File]::Move($next,(Join-Path $outputRoot 'input-ack.json'),$true)
    $anchors.WriteLine((@{kind='input_ack';details=$ack}|ConvertTo-Json -Depth 8 -Compress));$anchors.Flush()
}
try {
    if(-not ('HospitalTraceStatus' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'trace-status.cs')}
    if(-not ('HospitalInput' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'input-driver.cs')}
    if($AllocationTrace){
        $allocationArgs=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'capture-dxgkrnl.ps1'),'-TargetIdentityPath',(Join-Path $outputRoot 'game-identity.json'),'-Output',(Join-Path $outputRoot 'allocation'),'-ReadyPath',(Join-Path $outputRoot 'allocation.ready.json'),'-StopPath',(Join-Path $outputRoot 'allocation.stop'),'-TimeoutSeconds',[string]$TimeoutSeconds)
        $allocation=Start-Owned (Get-Process -Id $PID).Path $allocationArgs 'allocation-trace' $false;$owned+=,$allocation
        $readyDeadline=[DateTime]::UtcNow.AddSeconds(30)
        while(-not (Test-Path -LiteralPath (Join-Path $outputRoot 'allocation.ready.json'))){
            Pump $allocation
            if($allocation.process.HasExited -or [DateTime]::UtcNow -gt $readyDeadline){throw 'Allocation trace failed before game startup; inspect allocation trace logs.'}
            Start-Sleep -Milliseconds 20
        }
    }
    $game=Start-Owned $exePath $GameArguments 'game' $true; $owned+=,$game
    Save-Json (Join-Path $outputRoot 'game-identity.json') @{pid=$game.process.Id;start_utc_ticks=$game.start_utc_ticks;qpc_observed=(Qpc);qpc_frequency=$frequency}
    $pmArgs=@('--process_id',[string]$game.process.Id,'--output_stdout','--v1_metrics','--qpc_time','--no_console_stats','--session_name',$sessionName)
    $present=Start-Owned $presentPath $pmArgs 'presentmon' $false; $owned+=,$present
    if(-not $NoGpuCounters){
        $gpuArgs=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'sample-gpu.ps1'),'-TargetPid',[string]$game.process.Id,'-TargetStartUtcTicks',[string]$game.start_utc_ticks,'-Output',(Join-Path $outputRoot 'gpu-process-memory.ndjson'),'-StopPath',(Join-Path $outputRoot 'gpu.stop'))
        $gpu=Start-Owned (Get-Process -Id $PID).Path $gpuArgs 'gpu-sampler' $false;$owned+=,$gpu
    }
    $launchQpc=Qpc;$script:lastDisplayEnd=0.0;$stopRequestQpc=$null
    $windowFrameCounter=@{}
    while(-not $game.process.HasExited){
        $pollStarted=Qpc
        foreach($item in $owned){Pump $item}
        Pump-Input
        if($present.process.HasExited){throw 'PresentMon exited before the owned game completed.'}
        $game.process.Refresh()
        if($game.process.HasExited){break}
        $controller.Refresh();$controllerPeak=[Math]::Max($controllerPeak,$controller.WorkingSet64)
        $nativeMemory=[HospitalProcessMemory]::Read($game.process.Handle)
        $sample=@{kind='process';pid=$game.process.Id;qpc_ticks=(Qpc);working_set_bytes=$nativeMemory.working_set_bytes;private_commit_bytes=$nativeMemory.private_commit_bytes;lifetime_peak_working_set_bytes=$nativeMemory.lifetime_peak_working_set_bytes;lifetime_peak_private_commit_bytes=$nativeMemory.lifetime_peak_private_commit_bytes;cpu_seconds=$game.process.TotalProcessorTime.TotalSeconds}
        $sample.poll_work_us=((Qpc)-$pollStarted)*1000000.0/$frequency
        $memory.WriteLine(($sample | ConvertTo-Json -Compress));$memory.Flush()
        if($AbortWorkingSetBytes -gt 0 -and ([long]$sample.working_set_bytes -ge $AbortWorkingSetBytes -or [long]$sample.lifetime_peak_working_set_bytes -ge $AbortWorkingSetBytes)){
            Save-Json (Join-Path $outputRoot 'resource-abort.json') @{reason='working_set_stop_limit';limit_bytes=$AbortWorkingSetBytes;sample=$sample;target_start_utc_ticks=$game.start_utc_ticks;scope='bounded failure stop; not a completed acceptance window'}
            throw 'Owned game working set reached the configured failure stop limit; no complete result.'
        }
        $ready=$null
        if(Test-Path -LiteralPath $readyPath){try{$ready=Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json -AsHashtable}catch{}}
        if($phase -eq 'launch' -and $null -ne $csvHeader){[void](Send-Control 'armed');$phase='armed'}
        if($phase -eq 'armed' -and $ready -and $ready.phase -eq 'prepared' -and $ready.generation -eq $generation){[void](Send-Control 'start');$phase='starting'}
        if($phase -eq 'starting' -and $ready -and $ready.phase -eq 'started' -and $ready.generation -eq $generation){
            $windowStart=Accept-Ack $ready 'started';$startAck=$ready;$phase='running'
        }
        $boundaryMargin=[long]($scenarioData.boundary_step_margin ?? ([Math]::Ceiling([double]$scenarioData.speed*10)))
        if($phase -eq 'running' -and $ready -and $ready.generation -eq $generation -and $ready.operations_complete -eq $true -and [long]$ready.completed_steps -ge [long]$scenarioData.minimum_step_samples+$boundaryMargin){
            $count=Count-WindowFrames $frameStarts $windowStart $windowFrameCounter
            $minimumSeconds=[double]($scenarioData.minimum_capture_real_seconds ?? 0)
            if($count -ge [long]$scenarioData.minimum_frame_samples -and ((Qpc)-$windowStart)/$frequency -ge $minimumSeconds){$stopRequestQpc=Send-Control 'stop';$phase='stopping'}
        }
        if($phase -eq 'stopping' -and $ready -and $ready.phase -eq 'stopped' -and $ready.generation -eq $generation){
            # Request-to-ACK waiting belongs to this original window.
            $windowEnd=Accept-Ack $ready 'stopped';$stopAck=$ready;$phase='tail'
        }
        if($phase -eq 'tail' -and $lastDisplayEnd -gt $windowEnd){$tailAckQpc=Send-Control 'tail_ack';$phase='await_exit'}
        if($phase -eq 'tail' -and ((Qpc)-$windowEnd)/$frequency -gt $TailTimeoutSeconds){throw 'Missing display tail; no complete result.'}
        if($phase -eq 'await_exit' -and ((Qpc)-$tailAckQpc)/$frequency -gt $ExitTimeoutSeconds){throw 'Normal scenario/save/dispose exit watchdog expired.'}
        if(((Qpc)-$launchQpc)/$frequency -gt $TimeoutSeconds){$timedOut=$true;throw 'Scenario watchdog expired; no complete result.'}
        $spent=((Qpc)-$pollStarted)*1000.0/$frequency
        Start-Sleep -Milliseconds ([Math]::Max(1,$PollMs-[int]$spent))
    }
    $game.process.WaitForExit();foreach($item in $owned){Pump $item}
    if($phase -ne 'await_exit'){throw 'Game exited without complete operations and acknowledged tail.'}
} catch { $exceptionText=$_.Exception.Message }
finally {
    [IO.File]::WriteAllText((Join-Path $outputRoot 'gpu.stop'),'stop')
    [IO.File]::WriteAllText((Join-Path $outputRoot 'allocation.stop'),'stop')
    if($present -and -not $present.process.HasExited){
        try{$traceFinal=[HospitalTraceStatus]::Read($sessionName,$true);$traceStopped=($traceFinal.code -eq 0)}catch{$traceFinal=@{code=$null;error=$_.Exception.Message}}
        if(-not $present.process.WaitForExit(5000)){$forced.Add('presentmon');$present.process.Kill();$present.process.WaitForExit()}
    }
    foreach($item in $owned){
        if(-not $item.process.HasExited){
            if($item -eq $game -and $exceptionText){[void]$item.process.CloseMainWindow()}
            if(-not $item.process.WaitForExit($(if($item -eq $allocation -or $item -eq $gpu){10000}else{3000}))){$forced.Add($item.stem);$item.process.Kill();$item.process.WaitForExit()}
        }
        $drainDeadline=[DateTime]::UtcNow.AddSeconds(5)
        while((-not $item.out_done -or -not $item.err_done) -and [DateTime]::UtcNow -lt $drainDeadline){Pump $item;Start-Sleep -Milliseconds 5}
        if(-not $item.out_done -or -not $item.err_done){$forced.Add($item.stem+'_stream_drain_timeout')}
        $item.out_writer.Dispose();$item.err_writer.Dispose()
    }
    $memory.Dispose();$anchors.Dispose()
    $identities=@(foreach($item in $owned){
        try{$item.last_cpu_seconds=$item.process.TotalProcessorTime.TotalSeconds}catch{}
        @{stem=$item.stem;pid=$item.process.Id;exe=$item.path;arguments=$item.arguments;start_utc_ticks=$item.start_utc_ticks;exit_code=$item.process.ExitCode;cpu_seconds=$item.last_cpu_seconds;observed_lifetime_peak_working_set_bytes=$item.observed_peak_working_set_bytes;sampling_error=$item.sampling_error}
    })
    $artifacts=@(foreach($path in $launchHashes.Keys){
        $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if($hash -ne $launchHashes[$path]){$exceptionText='Capture artifact changed during run: '+$path}
        @{path=$path;bytes=(Get-Item -LiteralPath $path).Length;sha256=$hash;launch_sha256=$launchHashes[$path];unchanged=$hash -eq $launchHashes[$path]}
    })
    $productFiles=@(Get-ChildItem -LiteralPath (Split-Path -Parent $exePath) -File -Filter '*.dll'|ForEach-Object {@{path=$_.FullName;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
    $metadata=@{
        schema_version=2;kind='formal_capture';scenario=$scenarioData.name
        qpc_frequency=$frequency;pid=if($game){$game.process.Id}else{$null}
        poll_requested_ms=$PollMs;abort_working_set_bytes=$AbortWorkingSetBytes;session_name=$sessionName;presentmon_mode='v1_qpc_raw'
        presentmon_version=[Diagnostics.FileVersionInfo]::GetVersionInfo($presentPath).ProductVersion
        selected_swapchain=$selectedChain;window_start_qpc=$windowStart;window_end_qpc=$windowEnd
        stop_request_qpc=$stopRequestQpc;start_ack=$startAck;stop_ack=$stopAck
        ack_bounds=$ackBounds.ToArray();trace_stop_succeeded=$traceStopped;trace_final=$traceFinal
        presentmon_internal_lost_present_count=$null;processes=$identities
        forced_processes=$forced.ToArray();watchdog_expired=$timedOut;error=$exceptionText
        artifacts=$artifacts;product_dlls=$productFiles;source_product=$sourceProductRoot;runtime_product=$runtimeRoot
        exe_sha256=(Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
        presentmon_sha256=(Get-FileHash -LiteralPath $presentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    Save-Json (Join-Path $outputRoot 'capture.json') $metadata
    $controller.Refresh()
    Save-Json (Join-Path $outputRoot 'collector-overhead.json') @{pid=$PID;cpu_seconds=$controller.TotalProcessorTime.TotalSeconds-$controllerCpuBegin;observed_peak_working_set_bytes=$controllerPeak;scope='collector lifetime including startup and teardown; not deducted from game frame/step samples';qpc_frequency=$frequency}
}
if($exceptionText -or $forced.Count){[Console]::Error.WriteLine(($exceptionText ?? 'Owned helper required forced termination.'));exit 2}
if(@($owned | Where-Object {$_.process.ExitCode -ne 0}).Count){exit 1}
Write-Output "CAPTURE_ROOT=$outputRoot"
exit 0
