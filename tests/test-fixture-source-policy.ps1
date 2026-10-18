#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$tokens=$null; $parseErrors=$null
$tree=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'run-acceptance.ps1'),[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$sourcePolicy=$tree.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-FixtureSource'},$true)
if (-not $sourcePolicy) { throw 'Missing real fixture identity policy' }
. ([scriptblock]::Create($sourcePolicy.Extent.Text))
$cases=[ordered]@{
    'game/clinic/clinical_runtime.gd'=$true
    'game/clinic/clinical_runtime.gd.uid'=$false
    'game/sim/world_state.gd'=$true
    'game/persistence/snapshot_store.gd'=$true
    'game/platform/windows/platform_arrivals.cpp'=$true
    'game/content/schema100.json'=$true
    'content/core/manifest.json'=$true
    'content/core/assets/index.json'=$true
    'project.godot'=$true
    'game/view/hospital_view.gd'=$false
    'game/view/shaders/skinned_pose.gdshaderinc'=$false
    'game/ui/plans_panel.gd'=$false
    'game/app/game_session.gd'=$false
    'assets/models/body.glb'=$false
    'tests/acceptance/clinical.gd'=$false
    'docs/reports/example.md'=$false
}
foreach ($entry in $cases.GetEnumerator()) {
    if ((Test-FixtureSource $entry.Key) -ne $entry.Value) { throw "Incorrect generation dependency scope: $($entry.Key)" }
    if ((Test-FixtureSource ($entry.Key.Replace('/','\'))) -ne $entry.Value) { throw 'Windows path changed the source scope' }
}
[ordered]@{checks=$cases.Count*2; passed=$true; game_started=$false} | ConvertTo-Json
