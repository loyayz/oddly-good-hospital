#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$output = Join-Path $repo ('.cache/validation/Stage01 验收 UI/' + [Guid]::NewGuid().ToString())
$install = Join-Path $output '中文 安装程序'
$appData = Join-Path $output 'APPDATA'
$registration = 'HKCU:/Software/oddly-good-hospital'
$uninstallRegistration = 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/oddly-good-hospital'
$shortcuts = Join-Path ([Environment]::GetFolderPath('Programs')) '怪好的医院'
if ((Test-Path -LiteralPath $registration) -or (Test-Path -LiteralPath $uninstallRegistration) -or (Test-Path -LiteralPath $shortcuts)) {
    throw 'An existing hospital installation must be preserved; this probe cannot claim its registration.'
}
New-Item -ItemType Directory -Force -Path $output,$appData | Out-Null
function Run-Installer([string]$file, [string]$arguments, [string]$workingDirectory) {
    $info = [Diagnostics.ProcessStartInfo]::new($file)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.WorkingDirectory = $workingDirectory
    # NSIS /D must be the last, unquoted argument. No shell evaluates this string.
    $info.Arguments = $arguments
    $process = [Diagnostics.Process]::Start($info)
    if (-not $process.WaitForExit(60000)) { Stop-Process -Id $process.Id -Force; throw 'Installer timeout' }
    return $process.ExitCode
}
$setup = Join-Path $repo '.build/installer/oddly-good-hospital-stage01-setup.exe'
$identity = Get-Content -Raw -LiteralPath (Join-Path $repo '.build/windows/build-identity.json') | ConvertFrom-Json
$report = [ordered]@{ output_directory=$output; build_identity=$identity; setup_sha256=(Get-FileHash -LiteralPath $setup).Hash.ToLowerInvariant() }
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
$report.elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$report.install_exit = Run-Installer $setup ('/S /D=' + $install) $output
if ($report.install_exit -ne 0) { throw 'Trial installation failed' }
$report.files_match = $true
foreach ($file in $identity.files) {
    if ((Get-FileHash -LiteralPath (Join-Path $install $file.path)).Hash.ToLowerInvariant() -ne $file.sha256) { $report.files_match = $false }
}
$report.repeat_install_exit = Run-Installer $setup ('/S /D=' + $install) $output
if (-not $report.files_match -or $report.repeat_install_exit -ne 2) { throw 'Installed identity or existing-installation protection failed' }
$uiInfo = [Diagnostics.ProcessStartInfo]::new((Join-Path $install 'oddly-good-hospital.exe'))
$uiInfo.UseShellExecute = $false
$uiInfo.CreateNoWindow = $true
$uiInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
$uiInfo.WorkingDirectory = $install
$uiInfo.RedirectStandardOutput = $true
$uiInfo.RedirectStandardError = $true
$uiInfo.Environment['APPDATA'] = $appData
$uiInfo.Environment['PATH'] = 'C:\Windows\System32;C:\Windows'
foreach ($argument in @('--position','-10000,-10000','--write-movie',(Join-Path $output 'frame.png'),'--quit-after','12','--fixed-fps','10')) {
    $uiInfo.ArgumentList.Add($argument)
}
$ui = [Diagnostics.Process]::Start($uiInfo)
$stdout = $ui.StandardOutput.ReadToEndAsync()
$stderr = $ui.StandardError.ReadToEndAsync()
$tcpObserved = 0
$udpObserved = 0
$deadline = [DateTime]::UtcNow.AddSeconds(60)
while (-not $ui.HasExited) {
    $tcpObserved += @(Get-NetTCPConnection -OwningProcess $ui.Id -ErrorAction SilentlyContinue).Count
    $udpObserved += @(Get-NetUDPEndpoint -OwningProcess $ui.Id -ErrorAction SilentlyContinue).Count
    if ([DateTime]::UtcNow -gt $deadline) { Stop-Process -Id $ui.Id -Force; $ui.WaitForExit(); throw 'Standalone UI probe timeout' }
    Start-Sleep -Milliseconds 100
}
$stdout.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $output 'standalone.stdout.log') -Encoding utf8NoBOM
$stderr.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $output 'standalone.stderr.log') -Encoding utf8NoBOM
$report.ui_exit = $ui.ExitCode
$report.tcp_endpoints_observed = $tcpObserved
$report.udp_endpoints_observed = $udpObserved
$report.captures = @(Get-ChildItem -LiteralPath $output -Filter '*.png' -File | Select-Object -ExpandProperty FullName)
$userRoot = Join-Path $appData 'oddly-good-hospital'
$userFiles = @()
if (Test-Path -LiteralPath $userRoot) { $userFiles = @(Get-ChildItem -LiteralPath $userRoot -File -Recurse | ForEach-Object { @{ path=$_.FullName; hash=(Get-FileHash -LiteralPath $_.FullName).Hash } }) }
$report.user_file_count = $userFiles.Count
$extra = Join-Path $install '保留的额外文件.txt'
'Installer probe sentinel' | Set-Content -LiteralPath $extra -Encoding utf8NoBOM
New-ItemProperty -LiteralPath $registration -Name 'stage01_probe_extra' -Value 'retain' -PropertyType String | Out-Null
$report.uninstall_exit = Run-Installer (Join-Path $install 'Uninstall.exe') '/S' $output
# NSIS starts its temporary uninstaller asynchronously. Observe actual completion.
$uninstallDeadline = [DateTime]::UtcNow.AddSeconds(30)
while ((Test-Path -LiteralPath (Join-Path $install 'oddly-good-hospital.exe')) -or (Test-Path -LiteralPath $uninstallRegistration)) {
    if ([DateTime]::UtcNow -gt $uninstallDeadline) { throw 'Actual uninstall did not finish' }
    Start-Sleep -Milliseconds 100
}
$report.user_files_retained = $true
foreach ($file in $userFiles) {
    if (-not (Test-Path -LiteralPath $file.path) -or (Get-FileHash -LiteralPath $file.path).Hash -ne $file.hash) { $report.user_files_retained = $false }
}
$report.extra_file_retained = Test-Path -LiteralPath $extra
$report.extra_registration_retained = (Get-ItemProperty -LiteralPath $registration).stage01_probe_extra -eq 'retain'
$report.known_program_files_removed = $true
foreach ($file in $identity.files) { if (Test-Path -LiteralPath (Join-Path $install $file.path)) { $report.known_program_files_removed = $false } }
$report.shortcut_registration_removed = -not (Test-Path -LiteralPath $shortcuts) -and -not (Test-Path -LiteralPath $uninstallRegistration)
# This key did not exist before the probe. Remove only the probe value and its empty key.
Remove-ItemProperty -LiteralPath $registration -Name 'stage01_probe_extra'
if (@((Get-Item -LiteralPath $registration).GetValueNames()).Count -eq 0 -and @((Get-Item -LiteralPath $registration).GetSubKeyNames()).Count -eq 0) { Remove-Item -LiteralPath $registration }
$report.ok = -not $report.elevated -and $report.ui_exit -eq 0 -and $report.captures.Count -eq 12 -and $report.user_file_count -gt 0 -and $report.uninstall_exit -eq 0 -and $report.user_files_retained -and $report.extra_file_retained -and $report.extra_registration_retained -and $report.known_program_files_removed -and $report.shortcut_registration_removed
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding utf8NoBOM
Write-Output "STANDALONE_PACKAGE_PASS=$($report.ok); REPORT=$(Join-Path $output 'result.json')"
if (-not $report.ok) { exit 1 }
