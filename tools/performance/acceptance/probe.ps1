#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Product,
    [Parameter(Mandatory)][string]$Output
)
$ErrorActionPreference='Stop'
$source=(Resolve-Path -LiteralPath $Product).Path
$destination=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $destination){throw 'Probe output already exists.'}
if($destination.StartsWith($source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Probe must not write inside the original product.'}
New-Item -ItemType Directory -Path $destination|Out-Null
$runtime=Join-Path $destination 'product'
Copy-Item -LiteralPath $source -Destination $runtime -Recurse
$profile='OddlyGoodHospital Formal Probe '+[Guid]::NewGuid().ToString('N')
$scene=ConvertTo-Json -InputObject ((Join-Path $PSScriptRoot 'probe.tscn').Replace('\','/')) -Compress
$profileLiteral=ConvertTo-Json -InputObject $profile -Compress
[IO.File]::WriteAllText((Join-Path $runtime 'override.cfg'),"[application]`nrun/main_scene=$scene`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=$profileLiteral`n",[Text.UTF8Encoding]::new($false))
$arguments=@('--',('--output='+(Join-Path $destination 'probe.json')))
$info=[Diagnostics.ProcessStartInfo]::new((Join-Path $runtime 'oddly-good-hospital.exe'))
$info.WorkingDirectory=$runtime;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
foreach($argument in $arguments){$info.ArgumentList.Add($argument)}
$process=[Diagnostics.Process]::Start($info)
$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
$finished=$process.WaitForExit(30000)
if(-not $finished){$process.Kill();$process.WaitForExit()}
[IO.File]::WriteAllText((Join-Path $destination 'stdout.log'),$stdout.GetAwaiter().GetResult())
[IO.File]::WriteAllText((Join-Path $destination 'stderr.log'),$stderr.GetAwaiter().GetResult())
$files=@(foreach($file in Get-ChildItem -LiteralPath $runtime -File){@{path=$file.Name;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()}})
@{pid=$process.Id;exit=$process.ExitCode;timeout=(-not $finished);arguments=$arguments;profile=$profile;source=$source;files=$files}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $destination 'process.json') -Encoding utf8NoBOM
if(-not $finished -or $process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $destination 'probe.json'))){throw 'Actual Release probe did not complete successfully.'}
$result=Get-Content -LiteralPath (Join-Path $destination 'probe.json') -Raw|ConvertFrom-Json
if(-not $result.valid -or (Select-String -LiteralPath (Join-Path $destination 'stderr.log') -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)){throw 'Actual Release probe failed validation.'}
Write-Output ('RELEASE_PROBE='+$destination)
