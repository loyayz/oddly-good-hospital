shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled;

#include "res://game/view/shaders/skinned_pose.gdshaderinc"
#include "res://game/view/shaders/skin_readback_output.gdshaderinc"

void vertex() {
	int row = int(round(INSTANCE_CUSTOM.x));
	mat4 skin = skin_pose(BONE_INDICES, BONE_WEIGHTS, row);
	vec2 grid = vec2(float(VERTEX_ID % columns), float(VERTEX_ID / columns));
	measured_value = probe_value((skin * vec4(VERTEX, 1.0)).xyz, mat3(skin) * NORMAL, mat3(skin) * TANGENT, row, INSTANCE_ID, grid);
	POSITION = probe_grid(grid, row);
	POINT_SIZE = 1.0;
}
