#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Zig)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cache = Join-Path $repo '.cache/native-math'
$dependencies = Join-Path $cache 'ucrt64'
function Get-Archive([string]$Name, [string]$Url, [string]$Sha) {
    $path = Join-Path $cache $Name
    if (-not (Test-Path -LiteralPath $path)) {
        try { Invoke-WebRequest $Url -OutFile $path -TimeoutSec 120 }
        catch { throw "Download failed: $Name (HTTP $($_.Exception.Response.StatusCode))" }
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha) { throw "Source archive SHA256 mismatch: $Name" }
    return $path
}
function Write-Changed([string]$Path, [string]$Value) {
    if (-not (Test-Path -LiteralPath $Path) -or [IO.File]::ReadAllText($Path) -ne $Value) { [IO.File]::WriteAllText($Path,$Value,[Text.UTF8Encoding]::new($false)) }
}
function Invoke-CMake([string[]]$Arguments, [string]$Log) {
    & $cmake @Arguments *> $Log
    if ($LASTEXITCODE) { Get-Content -LiteralPath $Log -Tail 26; throw "Native dependency build failed: $Log" }
}
function Configure-Native([string]$Build, [string[]]$Arguments, [string]$Log) {
    $identity = (Get-FileHash -LiteralPath $toolchain -Algorithm SHA256).Hash
    $stamp = Join-Path $Build 'toolchain.sha256'
    $fresh = @()
    if (-not (Test-Path -LiteralPath $stamp) -or [IO.File]::ReadAllText($stamp) -ne $identity) { $fresh = @('--fresh') }
    Invoke-CMake ($fresh + $Arguments) $Log
    [IO.File]::WriteAllText($stamp,$identity)
}

