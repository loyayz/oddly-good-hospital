#requires -Version 7.0
[CmdletBinding()]
param([string]$Godot = 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = Join-Path $repo '.build/stage03/product'
$logs = Join-Path $repo '.cache/validation/stage03-build'
if (-not (Test-Path -LiteralPath $Godot)) { throw "Godot not found: $Godot" }
New-Item -ItemType Directory -Force -Path $output,$logs | Out-Null
& $Godot --headless --path $repo --import *> (Join-Path $logs 'import.log')
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath (Join-Path $logs 'import.log') -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) { throw "Godot import failed: $logs/import.log" }
& $Godot --headless --path $repo --export-release 'Windows Stage01' (Join-Path $output 'oddly-good-hospital.exe') *> (Join-Path $logs 'export.log')
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath (Join-Path $logs 'export.log') -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) { throw "Release export failed: $logs/export.log" }
$licenses = Join-Path $output 'licenses'
New-Item -ItemType Directory -Force -Path $licenses | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'assets/licenses/Godot-MIT.txt'),(Join-Path $repo 'assets/fonts/OFL.txt'),(Join-Path $PSScriptRoot 'windows/THIRD-PARTY-NOTICES.txt') -Destination $licenses -Force
$files = foreach ($name in @('oddly-good-hospital.exe','oddly-good-hospital.pck','oddly_good_platform.windows.x86_64.dll')) {
    $file = Join-Path $output $name
    [ordered]@{path=$name;bytes=(Get-Item -LiteralPath $file).Length;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()}
}
[ordered]@{version='0.3.0-stage03';engine=(& $Godot --version);files=@($files)} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'build-identity.json') -Encoding utf8NoBOM
Write-Output "PRODUCT_RELEASE=$output"
