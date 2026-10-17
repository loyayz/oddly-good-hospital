#requires -Version 7.0
[CmdletBinding()]
param([string]$Godot = 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$repo = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$windowsOutput = Join-Path $repo '.build/windows'
$installerOutput = Join-Path $repo '.build/installer'
$validationOutput = Join-Path $repo '.cache/validation'
Push-Location -LiteralPath $repo
try {
    & (Join-Path $PSScriptRoot 'prepare-stage01-tools.ps1') -Godot $Godot
    & (Join-Path $PSScriptRoot 'build-platform-guard.ps1') -GodotPath $Godot
    New-Item -ItemType Directory -Force -Path $windowsOutput,$installerOutput,$validationOutput | Out-Null
    & $Godot --headless --path $repo --import *> (Join-Path $validationOutput 'stage01-build-import.log')
    if ($LASTEXITCODE -ne 0) { throw 'Godot resource import failed.' }
    & $Godot --headless --path $repo --export-release 'Windows Stage01' (Join-Path $windowsOutput 'oddly-good-hospital.exe') *> (Join-Path $validationOutput 'stage01-export.log')
    if ($LASTEXITCODE -ne 0) { throw 'Godot Windows release export failed.' }
    $licenses = Join-Path $windowsOutput 'licenses'
    New-Item -ItemType Directory -Force -Path $licenses | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'assets/licenses/Godot-MIT.txt') -Destination (Join-Path $licenses 'Godot-MIT.txt')
    Copy-Item -LiteralPath (Join-Path $repo 'assets/fonts/OFL.txt') -Destination (Join-Path $licenses 'Noto-Sans-CJK-OFL.txt')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows/THIRD-PARTY-NOTICES.txt') -Destination (Join-Path $licenses 'THIRD-PARTY-NOTICES.txt')
    Copy-Item -Path (Join-Path $repo 'game/platform/windows/bin/licenses/*') -Destination $licenses -Force
    $packageFiles = @('oddly-good-hospital.exe','oddly-good-hospital.pck','oddly_good_platform.windows.x86_64.dll','libgmp-10.dll','libmpfr-6.dll','libgcc_s_seh-1.dll','libwinpthread-1.dll')
    $packageFiles += @(Get-ChildItem -LiteralPath $licenses -File | ForEach-Object { 'licenses/'+$_.Name })
    $fileIdentity = foreach ($relativePath in $packageFiles) {
        $filePath = Join-Path $windowsOutput $relativePath
        [PSCustomObject]@{ path = $relativePath; bytes = (Get-Item -LiteralPath $filePath).Length; sha256 = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    $gameVersion = [regex]::Match([IO.File]::ReadAllText((Join-Path $repo 'project.godot')),'config/version="([^"]+)"').Groups[1].Value
    [PSCustomObject]@{ product_id = 'oddly-good-hospital'; version = $gameVersion; engine = '4.7.2.stable.official.ed1daf0bf'; files = @($fileIdentity) } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $windowsOutput 'build-identity.json') -Encoding utf8NoBOM
    foreach ($previousName in @('OddlyGoodHospital.exe','OddlyGoodHospital.pck')) {
        $previousFile = Join-Path $windowsOutput $previousName
        if (Test-Path -LiteralPath $previousFile) { Remove-Item -LiteralPath $previousFile }
    }
    $nsis = Join-Path $repo '.cache/tools/nsis-3.13/makensis.exe'
    & $nsis /INPUTCHARSET UTF8 /V2 (Join-Path $PSScriptRoot 'windows/installer.nsi') *> (Join-Path $validationOutput 'stage01-installer-build.log')
    if ($LASTEXITCODE -ne 0) { throw 'NSIS installer build failed.' }
    Get-FileHash -LiteralPath (Join-Path $windowsOutput 'oddly-good-hospital.exe'),(Join-Path $windowsOutput 'oddly-good-hospital.pck'),(Join-Path $windowsOutput 'oddly_good_platform.windows.x86_64.dll'),(Join-Path $installerOutput 'oddly-good-hospital-stage01-setup.exe') -Algorithm SHA256
}
finally { Pop-Location }
