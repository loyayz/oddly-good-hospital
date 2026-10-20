#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Zig)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cache = Join-Path $repo '.cache/native-zip'
New-Item -ItemType Directory -Force $cache | Out-Null
function Get-SourceArchive([string]$Name, [string]$Url, [string]$Sha) {
    $path = Join-Path $cache $Name
    if (-not (Test-Path -LiteralPath $path)) { Invoke-WebRequest $Url -OutFile $path }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha) { throw "Source archive SHA256 mismatch: $Name" }
    return $path
}
$minizipSha = '71af7b9799856d8b03619df3949e9c1be9703f8de0795af71399ba283cb27aac'
$zlibSha = 'bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16'
$minizip = Get-SourceArchive 'minizip-ng-4.2.2.tar.gz' 'https://codeload.github.com/zlib-ng/minizip-ng/tar.gz/refs/tags/4.2.2' $minizipSha
$zlib = Get-SourceArchive 'zlib-1.3.2.tar.gz' 'https://zlib.net/fossils/zlib-1.3.2.tar.gz' $zlibSha
$minizipRoot = Join-Path $cache 'minizip-ng-4.2.2'
$zlibRoot = Join-Path $cache 'zlib-1.3.2'
foreach ($source in @(@($minizip,$minizipRoot),@($zlib,$zlibRoot))) {
    if (-not (Test-Path -LiteralPath $source[1])) {
        & tar -xf $source[0] -C $cache
        if ($LASTEXITCODE) { throw 'Backup ZIP dependency extraction failed' }
    }
}
$objects = Join-Path $cache 'objects'
$config = Join-Path $cache 'config'
New-Item -ItemType Directory -Force $objects,$config | Out-Null
# minizip 4.2 generates mz_config.h from mz_config.h.cmakein. This build is
# exclusively x86_64-windows-gnu and uses mz_os_win32, not POSIX directory/IO
# adapters. Keep that target profile explicit for reproducible offline builds.
@'
#ifndef MZ_CONFIG_H
#define MZ_CONFIG_H
#define HAVE_DIRENT_H 0
#define HAVE_SYS_DIRENT_H 0
#define HAVE_INTTYPES_H 1
#define HAVE_STDINT_H 1
#define HAVE_PDIR 0
#define HAVE_FSEEKO 0
#define HAVE_SYMLINK 0
#define HAVE_READLINK 0
#endif
'@ | Set-Content -LiteralPath (Join-Path $config 'mz_config.h') -Encoding utf8NoBOM
$adapter = Join-Path $repo 'game/platform/windows/platform_backup_zip.c'
$identity = @($minizipSha,$zlibSha,(Get-FileHash -LiteralPath $adapter -Algorithm SHA256).Hash,(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash,(& $Zig version)) -join ':'
$library = Join-Path $cache 'libhospital-backup-zip.a'
$stamp = Join-Path $cache 'build.identity'
if (-not (Test-Path -LiteralPath $library) -or -not (Test-Path -LiteralPath $stamp) -or (Get-Content -LiteralPath $stamp -Raw).Trim() -ne $identity) {
    $flags = @('cc','-target','x86_64-windows-gnu','-std=c11','-O2','-DNDEBUG','-DHAVE_ZLIB','-DZLIB_COMPAT','-DMZ_ZIP_NO_ENCRYPTION','-DMZ_ZIP_NO_CRYPTO','-I',$config,'-I',$minizipRoot,'-I',$zlibRoot)
    $sources = @('mz_crypt.c','mz_os.c','mz_os_win32.c','mz_strm.c','mz_strm_mem.c','mz_strm_os_win32.c','mz_strm_zlib.c') | ForEach-Object { Join-Path $minizipRoot $_ }
    $sources += @('adler32.c','crc32.c','deflate.c','infback.c','inffast.c','inflate.c','inftrees.c','trees.c','zutil.c','compress.c','uncompr.c') | ForEach-Object { Join-Path $zlibRoot $_ }
    $sources += $adapter
    $compiled = @()
    foreach ($source in $sources) {
        $object = Join-Path $objects (([IO.Path]::GetFileNameWithoutExtension($source))+'.o')
        & $Zig @flags -c $source -o $object
        if ($LASTEXITCODE) { throw "Backup ZIP dependency compilation failed: $source" }
        $compiled += $object
    }
    & $Zig ar rcs $library @compiled
    if ($LASTEXITCODE) { throw 'Backup ZIP dependency archive creation failed' }
    $identity | Set-Content -LiteralPath $stamp -Encoding utf8NoBOM
}
$licenses = Join-Path $repo 'game/platform/windows/bin/licenses'
New-Item -ItemType Directory -Force $licenses | Out-Null
Copy-Item -LiteralPath (Join-Path $minizipRoot 'LICENSE') -Destination (Join-Path $licenses 'minizip-ng-zlib.txt') -Force
Copy-Item -LiteralPath (Join-Path $zlibRoot 'LICENSE') -Destination (Join-Path $licenses 'zlib.txt') -Force
[PSCustomObject]@{include=@($config,$minizipRoot,$zlibRoot);libraries=@($library);minizip_ng='4.2.2';zlib='1.3.2';source_sha256=@($minizipSha,$zlibSha)}
