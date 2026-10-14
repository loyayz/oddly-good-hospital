shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled;

#include "res://game/view/shaders/skin_readback_output.gdshaderinc"

uniform int reference_row = 0;

void vertex() {
	// The engine's actual Skin/Skeleton GPU pass already deformed these inputs.
	// This shader contains no palette or bone-deformation implementation.
	vec2 grid = vec2(float(VERTEX_ID % columns), float(VERTEX_ID / columns));
	measured_value = probe_value(VERTEX, NORMAL, TANGENT, reference_row, 0, grid);
	POSITION = probe_grid(grid, reference_row);
	POINT_SIZE = 1.0;
}
