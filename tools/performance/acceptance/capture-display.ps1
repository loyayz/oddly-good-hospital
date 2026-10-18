#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string]$Output,
    [Parameter(Mandatory)][string]$RenderDoc,
    [string]$Conditions = '',
    [ValidateRange(30,1800)][int]$TimeoutSeconds = 300
)
$ErrorActionPreference='Stop'
$exePath=(Resolve-Path -LiteralPath $Exe).Path
$rdPath=(Resolve-Path -LiteralPath $RenderDoc).Path
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
    $copy=Join-Path $runtime $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $copy) | Out-Null
    $before=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    Copy-Item -LiteralPath $file.FullName -Destination $copy
    $after=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $copied=(Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant()
    if($before -ne $after -or $before -ne $copied){throw "Source identity changed: $relative"}
    @{path=$relative;source=$file.FullName;copy=$copy;sha256=$copied}
})
$files | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $destination 'product-copy.json') -Encoding utf8NoBOM
$scenario=@{output_dir=$destination;conditions=@()}
if($Conditions){$scenario.conditions=@(Get-Content -LiteralPath $Conditions -Raw | ConvertFrom-Json -AsHashtable)}
$scenarioPath=Join-Path $destination 'display-scenario.json'
$scenario | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $scenarioPath -Encoding utf8NoBOM
$override='[application]'+"`nrun/main_scene="+(ConvertTo-Json ((Join-Path $PSScriptRoot 'display_probe.tscn').Replace('\','/')) -Compress)+"`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name="+(ConvertTo-Json ('OddlyGoodHospital Display '+[Guid]::NewGuid().ToString('N')) -Compress)+"`n"
[IO.File]::WriteAllText((Join-Path $runtime 'override.cfg'),$override,[Text.UTF8Encoding]::new($false))
$diagnosticLog=(Join-Path $destination 'display-engine.log').Replace('\','/')
[IO.File]::AppendAllText((Join-Path $runtime 'override.cfg'),"`n[debug]`nfile_logging/enable_file_logging=true`nfile_logging/enable_file_logging.pc=true`nfile_logging/log_path="+(ConvertTo-Json $diagnosticLog -Compress)+"`n",[Text.UTF8Encoding]::new($false))
$configPath=Join-Path $destination 'renderdoc-config.json'
@{exe=(Join-Path $runtime (Split-Path -Leaf $exePath));pack=(Join-Path $runtime (Split-Path -Leaf $packPath));scenario=$scenarioPath;output_dir=$destination;condition_count=$(if($scenario.conditions.Count){$scenario.conditions.Count}else{12});timeout_seconds=$TimeoutSeconds} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
$profilePath=Join-Path $env:APPDATA 'qrenderdoc/UI.config'
$existed=Test-Path -LiteralPath $profilePath -PathType Leaf
$originalBytes=if($existed){[IO.File]::ReadAllBytes($profilePath)}else{$null}
$original=if($existed){[IO.File]::ReadAllText($profilePath)}else{$null}
$config=if($existed){$original | ConvertFrom-Json -AsHashtable}else{@{}}
# Suppress this diagnostic tool's first-use analytics dialog during the CLI run.
# Restore the exact original preferences in finally; no game preference changes.
$config.Analytics_TotalOptOut=$true
$config.CheckUpdate_AllowChecks=$false
$process=$null
$ownedGame=$null
$ownedGameStart=$null
try {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $profilePath) | Out-Null
    $config | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $profilePath -Encoding utf8NoBOM
    $launch=[Diagnostics.ProcessStartInfo]::new($rdPath)
    $launch.ArgumentList.Add('--python')
    $launch.ArgumentList.Add((Join-Path $PSScriptRoot 'renderdoc_display.py'))
    $launch.Environment['HOSPITAL_RENDERDOC_CONFIG']=$configPath
    $launch.UseShellExecute=$false
    $launch.CreateNoWindow=$true
    $launch.WindowStyle='Hidden'
    $process=[Diagnostics.Process]::Start($launch)
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds+180)
    while(-not $process.WaitForExit(200)){
        $identityPath=Join-Path $destination 'target-identity.json'
        if($null -eq $ownedGame -and (Test-Path -LiteralPath $identityPath)){
            try {
                $identity=Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
                $candidate=[Diagnostics.Process]::GetProcessById([int]$identity.pid)
                [void]$candidate.Handle
                if($candidate.MainModule.FileName -ine (Join-Path $runtime (Split-Path -Leaf $exePath))){throw 'RenderDoc target differs from owned product copy.'}
                $ownedGame=$candidate
                $ownedGameStart=$candidate.StartTime.ToUniversalTime().Ticks
            } catch [System.ArgumentException] { }
        }
        if([DateTimeOffset]::UtcNow -gt $deadline){throw 'RenderDoc capture/replay did not complete; raw evidence preserved.'}
    }
    if($process.ExitCode -ne 0){throw "RenderDoc failed: $(Join-Path $destination 'renderdoc-error.txt')"}
    if($null -eq $ownedGame -or -not $ownedGame.WaitForExit(5000) -or $ownedGame.ExitCode -ne 0){throw 'Owned Release display process did not exit normally.'}
    $evidence=Join-Path $destination 'render-target-evidence.json'
    if(-not (Test-Path -LiteralPath $evidence -PathType Leaf)){throw 'Renderer evidence absent.'}
    @{renderdoc=$rdPath;renderdoc_sha256=(Get-FileHash -LiteralPath $rdPath -Algorithm SHA256).Hash.ToLowerInvariant();exit_code=$process.ExitCode;game_pid=$ownedGame.Id;game_start_utc_ticks=$ownedGameStart;game_exit_code=$ownedGame.ExitCode;scope='display-only injected diagnostic; not formal timing or GPU memory budget'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'tool-identity.json') -Encoding utf8NoBOM
    Write-Output "DISPLAY_EVIDENCE=$evidence"
    if((Get-Content -LiteralPath $evidence -Raw | ConvertFrom-Json).status -ne 'verified'){throw 'Display capture completed with unverified conditions; inspect preserved backend evidence.'}
} finally {
    try {
        [IO.File]::WriteAllText((Join-Path $destination 'display.abort'),"collector finished`n")
        if($ownedGame){
            $ownedGame.Refresh()
            if(-not $ownedGame.HasExited -and -not $ownedGame.WaitForExit(5000)){
                if($ownedGame.StartTime.ToUniversalTime().Ticks -ne $ownedGameStart -or $ownedGame.MainModule.FileName -ine (Join-Path $runtime (Split-Path -Leaf $exePath))){throw 'Owned display process identity changed; no foreign process stopped.'}
                $ownedGame.Kill();$ownedGame.WaitForExit()
                @{pid=$ownedGame.Id;start_utc_ticks=$ownedGameStart;forced=$true;reason='display abort did not finish in 5 seconds'} | ConvertTo-Json | Set-Content (Join-Path $destination 'forced-display-stop.json') -Encoding utf8NoBOM
            }
        }
    } finally {
        if($process){$process.Refresh();if(-not $process.HasExited){$process.Kill();$process.WaitForExit()}}
        if($existed){[IO.File]::WriteAllBytes($profilePath,$originalBytes)}
        elseif(Test-Path -LiteralPath $profilePath){Remove-Item -LiteralPath $profilePath}
    }
}