$scipSha = 'fe8cfd15a03970ef45156ed56c6a4382485bd095e0e99cf7d7db87cdf8d47304'
$mpfrSha = '6b70a275d2ec75c70aa50a236c218e6b7ee9a5ab4c6d52cb0b580267b7d200fe'
$scip = Get-Archive 'scip-10.1.0.tgz' 'https://scipopt.org/download/release/scip-10.1.0.tgz' $scipSha
$mpfr = Get-Archive 'mpfr.pkg.tar.zst' 'https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-mpfr-4.2.2-3-any.pkg.tar.zst' $mpfrSha
$mpfrSource = Get-Archive 'mpfr-source.tar.zst' 'https://repo.msys2.org/mingw/sources/mingw-w64-mpfr-4.2.2-3.src.tar.zst' 'c8c9b1e091b744165b150d59b7599bcf014fe9c3ae21df98fd3807f05f702c60'
$gccSha = '80b2497f019977dd9528b1abc8621b1328a0115ab1f724047ccbb56bf323f11d'
$pthreadSha = 'a02f5e09d666d3be657c78c86fe67c975d04fe33b5211cd5ff1b23a91c118524'
$gcc = Get-Archive 'libgcc.pkg.tar.zst' 'https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-libgcc-16.2.0-6-any.pkg.tar.zst' $gccSha
$pthread = Get-Archive 'winpthread.pkg.tar.zst' 'https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-libwinpthread-14.0.0.r426.g4564ee4b5-2-any.pkg.tar.zst' $pthreadSha
$gccSource = Get-Archive 'gcc-source.tar.zst' 'https://repo.msys2.org/mingw/sources/mingw-w64-gcc-16.2.0-6.src.tar.zst' 'a901d8afb78438abcff9ed020cd9aa9431db76de1992171c2454c3c07ad289e8'
$cmakeZip = Get-Archive 'cmake.whl' 'https://files.pythonhosted.org/packages/be/36/77db223c6619aa11817040d9b0a9c232c9e26c86780cd676ff83e110ae73/cmake-4.1.2-py3-none-win_amd64.whl' '0a5edb762341220649794580b3b9608ea782b5ba6a3f7fe4e21eb4a4f705ec39'
$ninjaZip = Get-Archive 'ninja.whl' 'https://files.pythonhosted.org/packages/29/45/c0adfbfb0b5895aa18cec400c535b4f7ff3e52536e0403602fc1a23f7de9/ninja-1.13.0-py3-none-win_amd64.whl' 'fb8ee8719f8af47fed145cced4a85f0755dd55d45b2bddaf7431fa89803c5f3e'
if (-not (Test-Path -LiteralPath (Join-Path $cache 'scip-10.1.0/src/scip/scip.h'))) { & tar -xf $scip -C $cache; if ($LASTEXITCODE) { throw 'SCIP extraction failed' } }
if (-not (Test-Path -LiteralPath (Join-Path $dependencies 'include/mpfr.h'))) { & tar -xf $mpfr -C $cache; if ($LASTEXITCODE) { throw 'MPFR extraction failed' } }
if (-not (Test-Path -LiteralPath (Join-Path $dependencies 'bin/libgcc_s_seh-1.dll'))) { & tar -xf $gcc -C $cache; if ($LASTEXITCODE) { throw 'GCC runtime extraction failed' } }
if (-not (Test-Path -LiteralPath (Join-Path $dependencies 'bin/libwinpthread-1.dll'))) { & tar -xf $pthread -C $cache; if ($LASTEXITCODE) { throw 'winpthreads extraction failed' } }
if (-not (Test-Path -LiteralPath (Join-Path $dependencies 'lib/cmake/Boost-1.92.0/BoostConfig.cmake'))) {
    & tar -xf (Join-Path $cache 'boost.pkg.tar.zst') -C $cache ucrt64/lib/cmake/Boost-1.92.0 ucrt64/lib/cmake/boost_headers-1.92.0
    if ($LASTEXITCODE) { throw 'Boost CMake package extraction failed' }
}
if (-not (Test-Path -LiteralPath (Join-Path $cache 'cmake-4.1.2'))) { [IO.Compression.ZipFile]::ExtractToDirectory($cmakeZip,(Join-Path $cache 'cmake-4.1.2')) }
if (-not (Test-Path -LiteralPath (Join-Path $cache 'ninja-1.13.0'))) { [IO.Compression.ZipFile]::ExtractToDirectory($ninjaZip,(Join-Path $cache 'ninja-1.13.0')) }
$cmake = Join-Path $cache 'cmake-4.1.2/cmake/data/bin/cmake.exe'
$ninja = Join-Path $cache 'ninja-1.13.0/ninja-1.13.0.data/scripts/ninja.exe'
$zigPath = $Zig.Replace([char]92,[char]47)
$ar = Join-Path $cache 'zig-ar.cmd'
$ranlib = Join-Path $cache 'zig-ranlib.cmd'
Write-Changed $ar "@echo off`r`n`"$zigPath`" ar %*`r`n"
Write-Changed $ranlib "@echo off`r`n`"$zigPath`" ranlib %*`r`n"
$arPath = $ar.Replace([char]92,[char]47)
$ranlibPath = $ranlib.Replace([char]92,[char]47)
$toolchain = Join-Path $cache 'zig-toolchain.cmake'
Write-Changed $toolchain @"
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_C_COMPILER "$zigPath")
set(CMAKE_C_COMPILER_ARG1 cc)
set(CMAKE_CXX_COMPILER "$zigPath")
set(CMAKE_CXX_COMPILER_ARG1 c++)
set(CMAKE_C_FLAGS_INIT "-target x86_64-windows-gnu")
set(CMAKE_CXX_FLAGS_INIT "-target x86_64-windows-gnu")
set(CMAKE_AR "$arPath")
set(CMAKE_RANLIB "$ranlibPath")
"@
$soplexBuild = Join-Path $cache 'soplex-native'
$scipBuild = Join-Path $cache 'scip-native'
$common = @('-G','Ninja',"-DCMAKE_MAKE_PROGRAM=$ninja","-DCMAKE_TOOLCHAIN_FILE=$toolchain",'-DCMAKE_BUILD_TYPE=Release',"-DGMP_DIR=$dependencies","-DGMP_LIBRARY=$(Join-Path $dependencies 'lib/libgmp.dll.a')","-DGMPXX_LIBRARY=$(Join-Path $dependencies 'lib/libgmpxx.dll.a')","-DMPFR_DIR=$dependencies","-DMPFR_LIBRARY=$(Join-Path $dependencies 'lib/libmpfr.dll.a')","-DBoost_DIR=$(Join-Path $dependencies 'lib/cmake/Boost-1.92.0')",'-DPAPILO=OFF','-DZLIB=OFF')
Configure-Native $soplexBuild (@('-S',(Join-Path $cache 'soplex-a00610534e044f35aa298059eb963312336c4c9c'),'-B',$soplexBuild)+$common+@('-DGMP=ON','-DBOOST=ON','-DMPFR=ON')) (Join-Path $cache 'soplex-configure.log')
$soplexConfig = [IO.File]::ReadAllText((Join-Path $soplexBuild 'soplex/config.h'))
foreach ($feature in 'GMP','BOOST','MPFR') {
    if ($soplexConfig -notmatch "(?m)^#define SOPLEX_WITH_$feature\b") { throw "SoPlex requires $feature support" }
}
Invoke-CMake @('--build',$soplexBuild,'--target','libsoplex','--parallel','6') (Join-Path $cache 'soplex-build.log')
Configure-Native $scipBuild (@('-S',(Join-Path $cache 'scip-10.1.0'),'-B',$scipBuild)+$common+@("-DSOPLEX_DIR=$soplexBuild",'-DSHARED=OFF','-DGMP=ON','-DMPFR=ON','-DEXACTSOLVE=ON','-DREADLINE=OFF','-DZIMPL=OFF','-DAMPL=OFF','-DIPOPT=OFF','-DEXPRINT=none','-DSYM=none','-DTPI=none','-DLPS=spx','-DLPSEXACT=spx')) (Join-Path $cache 'scip-configure.log')
Invoke-CMake @('--build',$scipBuild,'--target','libscip','--parallel','6') (Join-Path $cache 'scip-build.log')

