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
$zigRoot = Join-Path $repoRoot '.cache/native-math'
$zigArchive = Join-Path $zigRoot 'zig.zip'
$zigExe = Join-Path $zigRoot "$zigName/zig.exe"
$zigSha256 = '3a0ed1e8799a2f8ce2a6e6290a9ff22e6906f8227865911fb7ddedc3cc14cb0c'
$outputPath = Join-Path $repoRoot 'game/platform/windows/bin/oddly_good_platform.windows.x86_64.dll'
$sqliteVersion = '3.54.0'
$sqliteName = 'sqlite-amalgamation-3540000'
$sqliteRoot = Join-Path $cacheRoot $sqliteName
$sqliteArchive = Join-Path $cacheRoot "$sqliteName.zip"
$sqliteSha256 = '68e913b0fe8ec6b4e5f391c594a28872884e80d6cd042a1e50c957be46b5aa4d'

New-Item -ItemType Directory -Force $cacheRoot, $zigRoot, $abiRoot, (Split-Path $outputPath) | Out-Null
if (-not (Test-Path -LiteralPath $zigExe)) {
    if (-not (Test-Path -LiteralPath $zigArchive)) {
        Invoke-WebRequest -Uri "https://ziglang.org/download/$zigVersion/$zigName.zip" -OutFile $zigArchive
    }
    if ((Get-FileHash -LiteralPath $zigArchive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $zigSha256) {
        throw 'Zig archive SHA256 mismatch. Remove the incomplete cache archive before rebuilding.'
    }
    Expand-Archive -LiteralPath $zigArchive -DestinationPath $zigRoot -Force
}
$actualZigVersion = (& $zigExe version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $actualZigVersion -ne $zigVersion) { throw 'Unexpected Zig compiler version.' }
if (-not (Test-Path -LiteralPath $sqliteArchive)) {
    Invoke-WebRequest -Uri "https://sqlite.org/2026/$sqliteName.zip" -OutFile $sqliteArchive
}
if ((Get-FileHash -LiteralPath $sqliteArchive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sqliteSha256) {
    throw 'SQLite source archive SHA256 mismatch.'
}
Expand-Archive -LiteralPath $sqliteArchive -DestinationPath $cacheRoot -Force
$sqliteObject = Join-Path $abiRoot 'sqlite3.o'
$sqliteObjectIdentity = "$sqliteObject.sha256"
$sqliteCompileIdentity = "$sqliteSha256|Zig $zigVersion|x86_64-windows-gnu|O2|THREADSAFE=1|OMIT_LOAD_EXTENSION=1|DQS=0"
if (-not (Test-Path -LiteralPath $sqliteObject) -or -not (Test-Path -LiteralPath $sqliteObjectIdentity) -or
    (Get-Content -LiteralPath $sqliteObjectIdentity -Raw).Trim() -ne $sqliteCompileIdentity) {
    & $zigExe cc -target x86_64-windows-gnu -std=c11 -O2 -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION=1 -DSQLITE_DQS=0 `
        -c (Join-Path $sqliteRoot 'sqlite3.c') -o $sqliteObject
    if ($LASTEXITCODE -ne 0) { throw 'SQLite compilation failed.' }
    $sqliteCompileIdentity | Set-Content -LiteralPath $sqliteObjectIdentity -Encoding utf8NoBOM
}
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
$expectedSizes = @{ Variant = 24; String = 8; StringName = 8; Dictionary = 8; Array = 8; PackedByteArray = 16; PackedInt32Array = 16; PackedInt64Array = 16; Vector2 = 8; Rect2 = 16 }
foreach ($name in $expectedSizes.Keys) {
    if (($sizes | Where-Object name -eq $name).size -ne $expectedSizes[$name]) {
        throw "Unexpected engine ABI size for $name."
    }
}
$userDirHash = ($api.classes | Where-Object name -eq 'OS').methods | Where-Object name -eq 'get_user_data_dir' | Select-Object -ExpandProperty hash
$notificationHash = ($api.classes | Where-Object name -eq 'Object').methods | Where-Object name -eq 'notification' | Select-Object -ExpandProperty hash
$astarMethods = ($api.classes | Where-Object name -eq 'AStar2D').methods
$astarReserveHash = ($astarMethods | Where-Object name -eq 'reserve_space').hash
$astarAddHash = ($astarMethods | Where-Object name -eq 'add_point').hash
$astarDisableHash = ($astarMethods | Where-Object name -eq 'set_point_disabled').hash
$astarConnectHash = ($astarMethods | Where-Object name -eq 'connect_points').hash
$astarCountHash = ($astarMethods | Where-Object name -eq 'get_point_count').hash
$arrayMethods = ($api.builtin_classes | Where-Object name -eq 'Array').methods
$byteMethods = ($api.builtin_classes | Where-Object name -eq 'PackedByteArray').methods
$arraySizeHash = ($arrayMethods | Where-Object name -eq 'size').hash
$arrayAppendHash = ($arrayMethods | Where-Object name -eq 'append').hash
$bytesResizeHash = ($byteMethods | Where-Object name -eq 'resize').hash
$dictionaryKeysHash = (($api.builtin_classes | Where-Object name -eq 'Dictionary').methods | Where-Object name -eq 'keys').hash
$dictionaryGetHash = (($api.builtin_classes | Where-Object name -eq 'Dictionary').methods | Where-Object name -eq 'get').hash
if (-not $userDirHash -or -not $notificationHash -or -not $astarReserveHash -or -not $astarAddHash -or -not $astarDisableHash -or -not $astarConnectHash -or -not $astarCountHash) { throw 'The required engine method hashes are missing.' }
@"
#define OGH_VARIANT_SIZE 24
#define OGH_STRING_SIZE 8
#define OGH_STRING_NAME_SIZE 8
#define OGH_DICTIONARY_SIZE 8
#define OGH_ARRAY_SIZE 8
#define OGH_PACKED_BYTE_ARRAY_SIZE 16
#define OGH_PACKED_INT32_ARRAY_SIZE 16
#define OGH_PACKED_INT64_ARRAY_SIZE 16
#define OGH_ARRAY_SIZE_HASH $arraySizeHash
#define OGH_ARRAY_APPEND_HASH $arrayAppendHash
#define OGH_BYTES_RESIZE_HASH $bytesResizeHash
#define OGH_DICTIONARY_KEYS_HASH $dictionaryKeysHash
#define OGH_DICTIONARY_GET_HASH $dictionaryGetHash
#define OGH_USER_DIR_HASH $userDirHash
#define OGH_NOTIFICATION_HASH $notificationHash
#define OGH_ASTAR_RESERVE_HASH $astarReserveHash
#define OGH_ASTAR_ADD_HASH $astarAddHash
#define OGH_ASTAR_DISABLE_HASH $astarDisableHash
#define OGH_ASTAR_CONNECT_HASH $astarConnectHash
#define OGH_ASTAR_COUNT_HASH $astarCountHash
"@ | Set-Content -LiteralPath (Join-Path $abiRoot 'platform_guard_abi.h') -Encoding utf8NoBOM

$math = & (Join-Path $PSScriptRoot 'build-arrival-math.ps1') -Zig $zigExe -AbiRoot $abiRoot
$platformObject = Join-Path $abiRoot 'platform_session_guard.o'
& $zigExe cc -target x86_64-windows-gnu -std=c11 -O2 -Wall -Wextra -Werror -c `
    (Join-Path $repoRoot 'game/platform/windows/platform_session_guard.c') -I $abiRoot -I $sqliteRoot -o $platformObject
if ($LASTEXITCODE -ne 0) { throw 'Platform binding compilation failed.' }
& $zigExe c++ -target x86_64-windows-gnu -O2 -shared -s $platformObject $sqliteObject @($math.objects) @($math.libraries) -o $outputPath -lkernel32 -ladvapi32
if ($LASTEXITCODE -ne 0) { throw 'Platform bridge compilation failed.' }
[PSCustomObject]@{
    output = $outputPath
    bytes = (Get-Item -LiteralPath $outputPath).Length
    sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    engine = $actualGodotVersion
    compiler = "Zig $actualZigVersion"
    sqlite = $sqliteVersion
    sqlite_source_sha256 = $sqliteSha256
    arrival_math = $math
} | ConvertTo-Json -Compress
