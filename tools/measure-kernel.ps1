#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet(160,320,640)][int[]]$Actors = @(160,320,640),
    [ValidateSet(1,3)][int[]]$Speeds = @(1,3),
    [double]$WarmupSeconds = 60,
    [double]$SampleSeconds = 600,
    [string]$RunName = ('formal-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [switch]$Profile,
    [switch]$Display,
    [switch]$Dense,
    [switch]$Visible,
    [ValidatePattern('^[1-9][0-9]+x[1-9][0-9]+$')][string]$Window = '2560x1440',
    [ValidateSet(1.0,0.75,0.6667)][double]$SceneScale = 0.75,
    [ValidateSet(1,2)][int]$UiScale = 1
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$release = Join-Path $repo '.build/stage03/benchmark'
$exe = Join-Path $release 'kernel-benchmark.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Build the Release benchmark with prepare-kernel-benchmark.ps1 first.' }
if ($RunName -notmatch '^[a-zA-Z0-9-]+$') { throw 'RunName must contain only letters, digits and hyphens.' }
if ($SampleSeconds -le 0 -or $WarmupSeconds -lt 0) { throw 'Invalid capture duration.' }
$output = Join-Path $repo ('.cache/validation/stage03/' + $RunName)
if (Test-Path -LiteralPath $output) { throw "Capture output already exists: $output" }
New-Item -ItemType Directory -Path $output | Out-Null
Copy-Item -LiteralPath (Join-Path $release 'build-identity.json') -Destination $output
$environment = [ordered]@{
    captured_utc = [DateTime]::UtcNow.ToString('o')
    cpu = @(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors)
    os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,TotalVisibleMemorySize,FreePhysicalMemory
    adapters = @(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate)
    power = (& powercfg /getactivescheme)
    battery = @(Get-CimInstance Win32_Battery | Select-Object BatteryStatus,EstimatedChargeRemaining)
    background = @(Get-Process | Sort-Object CPU -Descending | Select-Object -First 12 ProcessName,Id,CPU,WorkingSet64)
    scope = if ($Display) { 'Release projection observations; presented frames and GPU require external capture' } else { 'headless Release simulation; no presented frames or GPU measurements' }
    process_observation_cadence_seconds = 1
}
$environment | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'environment.json') -Encoding utf8NoBOM
$failed = $false
foreach ($count in $Actors) {
    foreach ($speed in $Speeds) {
        $group = Join-Path $output ("actors-$count-speed-$speed")
        New-Item -ItemType Directory -Path $group | Out-Null
        $arguments = [string[]]@('--',"--actors=$count","--speed=$speed","--warmup=$WarmupSeconds","--sample=$SampleSeconds",('--output="' + $group + '"'))
        if (-not $Display) { $arguments = @('--headless') + $arguments }
        if ($Display) { $arguments += @('--display',"--window=$Window","--scene-scale=$($SceneScale.ToString([Globalization.CultureInfo]::InvariantCulture))","--ui-scale=$UiScale") }
        if ($Dense) { $arguments += '--dense' }
        if ($Profile) { $arguments += '--profile' }
        $windowStyle = if ($Visible) { 'Normal' } else { 'Hidden' }
        $process = Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle $windowStyle -PassThru -RedirectStandardOutput (Join-Path $group 'stdout.log') -RedirectStandardError (Join-Path $group 'stderr.log')
        $observations = [IO.StreamWriter]::new((Join-Path $group 'process.ndjson'),$false,[Text.UTF8Encoding]::new($false))
        try {
            while (-not $process.HasExited) {
                $process.Refresh()
                if (-not $process.HasExited) {
                    $sample = [ordered]@{real_utc=[DateTime]::UtcNow.ToString('o');process_id=$process.Id;working_set_bytes=$process.WorkingSet64;private_commit_bytes=$process.PrivateMemorySize64;lifetime_peak_working_set_bytes=$process.PeakWorkingSet64;cpu_seconds=$process.TotalProcessorTime.TotalSeconds}
                    $observations.WriteLine(($sample | ConvertTo-Json -Compress))
                    $observations.Flush()
                    [Threading.Thread]::Sleep(1000)
                }
            }
            $process.WaitForExit()
            $process.Refresh()
        }
        finally { $observations.Dispose() }
        $summaryPath = Join-Path $group 'summary.json'
        $exitCode = $process.ExitCode
        [ordered]@{exit_code=$exitCode;arguments=@($arguments);working_directory=$repo} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $group 'execution.json') -Encoding utf8NoBOM
        $scriptErrors = @(Select-String -LiteralPath (Join-Path $group 'stdout.log'),(Join-Path $group 'stderr.log') -Pattern 'SCRIPT ERROR:|ERROR:')
        [ordered]@{valid=($scriptErrors.Count -eq 0);script_error_count=$scriptErrors.Count;errors=@($scriptErrors | Select-Object -First 8 Line)} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $group 'validation.json') -Encoding utf8NoBOM
        if ($scriptErrors.Count -gt 0) { throw "Capture has runtime errors: $group/stderr.log" }
        if (-not (Test-Path -LiteralPath $summaryPath)) { throw "Capture produced no summary: $group (exit $exitCode)" }
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        if ($exitCode -ne 0) { $failed = $true }
        [ordered]@{completed_group="actors-$count-speed-$speed";step_p95_ms=$summary.step.p95_ms;speed_ratio=$summary.speed_ratio;passed=$summary.passed;formal=$summary.formal_capture} |
            ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $output 'progress.ndjson') -Encoding utf8NoBOM
        Write-Output "CAPTURE_GROUP=$count/$speed p95=$($summary.step.p95_ms)ms ratio=$($summary.speed_ratio) formal=$($summary.formal_capture) passed=$($summary.passed)"
    }
}
Write-Output "CAPTURE_ROOT=$output"
if ($failed) { exit 1 }
