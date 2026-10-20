#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Zig, [Parameter(Mandatory)][string]$AbiRoot)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cache = Join-Path $repo '.cache/native-math'
New-Item -ItemType Directory -Force $cache,(Join-Path $AbiRoot 'soplex') | Out-Null
function Get-Archive([string]$Name, [string]$Url, [string]$Sha) {
    $path = Join-Path $cache $Name
    if (-not (Test-Path -LiteralPath $path)) { Invoke-WebRequest $Url -OutFile $path }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha) { throw "Source archive SHA256 mismatch: $Name" }
    return $path
}
$soplexSha = '67630bc95203933a3f1145ba7fad512b7f68f59dc18029eee74ac381298f56d8'
$gmpSha = 'e82a75968a556484a50084578238a84eb60fb93e34986fd6695c537975bd39ea'
$boostSha = '2f9935335e17f9930cba7e93a8db95bf699df2dd1c250cffe6dce89c7ea70154'
$soplex = Get-Archive 'soplex-8.1.0.tar.gz' 'https://codeload.github.com/scipopt/soplex/tar.gz/a00610534e044f35aa298059eb963312336c4c9c' $soplexSha
$gmp = Get-Archive 'gmp.pkg.tar.zst' 'https://mirror.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-gmp-6.3.0-2-any.pkg.tar.zst' $gmpSha
$boost = Get-Archive 'boost.pkg.tar.zst' 'https://mirror.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-boost-1.92.0-4-any.pkg.tar.zst' $boostSha
$gmpSource = Get-Archive 'gmp-source.tar.zst' 'https://mirror.msys2.org/mingw/sources/mingw-w64-gmp-6.3.0-2.src.tar.zst' 'f288f944fd9609db220bcf6a8dd0703a5674eeb906ef35eb8485bb8192135994'
$source = Join-Path $cache 'soplex-a00610534e044f35aa298059eb963312336c4c9c/src'
$dependencies = Join-Path $cache 'ucrt64'
if (-not (Test-Path -LiteralPath $source)) { & tar -xf $soplex -C $cache; if ($LASTEXITCODE) { throw 'SoPlex extraction failed' } }
if (-not (Test-Path -LiteralPath (Join-Path $dependencies 'include/gmp.h'))) { & tar -xf $gmp -C $cache; if ($LASTEXITCODE) { throw 'GMP extraction failed' } }
if (-not (Test-Path -LiteralPath (Join-Path $dependencies 'include/boost/version.hpp'))) {
    & tar -xf $boost -C $cache ucrt64/include/boost ucrt64/share/licenses/boost
    if ($LASTEXITCODE) { throw 'Boost extraction failed' }
}
$discrete = & (Join-Path $PSScriptRoot 'build-arrival-discrete.ps1') -Zig $Zig
$json = & (Join-Path $PSScriptRoot 'build-json-stream.ps1')
$backup = & (Join-Path $PSScriptRoot 'build-backup-zip.ps1') -Zig $Zig
Copy-Item -LiteralPath (Join-Path $discrete.soplex_include 'soplex/config.h') -Destination (Join-Path $AbiRoot 'soplex/config.h') -Force
$flags = @('c++','-target','x86_64-windows-gnu','-std=c++17','-O2','-DNDEBUG','-DSCIP_STATIC_DEFINE','-I',$AbiRoot,'-isystem',$source,'-isystem',$discrete.soplex_include,'-isystem',$discrete.scip_include,'-isystem',$discrete.scip_source,'-isystem',(Join-Path $dependencies 'include'),'-isystem',$json.include)
foreach ($include in $backup.include) { $flags += @('-isystem',$include) }
$backend = Join-Path $AbiRoot 'platform_arrivals.o'
& $Zig @flags -Wall -Wextra -Werror -c (Join-Path $repo 'game/platform/windows/platform_arrivals.cpp') -o $backend
if ($LASTEXITCODE) { throw 'Arrival math backend compilation failed' }
$output = Join-Path $repo 'game/platform/windows/bin'
Copy-Item -LiteralPath (Join-Path $dependencies 'bin/libgmp-10.dll') -Destination $output -Force
$licenses = Join-Path $output 'licenses'
New-Item -ItemType Directory -Force $licenses | Out-Null
Copy-Item -LiteralPath $gmpSource -Destination (Join-Path $licenses 'gmp-6.3.0-2-source.tar.zst') -Force
Copy-Item -LiteralPath (Join-Path $cache 'soplex-a00610534e044f35aa298059eb963312336c4c9c/LICENSE') -Destination (Join-Path $licenses 'SoPlex-Apache-2.0.txt') -Force
Copy-Item -LiteralPath (Join-Path $dependencies 'share/licenses/boost/LICENSE') -Destination (Join-Path $licenses 'Boost-1.0.txt') -Force
& tar -xf $gmpSource -C $cache mingw-w64-gmp/gmp-6.3.0.tar.xz
if ($LASTEXITCODE) { throw 'GMP source extraction failed' }
& tar -xf (Join-Path $cache 'mingw-w64-gmp/gmp-6.3.0.tar.xz') -C $cache gmp-6.3.0/COPYING.LESSERv3 gmp-6.3.0/COPYINGv3
if ($LASTEXITCODE) { throw 'GMP license extraction failed' }
Copy-Item -LiteralPath (Join-Path $cache 'gmp-6.3.0/COPYING.LESSERv3') -Destination (Join-Path $licenses 'GMP-LGPL-3.0.txt') -Force
Copy-Item -LiteralPath (Join-Path $cache 'gmp-6.3.0/COPYINGv3') -Destination (Join-Path $licenses 'GNU-GPL-3.0.txt') -Force
$fmtHeader = Get-Content -LiteralPath (Join-Path $source 'soplex/external/fmt/format.h') -Raw
[regex]::Match($fmtHeader,'(?s)^/\*.*?\*/').Value | Set-Content -LiteralPath (Join-Path $licenses 'fmt-MIT.txt') -Encoding utf8NoBOM
[PSCustomObject]@{objects=@($backend);libraries=@($discrete.scip_library,$discrete.soplex_library,$discrete.mpfr_import,(Join-Path $dependencies 'lib/libgmp.dll.a'))+$backup.libraries;soplex='8.1.0';scip=$discrete.scip;mpfr=$discrete.mpfr;gcc=$discrete.gcc;winpthreads=$discrete.winpthreads;gmp='6.3.0-2';boost='1.92.0-4';rapidjson=$json.rapidjson;minizip_ng=$backup.minizip_ng;zlib=$backup.zlib;source_sha256=@($soplexSha,$gmpSha,$boostSha)+$discrete.source_sha256+@($json.source_sha256)+$backup.source_sha256}
