#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string]$Output,
    [Parameter(Mandatory)][string]$ApiTrace,
    [string]$Conditions = '',
    [ValidateRange(10,300)][int]$TimeoutSeconds = 45
)
$ErrorActionPreference='Stop'
$exePath=(Resolve-Path -LiteralPath $Exe).Path
$apiPath=(Resolve-Path -LiteralPath $ApiTrace).Path
$wrapper=(Resolve-Path -LiteralPath (Join-Path (Split-Path -Parent (Split-Path -Parent $apiPath)) 'lib/wrappers/opengl32.dll')).Path
$featureMask=Join-Path $env:LOCALAPPDATA 'apitrace/gltrace.conf'
if(Test-Path -LiteralPath $featureMask){throw 'apitrace feature-mask configuration exists; original renderer capabilities cannot be assumed.'}
$destination=[IO.Path]::GetFullPath($Output)
$sourceRoot=Split-Path -Parent $exePath
$packPath=[IO.Path]::ChangeExtension($exePath,'.pck')
if(-not (Test-Path -LiteralPath $packPath -PathType Leaf)){throw 'Original same-name Release PCK is required.'}
if(Test-Path -LiteralPath $destination){throw 'Display capture output must be new.'}
if($destination.StartsWith($sourceRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Evidence cannot be inside its source product.'}
New-Item -ItemType Directory -Path $destination | Out-Null
$runtime=Join-Path $destination 'product'
New-Item -ItemType Directory -Path $runtime | Out-Null
$files=@(foreach($file in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse){
    $relative=[IO.Path]::GetRelativePath($sourceRoot,$file.FullName)
    if($relative -ieq 'override.cfg'){continue}
    if($relative -ieq 'opengl32.dll'){throw 'Original product already contains an OpenGL wrapper; no override performed.'}
    $copy=Join-Path $runtime $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $copy) | Out-Null
    $before=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    Copy-Item -LiteralPath $file.FullName -Destination $copy
    $after=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if($before -ne $after -or $before -ne (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant()){throw "Source identity changed: $relative"}
    @{path=$relative;source=$file.FullName;copy=$copy;sha256=$before}
})
$files | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $destination 'product-copy.json') -Encoding utf8NoBOM
Copy-Item -LiteralPath $wrapper -Destination (Join-Path $runtime 'opengl32.dll')
$scenario=@{output_dir=$destination;conditions=@()}
if($Conditions){$scenario.conditions=@(Get-Content -LiteralPath $Conditions -Raw | ConvertFrom-Json -AsHashtable)}
$scenarioPath=Join-Path $destination 'display-scenario.json'
$scenario | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $scenarioPath -Encoding utf8NoBOM
$observer=Join-Path $destination 'observer'
New-Item -ItemType Directory -Path $observer | Out-Null
$observerFiles=@(foreach($name in @('display_probe.tscn','display_probe.gd','display_root.gd')){
    $original=Join-Path $PSScriptRoot $name
    $copy=Join-Path $observer $name
    $before=(Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant()
    Copy-Item -LiteralPath $original -Destination $copy
    if((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant() -ne $before -or (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant() -ne $before){throw 'Display observer changed during copy.'}
    @{path=$copy;sha256=$before}
})
$observerFiles | ConvertTo-Json | Set-Content (Join-Path $destination 'observer-sources.json') -Encoding utf8NoBOM
$override='[application]'+"`nrun/main_scene="+(ConvertTo-Json ((Join-Path $observer 'display_probe.tscn').Replace('\','/')) -Compress)+"`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name="+(ConvertTo-Json ('OddlyGoodHospital GL display '+[Guid]::NewGuid().ToString('N')) -Compress)+"`n`n[debug]`nfile_logging/enable_file_logging=true`nfile_logging/enable_file_logging.pc=true`n"
[IO.File]::WriteAllText((Join-Path $runtime 'override.cfg'),$override,[Text.UTF8Encoding]::new($false))
$trace=Join-Path $destination 'display.trace'
$launch=[Diagnostics.ProcessStartInfo]::new((Join-Path $runtime (Split-Path -Leaf $exePath)))
$launch.WorkingDirectory=$runtime
$launch.UseShellExecute=$false
$launch.CreateNoWindow=$true
$launch.WindowStyle='Hidden'
$launch.Environment['TRACE_FILE']=$trace
$launch.ArgumentList.Add('--log-file')
$launch.ArgumentList.Add((Join-Path $destination 'display-engine.log'))
$launch.ArgumentList.Add('--')
$launch.ArgumentList.Add(('--config='+$scenarioPath))
$game=$null
$forced=$false
$records=@()
try {
    $game=[Diagnostics.Process]::Start($launch)
    $startTicks=$game.StartTime.ToUniversalTime().Ticks
    @{pid=$game.Id;exe=$launch.FileName;start_utc_ticks=$startTicks} | ConvertTo-Json | Set-Content (Join-Path $destination 'target-identity.json') -Encoding utf8NoBOM
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $count=if($scenario.conditions.Count){$scenario.conditions.Count}else{12}
    for($index=0;$index -lt $count;$index++){
        $ready=Join-Path $destination ('display-{0:d2}.json' -f $index)
        while(-not (Test-Path -LiteralPath $ready)){
            if($game.WaitForExit(100)){throw "Owned display process exited before condition $index (exit $($game.ExitCode))."}
            if([DateTimeOffset]::UtcNow -ge $deadline){throw "Display condition $index watchdog expired; raw evidence preserved."}
        }
        $record=Get-Content -LiteralPath $ready -Raw | ConvertFrom-Json
        if($record.pid -ne $game.Id){throw 'Display metadata differs from owned process.'}
        $records+=,$record
        [IO.File]::WriteAllText((Join-Path $destination ('display-{0:d2}.ack' -f $index)),"traced`n")
    }
    if(-not $game.WaitForExit(5000) -or $game.ExitCode -ne 0){throw 'Owned display process did not exit normally.'}
    if(-not (Test-Path -LiteralPath $trace -PathType Leaf)){throw 'OpenGL trace absent; wrapper instrumentation did not produce backend evidence.'}
    $dump=Join-Path $destination 'gl-calls.txt'
    # Keep only state needed to reconstruct actual attachments and draws. The
    # original trace retains every call for independent audit and replay.
    & $apiPath dump --color=never --thread-ids=yes '--grep=^(wgl(SwapBuffers|SwapLayerBuffers|MakeCurrent|CreateContext|CreateContextAttribsARB|ShareLists|DeleteContext)|SwapBuffers|glXSwapBuffers|eglSwapBuffers|gl(BindFramebuffer|GenFramebuffers|DeleteFramebuffers|FramebufferTexture|FramebufferRenderbuffer|CheckFramebufferStatus|BindTexture|ActiveTexture|TexImage|TexStorage|TextureStorage|TextureImage|GetTexImage|GetTextureImage|ReadPixels|PushDebugGroup|PopDebugGroup|DebugMessageInsert|DeleteTextures|GenTextures|BindRenderbuffer|RenderbufferStorage|DeleteRenderbuffers|Viewport|DrawArrays|DrawElements|DrawBuffers|ReadBuffer|BlitFramebuffer|Clear|Finish|Flush|GetError))' $trace | Set-Content -LiteralPath $dump -Encoding utf8NoBOM
    if($LASTEXITCODE -ne 0){throw 'apitrace dump failed; raw trace preserved.'}
    @{kind='apitrace_display_boundaries';status='captured_pending_backend_analysis';condition_count=$records.Count;pid=$game.Id;game_start_utc_ticks=$startTicks;game_exit_code=$game.ExitCode;apitrace=$apiPath;apitrace_sha256=(Get-FileHash -LiteralPath $apiPath -Algorithm SHA256).Hash.ToLowerInvariant();wrapper=$wrapper;wrapper_sha256=(Get-FileHash -LiteralPath $wrapper -Algorithm SHA256).Hash.ToLowerInvariant();trace=$trace;trace_sha256=(Get-FileHash -LiteralPath $trace -Algorithm SHA256).Hash.ToLowerInvariant();dump=$dump;dump_sha256=(Get-FileHash -LiteralPath $dump -Algorithm SHA256).Hash.ToLowerInvariant();scope='instrumented display-only preset; not timing, allocation budget, OS presentation or business load'} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $destination 'apitrace-identity.json') -Encoding utf8NoBOM
    Write-Output "DISPLAY_TRACE=$trace"
} finally {
    [IO.File]::WriteAllText((Join-Path $destination 'display.abort'),"collector finished`n")
    if($game){
        $game.Refresh()
        if(-not $game.HasExited -and -not $game.WaitForExit(2000)){
            if($game.StartTime.ToUniversalTime().Ticks -ne $startTicks){throw 'Owned display process identity changed; no foreign process stopped.'}
            $game.Kill()
            $forced=$true
            if(-not $game.WaitForExit(5000)){throw 'Owned display process has not finished after forced stop.'}
        }
        @{pid=$game.Id;start_utc_ticks=$startTicks;exited=$game.HasExited;exit_code=$(if($game.HasExited){$game.ExitCode}else{$null});forced=$forced} | ConvertTo-Json | Set-Content (Join-Path $destination 'process-cleanup.json') -Encoding utf8NoBOM
    }
}
