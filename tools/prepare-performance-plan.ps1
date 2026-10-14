#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$balance = Get-Content -LiteralPath (Join-Path $repo 'docs/data/balance.json') -Raw | ConvertFrom-Json
$target = $balance.performance_targets
$groups = foreach ($window in @($target.display.window_pixels,$target.hardware_reference.reported_gpu_mode)) {
    foreach ($count in @(160,320,640)) {
        foreach ($sceneScale in $target.display.scene_scale_options_bp) {
            foreach ($ui in $target.display_workload_samples.ui_scale_percent) {
                foreach ($speed in $target.capture.speeds) {
                    [ordered]@{actors=$count;window=@($window);scene_scale_bp=$sceneScale;ui_percent=$ui;speed=$speed;warmup_real_seconds=$target.capture.warmup_real_seconds;sample_real_seconds=$target.capture.sample_real_seconds;measurement_status='not_measured'}
                }
            }
        }
    }
}
$output = Join-Path $repo '.cache/validation/stage02'
New-Item -ItemType Directory -Force -Path $output | Out-Null
[ordered]@{schema_version=1;stage02_performance_status='skipped';display_groups=@($groups);spatial_samples=$target.spatial_samples;large_world_samples=$target.large_world_samples;metrics=$target.metrics;cost_coverage=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'benchmarks/cost-coverage.json') -Raw | ConvertFrom-Json)} |
    ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $output 'baseline-plan.json') -Encoding utf8NoBOM
Write-Output "PERFORMANCE_PLAN=$(Join-Path $output 'baseline-plan.json') GROUPS=$(@($groups).Count) MEASUREMENTS=0"
