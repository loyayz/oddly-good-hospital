param([string]$OutputPath, [switch]$Check)
$ErrorActionPreference = 'Stop'
$python = if ($env:PYTHON) { $env:PYTHON } else { 'python' }
$arguments = @('-B', '-X', 'utf8', (Join-Path $PSScriptRoot 'export-design.py'))
if ($OutputPath) { $arguments += $OutputPath }
if ($Check) { $arguments += '--check' }
try { & $python @arguments }
catch [System.Management.Automation.CommandNotFoundException] {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 127
}
exit $LASTEXITCODE
