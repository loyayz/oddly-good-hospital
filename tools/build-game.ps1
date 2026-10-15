#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Godot = 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe',
    [string]$ProjectPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')),
    [string]$Output = ''
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$productOutput = if ([string]::IsNullOrWhiteSpace($Output)) {
    Join-Path $project '.build/stage28/product'
} else {
    [IO.Path]::GetFullPath($Output)
}
$logs = Join-Path (Split-Path -Parent $productOutput) ((Split-Path -Leaf $productOutput) + '-logs')
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw "Godot not found: $Godot" }
if (-not (Test-Path -LiteralPath (Join-Path $project 'project.godot') -PathType Leaf)) { throw "Godot project not found: $project" }
New-Item -ItemType Directory -Force -Path $productOutput,$logs | Out-Null

function Invoke-BuildCommand {
    param([scriptblock]$Command, [string]$LogPath, [string]$Description)
    & $Command *> $LogPath
    $commandExit = $LASTEXITCODE
    if ($commandExit -ne 0 -or (Select-String -LiteralPath $LogPath -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) {
        throw "$Description failed (exit $commandExit): $LogPath"
    }
}

function Read-Git {
    param([string[]]$GitArguments)
    $value = & git -c core.quotePath=false -C $project @GitArguments
    if ($LASTEXITCODE -ne 0) { throw "Cannot identify build source: git $($GitArguments -join ' ')" }
    return ($value -join "`n").Trim()
}

function Read-SourceIdentity {
    $head = Read-Git -GitArguments @('rev-parse','HEAD')
    $headTree = Read-Git -GitArguments @('rev-parse','HEAD^{tree}')
    $stagedTree = Read-Git -GitArguments @('write-tree')
    $unstagedText = Read-Git -GitArguments @('diff','--name-only')
    $untrackedText = Read-Git -GitArguments @('ls-files','--others','--exclude-standard')
    $unstaged = @($unstagedText -split "`n" | Where-Object { $_.Length -gt 0 })
    $untracked = @($untrackedText -split "`n" | Where-Object { $_.Length -gt 0 })
    $workingFiles = foreach ($relativePath in @($unstaged + $untracked | Sort-Object -Unique)) {
        $path = Join-Path $project $relativePath
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            [ordered]@{path=$relativePath;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
        } else {
            [ordered]@{path=$relativePath;deleted=$true}
        }
    }
    $kind = if ($workingFiles.Count -gt 0) { 'working_tree' } elseif ($stagedTree -eq $headTree) { 'HEAD' } else { 'staged_tree' }
    return [ordered]@{
        kind=$kind
        head=$head
        head_tree=$headTree
        staged_tree=$stagedTree
        tracked_working_tree_matches_index=($unstaged.Count -eq 0)
        unstaged_paths=@($unstaged)
        untracked_paths=@($untracked)
        working_files=@($workingFiles)
    }
}

Invoke-BuildCommand -Description 'Published content check' -LogPath (Join-Path $logs 'content-check.log') -Command {
    & python (Join-Path $project 'tools/compile-content.py') --check
}
Invoke-BuildCommand -Description 'Godot project import' -LogPath (Join-Path $logs 'import.log') -Command {
    & $Godot --headless --path $project --editor --import --quit
}
$source = Read-SourceIdentity
Invoke-BuildCommand -Description 'Windows release export' -LogPath (Join-Path $logs 'export.log') -Command {
    & $Godot --headless --path $project --export-release 'Windows Stage01' (Join-Path $productOutput 'oddly-good-hospital.exe')
}

# Query the loaded project's settings instead of maintaining another version value.
$settingsScript = Join-Path $logs 'read-build-settings.gd'
@'
extends SceneTree
func _initialize() -> void:
    print("BUILD_SETTINGS=" + JSON.stringify({"version":ProjectSettings.get_setting("application/config/version", ""), "engine":Engine.get_version_info().string}))
    quit(0)
'@ | Set-Content -LiteralPath $settingsScript -Encoding utf8NoBOM
$settingsLog = Join-Path $logs 'settings.log'
Invoke-BuildCommand -Description 'Project settings identity' -LogPath $settingsLog -Command {
    & $Godot --headless --path $project --script $settingsScript
}
$settingsLine = @(Get-Content -LiteralPath $settingsLog | Where-Object { $_.StartsWith('BUILD_SETTINGS=') })
if ($settingsLine.Count -ne 1) { throw "Missing project settings identity: $settingsLog" }
$settings = $settingsLine[0].Substring('BUILD_SETTINGS='.Length) | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($settings.version)) { throw 'ProjectSettings application/config/version is empty.' }
$sourceAfterExport = Read-SourceIdentity
if (($source | ConvertTo-Json -Depth 8 -Compress) -ne ($sourceAfterExport | ConvertTo-Json -Depth 8 -Compress)) {
    throw "Build source changed during import/export; source identity cannot be sealed: $logs"
}

$licenses = Join-Path $productOutput 'licenses'
New-Item -ItemType Directory -Force -Path $licenses | Out-Null
Copy-Item -LiteralPath (Join-Path $project 'assets/licenses/Godot-MIT.txt'),(Join-Path $project 'assets/fonts/OFL.txt'),(Join-Path $project 'tools/windows/THIRD-PARTY-NOTICES.txt') -Destination $licenses -Force
$files = foreach ($name in @('oddly-good-hospital.exe','oddly-good-hospital.pck','oddly_good_platform.windows.x86_64.dll')) {
    $path = Join-Path $productOutput $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release artifact missing: $path" }
    [ordered]@{path=$name;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
}
[ordered]@{
    product_id='oddly-good-hospital'
    version=$settings.version
    version_source='ProjectSettings:application/config/version'
    engine=$settings.engine
    source=$source
    files=@($files)
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $productOutput 'build-identity.json') -Encoding utf8NoBOM
Write-Output "PRODUCT_RELEASE=$productOutput"
Write-Output "BUILD_LOGS=$logs"
