#requires -Version 7.0
$ErrorActionPreference = 'Stop'
# Load the actual collector function without launching a capture or product.
$tokens=$null; $parseErrors=$null
$tree=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'capture.ps1'),[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$function=$tree.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Count-WindowFrames'},$true)
if (-not $function) { throw 'Missing real collector count function' }
. ([scriptblock]::Create($function.Extent.Text))
$frames=[Collections.Generic.List[double]]::new(); $state=@{}; $checks=0
$random=[Random]::new(181018)
foreach ($boundary in @(0L,1000L,1000L,-5L,999999L)) {
    for ($batch=0; $batch -lt 20; $batch++) {
        for ($n=0; $n -lt 13; $n++) { $frames.Add($random.Next(-20,2000)+0.5) }
        $expected=0L
        foreach ($point in $frames) { if ($point -ge $boundary) { $expected++ } }
        $actual=Count-WindowFrames $frames $boundary $state
        if ($actual -ne $expected -or $state.cursor -ne $frames.Count) { throw 'Append cursor changed complete out-of-order population' }
        # Empty polls do not count any observation again.
        if ((Count-WindowFrames $frames $boundary $state) -ne $expected) { throw 'Duplicate count on an empty poll' }
        $checks+=2
    }
}
$frames.Add(999999); $expected=1L
if ((Count-WindowFrames $frames 999999 $state) -ne $expected) { throw 'Inclusive boundary frame was lost' }
$checks++
[ordered]@{checks=$checks; passed=$true; original_observations=$frames.Count; capture_started=$false} | ConvertTo-Json
