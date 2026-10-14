#requires -Version 7.0
[CmdletBinding()]
param([string]$Godot = 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$repo = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cache = Join-Path $repo '.cache/tools'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
if ((& $Godot --version) -ne '4.7.2.stable.official.ed1daf0bf') { throw 'Godot 4.7.2 standard engine is required.' }
$archive = Join-Path $cache 'Godot_v4.7.2-stable_export_templates.tpz'
$expected = 'f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011'
if (-not (Test-Path -LiteralPath $archive) -or (Get-Item -LiteralPath $archive).Length -lt 1281349702) {
    & curl.exe --fail --location --silent --show-error --continue-at - --output $archive 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'
    if ($LASTEXITCODE -ne 0) { throw 'Export template download interrupted; the pinned archive can be resumed.' }
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'Export template SHA-256 mismatch.' }
$templates = Join-Path $cache 'godot-4.7.2'
New-Item -ItemType Directory -Force -Path $templates | Out-Null
& tar.exe -xf $archive -C $templates templates/windows_release_x86_64.exe templates/windows_debug_x86_64.exe
if ($LASTEXITCODE -ne 0) { throw 'Windows template extraction failed.' }
Write-Output "GODOT_TEMPLATES=$templates/templates"

$nsisArchive = Join-Path $cache 'nsis-3.13.zip'
$nsisSha256 = 'ba63dffc4410ee89193e1cb5a41989991bd77c61068da17e3156d136b7b0b3d8'
if (-not (Test-Path -LiteralPath $nsisArchive) -or (Get-Item -LiteralPath $nsisArchive).Length -lt 2363925) {
    & curl.exe --fail --location --silent --show-error --continue-at - --output $nsisArchive 'https://downloads.sourceforge.net/project/nsis/NSIS%203/3.13/nsis-3.13.zip'
    if ($LASTEXITCODE -ne 0) { throw 'NSIS download interrupted; the pinned archive can be resumed.' }
}
if ((Get-FileHash -LiteralPath $nsisArchive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $nsisSha256) {
    throw 'NSIS 3.13 archive SHA-256 mismatch.'
}
$nsisExe = Join-Path $cache 'nsis-3.13/makensis.exe'
if (-not (Test-Path -LiteralPath $nsisExe)) {
    Expand-Archive -LiteralPath $nsisArchive -DestinationPath $cache -Force
}
$nsisVersion = (& $nsisExe /VERSION | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $nsisVersion -ne 'v3.13') { throw 'NSIS 3.13 portable is required.' }
Write-Output "NSIS=$nsisExe"
