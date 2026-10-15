param(
    [string]$BlenderPath = '',
    [string]$PythonPath = 'python',
    [switch]$RenderSourcePreview
)

$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
if (-not $BlenderPath) { $BlenderPath = Join-Path $taskRoot '.cache/tools/blender-4.5.14/blender.exe' }
if (-not (Test-Path -LiteralPath $BlenderPath)) { throw 'Blender 4.5.14 LTS is required for gag source export.' }
$taskVersion = & $BlenderPath --version
if ($LASTEXITCODE -ne 0 -or $taskVersion[0] -ne 'Blender 4.5.14 LTS') { throw "Expected Blender 4.5.14 LTS; received: $($taskVersion[0])" }
$taskLogs = Join-Path $taskRoot '.cache/validation'
New-Item -ItemType Directory -Force -Path $taskLogs | Out-Null
& $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $taskRoot 'art-source/gags/build_gags.py') -- --root $taskRoot 2>&1 |
    Tee-Object -FilePath (Join-Path $taskLogs 'stage01-gags-export.log')
if ($LASTEXITCODE -ne 0) { throw "Blender gag export failed: $LASTEXITCODE" }
if ($RenderSourcePreview) {
    & $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $taskRoot 'art-source/gags/preview_gags.py') -- --root $taskRoot 2>&1 |
        Tee-Object -FilePath (Join-Path $taskLogs 'stage01-gags-source-preview.log')
    if ($LASTEXITCODE -ne 0) { throw "Gag source preview failed: $LASTEXITCODE" }
}
