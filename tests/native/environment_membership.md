# Environment footprint membership isolation

Run `python3 -B tests/native/environment_membership.py --output <new-directory>`.

The tool extracts the complete production `_facility_in_coverage()` and `_cell_key()` functions unchanged from the selected baseline and current source. Only `WorldState` identity and the `facility_layout` input are adapted. Godot executes the actual loops, integer conversions, key construction and Dictionary membership checks.

Independent expected results cover zero footprints, nine footprint sizes, positive/negative/fractional starting coordinates, false-valued membership entries, outside/edge cells and unchanged facility facts (5,490 cases). The layout deliberately differs from the facility's raw footprint so the test cannot silently substitute the wrong geometry source.

For 1×1, 3×3 and 8×8 footprints, twelve A-B-B-A windows each execute 12,000 full membership calls after equal warm-up. All timing windows and source/tool identities are preserved. This measures key-construction cost inside the helper, not complete environmental observation, native coverage generation, actual footprint distribution or whole-step performance.

The rule and integration boundary remains the original OPS-11 environment coverage behavior: every tile of the actual adapted facility footprint is checked, in the same order, with early success unchanged. Full OPS-11 is not run by this isolated tool.
