#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(4,24)][int]$Stage,
    [Parameter(Mandatory)][string[]]$Scripts,
    [string[]]$ScriptArguments = @()
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$godot = 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godot)) { throw "Godot not found: $godot" }
$preparation = & (Join-Path $PSScriptRoot 'prepare-functional-validation.ps1') -Stage $Stage
$projectLine = $preparation | Where-Object { $_ -like 'VALIDATION_PROJECT=*' } | Select-Object -Last 1
if (-not $projectLine) { throw 'Validation project was not prepared.' }
$target = $projectLine.Substring('VALIDATION_PROJECT='.Length)
New-Item -ItemType Directory -Path (Join-Path $target '.cache/validation') -Force | Out-Null
$importLog = Join-Path $target 'import.log'
& $godot --headless --path $target --import *> $importLog
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR:|Parse Error:|ERROR:' -Quiet)) {
    Get-Content -LiteralPath $importLog -Tail 45
    throw "Stage $Stage import failed: $importLog"
}
foreach ($script in $Scripts) {
    $log = Join-Path $target (([IO.Path]::GetFileNameWithoutExtension($script)) + '.log')
    $arguments = @('--headless','--path',$target,'--script',('res://' + $script.Replace('\','/')))
    if ($ScriptArguments.Count -gt 0) { $arguments += @('--') + $ScriptArguments }
    & $godot @arguments *> $log
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR:|Parse Error:|ERROR:' -Quiet)) {
        Get-Content -LiteralPath $log -Tail 45
        throw "Stage $Stage rule check failed: $log"
    }
    Get-Content -LiteralPath $log -Tail 1
}
Write-Output "FUNCTIONAL_STAGE_PASS=$Stage"
Write-Output "VALIDATION_PROJECT=$target"