$output = Join-Path $repo 'game/platform/windows/bin'
New-Item -ItemType Directory -Force $output,(Join-Path $output 'licenses') | Out-Null
Copy-Item -LiteralPath (Join-Path $dependencies 'bin/libmpfr-6.dll') -Destination $output -Force
foreach ($name in 'libgcc_s_seh-1.dll','libwinpthread-1.dll') { Copy-Item -LiteralPath (Join-Path $dependencies "bin/$name") -Destination $output -Force }
$licenses = Join-Path $output 'licenses'
Copy-Item -LiteralPath (Join-Path $dependencies 'share/licenses/libgcc/COPYING.RUNTIME') -Destination (Join-Path $licenses 'GCC-Runtime-Exception-3.1.txt') -Force
Copy-Item -LiteralPath (Join-Path $dependencies 'share/licenses/libwinpthread/COPYING') -Destination (Join-Path $licenses 'winpthreads-MIT-BSD.txt') -Force
Copy-Item -LiteralPath $gccSource -Destination (Join-Path $licenses 'gcc-16.2.0-6-source.tar.zst') -Force
Copy-Item -LiteralPath (Join-Path $cache 'scip-10.1.0/LICENSE') -Destination (Join-Path $licenses 'SCIP-Apache-2.0.txt') -Force
Copy-Item -LiteralPath $mpfrSource -Destination (Join-Path $licenses 'mpfr-4.2.2-3-source.tar.zst') -Force
& tar -xf $mpfrSource -C $cache mingw-w64-mpfr/mpfr-4.2.2.tar.xz
if ($LASTEXITCODE) { throw 'MPFR source extraction failed' }
& tar -xf (Join-Path $cache 'mingw-w64-mpfr/mpfr-4.2.2.tar.xz') -C $cache mpfr-4.2.2/COPYING.LESSER
if ($LASTEXITCODE) { throw 'MPFR license extraction failed' }
Copy-Item -LiteralPath (Join-Path $cache 'mpfr-4.2.2/COPYING.LESSER') -Destination (Join-Path $licenses 'MPFR-LGPL-3.0.txt') -Force
[PSCustomObject]@{soplex_library=(Join-Path $soplexBuild 'lib/libsoplex.a');scip_library=(Join-Path $scipBuild 'lib/libscip.a');soplex_include=$soplexBuild;scip_include=$scipBuild;scip_source=(Join-Path $cache 'scip-10.1.0/src');mpfr_import=(Join-Path $dependencies 'lib/libmpfr.dll.a');scip='10.1.0';mpfr='4.2.2-3';gcc='16.2.0-6';winpthreads='14.0.0.r426.g4564ee4b5-2';source_sha256=@($scipSha,$mpfrSha,$gccSha,$pthreadSha)}
