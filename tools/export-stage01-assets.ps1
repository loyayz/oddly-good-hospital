param(
    [string]$BlenderPath = '',
    [string]$PythonPath = 'python',
    [switch]$PrepareBlender,
    [switch]$RenderSourcePreviews
)

$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskTools = Join-Path $taskRoot '.cache/tools'
$taskBlenderRoot = Join-Path $taskTools 'blender-4.5.14'
if (-not $BlenderPath) { $BlenderPath = Join-Path $taskBlenderRoot 'blender.exe' }
if ($PrepareBlender -and -not (Test-Path -LiteralPath $BlenderPath)) {
    New-Item -ItemType Directory -Force -Path $taskTools | Out-Null
    $taskArchive = Join-Path $taskTools 'blender-4.5.14-windows-x64.zip'
    if (-not (Test-Path -LiteralPath $taskArchive)) {
        & curl.exe --fail --location --silent --show-error --output $taskArchive 'https://download.blender.org/release/Blender4.5/blender-4.5.14-windows-x64.zip'
        if ($LASTEXITCODE -ne 0) { throw "Blender download failed: $LASTEXITCODE" }
    }
    $taskChecksum = (Get-FileHash -LiteralPath $taskArchive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($taskChecksum -ne 'b9533d2397ac1984db4466fb23a7a4649391cca93f6e84209f9bcc60d071c8b9') {
        throw 'Blender 4.5.14 archive checksum mismatch.'
    }
    New-Item -ItemType Directory -Force -Path $taskBlenderRoot | Out-Null
    & tar.exe -xf $taskArchive -C $taskBlenderRoot --strip-components=1
    if ($LASTEXITCODE -ne 0) { throw "Blender extraction failed: $LASTEXITCODE" }
}
if (-not (Test-Path -LiteralPath $BlenderPath)) {
    throw 'Blender 4.5.14 LTS is required for source export. Use -PrepareBlender or -BlenderPath.'
}
$taskVersion = & $BlenderPath --version
if ($LASTEXITCODE -ne 0 -or $taskVersion[0] -ne 'Blender 4.5.14 LTS') {
    throw "Expected Blender 4.5.14 LTS; received: $($taskVersion[0])"
}
$taskLogs = Join-Path $taskRoot '.cache/validation'
New-Item -ItemType Directory -Force -Path $taskLogs | Out-Null
& $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $taskRoot 'art-source/build_stage01.py') -- --root $taskRoot 2>&1 |
    Tee-Object -FilePath (Join-Path $taskLogs 'stage01-blender-export.log')
if ($LASTEXITCODE -ne 0) { throw "Blender source export failed: $LASTEXITCODE" }
if ($RenderSourcePreviews) {
    & $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $taskRoot 'art-source/preview_stage01.py') -- --root $taskRoot 2>&1 |
        Tee-Object -FilePath (Join-Path $taskLogs 'stage01-source-previews.log')
    if ($LASTEXITCODE -ne 0) { throw "GLB source preview failed: $LASTEXITCODE" }
}
