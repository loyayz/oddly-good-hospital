#requires -Version 7.0
param([string]$Godot = 'C:\programs\godot\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Godot)) {
    $assetGodotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -eq $assetGodotCommand) { throw '请用 Godot 4.7.2 打开本目录的 project.godot，或通过 -Godot 指定程序路径。' }
    $Godot = $assetGodotCommand.Source
}
& $Godot --headless --editor --import --path $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw '素材导入未完成，请检查 Godot 导入日志。' }
& $Godot --path $PSScriptRoot
