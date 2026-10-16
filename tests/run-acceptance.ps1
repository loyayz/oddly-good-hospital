#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('core','clinical','staff','operations','growth','space')][string[]]$Suite = @('core','clinical','staff','operations','growth','space'),
    [Alias('Case')][string[]]$CaseId = @(),
    [switch]$ListCases,
    [switch]$All,
    [switch]$RebuildFixtures,
    [string]$Godot = 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$runClock = [Diagnostics.Stopwatch]::StartNew()
$runStartedUtc = [DateTimeOffset]::UtcNow
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $All -and -not $ListCases -and -not $PSBoundParameters.ContainsKey('Suite') -and $CaseId.Count -eq 0) {
    throw 'Choose -Case, -Suite, -ListCases, or explicitly use -All for the complete suite.'
}
if ($All -and ($CaseId.Count -gt 0 -or $PSBoundParameters.ContainsKey('Suite'))) { throw '-All cannot be combined with -Case or -Suite.' }
$CaseId = @($CaseId | ForEach-Object { $_.Split(',') } | ForEach-Object { $_.Trim().ToUpperInvariant() })
if (@($CaseId | Sort-Object -Unique).Count -ne $CaseId.Count -or '' -in $CaseId) { throw 'Empty or duplicate acceptance case.' }
$catalog = foreach ($topic in @('core','clinical','staff','operations','growth','space')) {
    foreach ($line in Get-Content -LiteralPath (Join-Path $PSScriptRoot "acceptance/$topic.gd")) {
        if ($line -match '^\s*"((?:CORE|CLIN|STAFF|OPS|GROW|SPACE)-\d{2})"\s*:\s*"([^"]+)"') {
            [pscustomobject]@{ Suite=$topic; CaseId=$Matches[1]; Requirement=$Matches[2] }
        }
    }
}
foreach ($id in $CaseId) { if ($id -notin $catalog.CaseId) { throw "Unknown acceptance case: $id" } }
if ($CaseId.Count -gt 0 -and -not $PSBoundParameters.ContainsKey('Suite')) {
    $Suite = @($catalog | Where-Object CaseId -In $CaseId | Select-Object -ExpandProperty Suite -Unique)
}
if (@($Suite | Sort-Object -Unique).Count -ne $Suite.Count) { throw 'Duplicate acceptance suite.' }
foreach ($id in $CaseId) {
    if (($catalog | Where-Object CaseId -EQ $id).Suite -notin $Suite) { throw "Case $id is outside the selected suites." }
}
if ($ListCases) {
    $catalog | Where-Object { $_.Suite -in $Suite -and ($CaseId.Count -eq 0 -or $_.CaseId -in $CaseId) } | Format-Table -AutoSize
    return
}
$runId = [Guid]::NewGuid().ToString('N')
$target = Join-Path $repo ('.cache/acceptance/' + $runId)
New-Item -ItemType Directory -Path $target -Force | Out-Null
$paths = @(& git -c core.quotePath=false -C $repo ls-files --cached --others --exclude-standard | Sort-Object -Unique)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate acceptance source.' }
$identity = foreach ($relative in $paths) {
    $source = Join-Path $repo $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    $destination = Join-Path $target $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
    [ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$native = Join-Path $repo 'game/platform/windows/bin/oddly_good_platform.windows.x86_64.dll'
if (-not (Test-Path -LiteralPath $native -PathType Leaf)) { throw 'Build the platform library before acceptance.' }
$nativeTarget = Join-Path $target 'game/platform/windows/bin'
New-Item -ItemType Directory -Force -Path $nativeTarget,(Join-Path $target '.godot/imported') | Out-Null
Copy-Item -LiteralPath $native -Destination $nativeTarget
# Reuse imported immutable assets; editor state and hospital data are never copied.
Get-ChildItem -LiteralPath (Join-Path $repo '.godot/imported') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $target '.godot/imported')
}
$project = Join-Path $target 'project.godot'
$profile = 'OddlyGoodHospital Acceptance ' + $runId
$configuration = [IO.File]::ReadAllText($project)
$configuration.Replace('config/custom_user_dir_name="oddly-good-hospital"',('config/custom_user_dir_name="' + $profile + '"')) | Set-Content -LiteralPath $project -Encoding utf8NoBOM
$importArguments = @('--headless','--editor','--path',$target,'--import','--quit')
$arguments = @('--headless','--path',$target,'--script','res://tests/acceptance/runner.gd','--') + $Suite
foreach ($selectedCase in $CaseId) { $arguments += '--case=' + $selectedCase }
$engineHash = (Get-FileHash -LiteralPath $Godot -Algorithm SHA256).Hash
$nativeHash = (Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash
# Real prefix generation steps all simulation services. Their source, content,
# assets and runtime identities invalidate generated states; unrelated docs and
# case assertions do not. Each fixture builder adds its own identity in Godot.
$fixtureSources = @($identity | Where-Object { $_.path -match '^(game/|content/|assets/|project\.godot$)' })
$fixtureIdentity = [ordered]@{ source=$fixtureSources; engine=$engineHash; native=$nativeHash }
$fixtureBytes = [Text.Encoding]::UTF8.GetBytes(($fixtureIdentity | ConvertTo-Json -Depth 8 -Compress))
$fixtureHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($fixtureBytes)).ToLowerInvariant()
[ordered]@{ directory=(Join-Path $repo '.cache/acceptance-checkpoints'); identity=$fixtureHash; rebuild=[bool]$RebuildFixtures } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $target 'fixture-config.json') -Encoding utf8NoBOM
[ordered]@{
    head=(& git -C $repo rev-parse HEAD); cwd=$repo; project=$target; profile=$profile
    engine=$Godot; engine_sha256=$engineHash
    native_sha256=$nativeHash; fixture_identity=$fixtureHash; rebuild_fixtures=[bool]$RebuildFixtures
    import_arguments=$importArguments; test_arguments=$arguments; source=$identity
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $target 'source-identity.json') -Encoding utf8NoBOM
Write-Output "ACCEPTANCE_PROJECT=$target"
$timing = [ordered]@{
    started_at_utc=$runStartedUtc.ToString('o'); ended_at_utc=$null
    phase='import'; completed=$false; preparation_ms=$runClock.ElapsedMilliseconds
    import_ms=$null; tests_ms=$null; total_ms=$null
}
$timingPath = Join-Path $target 'timing-summary.json'
$timing | ConvertTo-Json | Set-Content -LiteralPath $timingPath -Encoding utf8NoBOM
$importLog = Join-Path $target 'import.log'
$importStarted = $runClock.ElapsedMilliseconds
& $Godot @importArguments *> $importLog
$importExit = $LASTEXITCODE
$timing.import_ms = $runClock.ElapsedMilliseconds - $importStarted
if ($importExit -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR:|Parse Error:|ERROR:' -Quiet)) {
    $timing.phase = 'import_failed'
    $timing.ended_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
    $timing.total_ms = $runClock.ElapsedMilliseconds
    $timing | ConvertTo-Json | Set-Content -LiteralPath $timingPath -Encoding utf8NoBOM
    Get-Content -LiteralPath $importLog -Tail 40
    throw "Acceptance import failed: exit=$importExit log=$importLog"
}
$timing.phase = 'tests'
$timing | ConvertTo-Json | Set-Content -LiteralPath $timingPath -Encoding utf8NoBOM
$testLog = Join-Path $target 'execution.log'
$testStarted = $runClock.ElapsedMilliseconds
& $Godot @arguments *> $testLog
$testExit = $LASTEXITCODE
$timing.tests_ms = $runClock.ElapsedMilliseconds - $testStarted
$timing.ended_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
$timing.total_ms = $runClock.ElapsedMilliseconds
$timing.completed = $true
$timing.phase = 'finished'
$timing | ConvertTo-Json | Set-Content -LiteralPath $timingPath -Encoding utf8NoBOM
$scriptErrors = [bool](Select-String -LiteralPath $testLog -Pattern 'SCRIPT ERROR:|Parse Error:|ERROR:' -Quiet)
[ordered]@{import_exit=$importExit;test_exit=$testExit;script_errors=$scriptErrors;log=$testLog} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $target 'execution-status.json') -Encoding utf8NoBOM
Get-Content -LiteralPath $testLog
if ($testExit -ne 0 -or $scriptErrors) { throw "Acceptance failed: exit=$testExit log=$testLog" }
Write-Output "ACCEPTANCE_PASS=$target"
