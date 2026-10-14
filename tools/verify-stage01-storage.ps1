#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GodotPath = 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe',
    [string]$ProjectPath = '.cache/validation/runtime-r5',
    [ValidateSet('database','journal','before_commit','after_commit')][string[]]$Stages = @('database','journal','before_commit','after_commit')
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$project = [IO.Path]::GetFullPath((Join-Path $repo $ProjectPath))
$output = Join-Path $repo ('.cache/validation/Stage01 验收 storage/' + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $output | Out-Null
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public struct Stage01SqliteOverlapped {
    public UIntPtr Internal, InternalHigh;
    public uint Offset, OffsetHigh;
    public IntPtr Event;
}
public static class Stage01SqliteLock {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool LockFileEx(SafeFileHandle file, uint flags, uint reserved, uint low, uint high, ref Stage01SqliteOverlapped overlapped);
}
'@
function Start-Probe([string]$mode, [string]$stage, [string]$control, [string]$appData) {
    $info = [Diagnostics.ProcessStartInfo]::new($GodotPath)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.WorkingDirectory = $repo
    $info.Environment['APPDATA'] = $appData
    foreach ($arg in @('--headless','--path',$project,'--script','res://verify-stage01-storage.gd','--',"--mode=$mode","--stage=$stage","--control-dir=$control")) {
        $info.ArgumentList.Add($arg)
    }
    $process = [Diagnostics.Process]::Start($info)
    return @{ Process=$process; Stdout=$process.StandardOutput.ReadToEndAsync(); Stderr=$process.StandardError.ReadToEndAsync() }
}
function Await-File([string]$path, $process) {
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while (-not (Test-Path -LiteralPath $path)) {
        if ($process.HasExited) { throw "Probe ended before $path (exit $($process.ExitCode))" }
        if ([DateTime]::UtcNow -gt $deadline) { throw "Timeout waiting for $path" }
        Start-Sleep -Milliseconds 100
    }
}
function Save-ProcessOutput($run, [string]$prefix) {
    $run.Stdout.GetAwaiter().GetResult() | Set-Content -LiteralPath ($prefix+'.stdout.log') -Encoding utf8NoBOM
    $run.Stderr.GetAwaiter().GetResult() | Set-Content -LiteralPath ($prefix+'.stderr.log') -Encoding utf8NoBOM
}
$results = [Collections.Generic.List[object]]::new()
foreach ($stage in $Stages) {
    $control = Join-Path $output $stage
    $appData = Join-Path $control 'APPDATA'
    New-Item -ItemType Directory -Force -Path $control,$appData | Out-Null
    $run = Start-Probe 'fault' $stage $control $appData
    $lock = $null
    try {
        Await-File (Join-Path $control 'ready.json') $run.Process
        $ready = Get-Content -Raw -LiteralPath (Join-Path $control 'ready.json') | ConvertFrom-Json
        $competitor = Start-Probe 'busy' $stage $control $appData
        if (-not $competitor.Process.WaitForExit(30000)) { Stop-Process -Id $competitor.Process.Id -Force; throw 'Contention probe timeout' }
        Save-ProcessOutput $competitor (Join-Path $control 'contention')
        if ($competitor.Process.ExitCode -ne 0) { throw 'Concurrent process did not return the actual ownership conflict' }
        $databasePath = [IO.Path]::GetFullPath($ready.database_path)
        $actualUser = [IO.Path]::GetFullPath($ready.actual_user_directory)
        if (-not $actualUser.StartsWith([IO.Path]::GetFullPath($appData)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected user directory' }
        if (-not $databasePath.StartsWith($actualUser+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Database path escaped isolated user directory' }
        if ($stage -eq 'before_commit') {
            $lock = [IO.File]::Open($databasePath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
            $overlapped = [Stage01SqliteOverlapped]::new()
            $overlapped.Offset = 0x40000002 # SQLite Win32 SHARED_FIRST; reserve/intent bytes remain available.
            if (-not [Stage01SqliteLock]::LockFileEx($lock.SafeFileHandle,1,0,510,0,[ref]$overlapped)) {
                throw "Cannot acquire actual SQLite reader byte lock: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            }
        } elseif ($stage -in @('database','journal')) {
            $lockedPath = $databasePath + $(if ($stage -eq 'journal') { '-journal' } else { '' })
            $lock = [IO.File]::Open($lockedPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        }
        'GO' | Set-Content -LiteralPath (Join-Path $control 'GO') -Encoding ascii
        if ($stage -eq 'before_commit') {
            $journalPath = $databasePath + '-journal'
            Await-File $journalPath $run.Process
            $deadline = [DateTime]::UtcNow.AddSeconds(10)
            while ((Get-Item -LiteralPath $journalPath).Length -eq 0) {
                if ([DateTime]::UtcNow -gt $deadline -or $run.Process.HasExited) { throw 'No actual transaction journal write observed' }
                Start-Sleep -Milliseconds 5
            }
            $writer = [PSCustomObject]@{ ok=$false; error='Process terminated during an actual uncommitted SQLite transaction'; journal_bytes=(Get-Item -LiteralPath $journalPath).Length }
        } else {
            Await-File (Join-Path $control 'writer.json') $run.Process
            $writer = Get-Content -Raw -LiteralPath (Join-Path $control 'writer.json') | ConvertFrom-Json
            if ($stage -eq 'after_commit') {
                if (-not $writer.ok) { throw 'The post-commit crash case did not commit' }
            } elseif ($writer.ok) { throw "Boundary $stage unexpectedly committed despite real share lock" }
        }
        Stop-Process -Id $run.Process.Id -Force
        $run.Process.WaitForExit()
        Save-ProcessOutput $run (Join-Path $control 'interrupted')
    } finally {
        if ($null -ne $lock) { $lock.Dispose() }
        if (-not $run.Process.HasExited) { Stop-Process -Id $run.Process.Id -Force; $run.Process.WaitForExit() }
    }
    $recovery = Start-Probe 'recover' $stage $control $appData
    if (-not $recovery.Process.WaitForExit(60000)) { Stop-Process -Id $recovery.Process.Id -Force; throw 'Recovery timeout' }
    Save-ProcessOutput $recovery (Join-Path $control 'recovery')
    if ($recovery.Process.ExitCode -ne 0) { throw "Recovery $stage failed (exit $($recovery.Process.ExitCode))" }
    $result = Get-Content -Raw -LiteralPath (Join-Path $control 'recovery.json') | ConvertFrom-Json
    $result | Add-Member -NotePropertyName writer_error -NotePropertyValue $writer.error
    $result | Add-Member -NotePropertyName concurrent_process -NotePropertyValue (Get-Content -Raw -LiteralPath (Join-Path $control 'contention.json') | ConvertFrom-Json)
    $result | Add-Member -NotePropertyName intervention -NotePropertyValue 'Actual Windows sharing/SQLite reader byte locks; forced process termination and restart with the same profile'
    $results.Add($result)
}
$report = @{ ok=$true; engine=$GodotPath; project=$project; process_identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name; cases=$results; output_directory=$output }
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding utf8NoBOM
Write-Output "STORAGE_FAULTS_PASS=True; CASES=$($results.Count); REPORT=$(Join-Path $output 'result.json')"
