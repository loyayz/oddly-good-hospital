#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GodotPath = 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cacheRoot = Join-Path $repoRoot '.cache/tools'
$abiRoot = Join-Path $repoRoot '.cache/platform-guard/abi'
$zigVersion = '0.15.2'
$zigName = "zig-x86_64-windows-$zigVersion"
$zigArchive = Join-Path $cacheRoot "$zigName.zip"
$zigExe = Join-Path $cacheRoot "$zigName/zig.exe"
$zigSha256 = '3a0ed1e8799a2f8ce2a6e6290a9ff22e6906f8227865911fb7ddedc3cc14cb0c'
$outputPath = Join-Path $repoRoot 'game/platform/windows/bin/oddly_good_platform.windows.x86_64.dll'

New-Item -ItemType Directory -Force $cacheRoot, $abiRoot, (Split-Path $outputPath) | Out-Null
if (-not (Test-Path -LiteralPath $zigExe)) {
    if (-not (Test-Path -LiteralPath $zigArchive)) {
        Invoke-WebRequest -Uri "https://ziglang.org/download/$zigVersion/$zigName.zip" -OutFile $zigArchive
    }
    if ((Get-FileHash -LiteralPath $zigArchive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $zigSha256) {
        throw 'Zig archive SHA256 mismatch. Remove the incomplete cache archive before rebuilding.'
    }
    Expand-Archive -LiteralPath $zigArchive -DestinationPath $cacheRoot -Force
}
$actualZigVersion = (& $zigExe version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $actualZigVersion -ne $zigVersion) { throw 'Unexpected Zig compiler version.' }
$actualGodotVersion = (& $GodotPath --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $actualGodotVersion -ne '4.7.2.stable.official.ed1daf0bf') {
    throw 'The platform bridge requires the fixed Godot 4.7.2 standard x86_64 engine.'
}

Push-Location $abiRoot
try {
    & $GodotPath --headless --dump-gdextension-interface
    if ($LASTEXITCODE -ne 0) { throw 'Godot GDExtension interface generation failed.' }
    & $GodotPath --headless --dump-extension-api
    if ($LASTEXITCODE -ne 0) { throw 'Godot extension API generation failed.' }
} finally {
    Pop-Location
}
$api = Get-Content -Raw -LiteralPath (Join-Path $abiRoot 'extension_api.json') | ConvertFrom-Json -Depth 100
if ($api.header.precision -ne 'single') { throw 'The bridge ABI requires single-precision Godot.' }
$sizes = ($api.builtin_class_sizes | Where-Object build_configuration -eq 'float_64').sizes
$expectedSizes = @{ Variant = 24; String = 8; StringName = 8; Dictionary = 8 }
foreach ($name in $expectedSizes.Keys) {
    if (($sizes | Where-Object name -eq $name).size -ne $expectedSizes[$name]) {
        throw "Unexpected engine ABI size for $name."
    }
}
$userDirHash = ($api.classes | Where-Object name -eq 'OS').methods | Where-Object name -eq 'get_user_data_dir' | Select-Object -ExpandProperty hash
$notificationHash = ($api.classes | Where-Object name -eq 'Object').methods | Where-Object name -eq 'notification' | Select-Object -ExpandProperty hash
if (-not $userDirHash -or -not $notificationHash) { throw 'The required engine method hashes are missing.' }
@"
#define OGH_VARIANT_SIZE 24
#define OGH_STRING_SIZE 8
#define OGH_STRING_NAME_SIZE 8
#define OGH_DICTIONARY_SIZE 8
#define OGH_USER_DIR_HASH $userDirHash
#define OGH_NOTIFICATION_HASH $notificationHash
"@ | Set-Content -LiteralPath (Join-Path $abiRoot 'platform_guard_abi.h') -Encoding utf8NoBOM

& $zigExe cc -target x86_64-windows-gnu -std=c11 -O2 -Wall -Wextra -Werror -shared -s `
    (Join-Path $repoRoot 'game/platform/windows/platform_session_guard.c') -I $abiRoot -o $outputPath -lkernel32
if ($LASTEXITCODE -ne 0) { throw 'Platform bridge compilation failed.' }
[PSCustomObject]@{
    output = $outputPath
    bytes = (Get-Item -LiteralPath $outputPath).Length
    sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    engine = $actualGodotVersion
    compiler = "Zig $actualZigVersion"
} | ConvertTo-Json -Compress
