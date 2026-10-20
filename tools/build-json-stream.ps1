#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cache = Join-Path $repo '.cache/native-math'
$revision = '24b5e7a8b27f42fa16b96fc70aade9106cf7102f'
$sha = '2d2601a82d2d3b7e143a3c8d43ef616671391034bc46891a9816b79cf2d3e7a8'
$archive = Join-Path $cache "rapidjson-$revision.tar.gz"
New-Item -ItemType Directory -Force $cache | Out-Null
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest "https://codeload.github.com/Tencent/rapidjson/tar.gz/$revision" -OutFile $archive -TimeoutSec 180
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha) { throw 'RapidJSON source archive SHA256 mismatch' }
$source = Join-Path $cache "rapidjson-$revision"
if (-not (Test-Path -LiteralPath (Join-Path $source 'include/rapidjson/reader.h'))) {
    & tar -xf $archive -C $cache
    if ($LASTEXITCODE) { throw 'RapidJSON extraction failed' }
}
$licenses = Join-Path $repo 'game/platform/windows/bin/licenses'
New-Item -ItemType Directory -Force $licenses | Out-Null
Copy-Item -LiteralPath (Join-Path $source 'license.txt') -Destination (Join-Path $licenses 'RapidJSON-MIT.txt') -Force
[PSCustomObject]@{include=(Join-Path $source 'include');rapidjson=$revision;source_sha256=$sha}
