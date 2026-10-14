#include "res://game/view/shaders/skinned_pose.gdshaderinc"

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float material_roughness : hint_range(0.0, 1.0) = 1.0;
uniform float material_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float material_specular : hint_range(0.0, 1.0) = 0.5;

void vertex() {
	int row = int(round(INSTANCE_CUSTOM.x));
	mat4 skin = skin_pose(BONE_INDICES, BONE_WEIGHTS, row);
	VERTEX = (skin * vec4(VERTEX, 1.0)).xyz;
	NORMAL = mat3(skin) * NORMAL;
	TANGENT = mat3(skin) * TANGENT;
	BINORMAL = mat3(skin) * BINORMAL;
}

void fragment() {
	ALBEDO = albedo_color.rgb * (use_vertex_color ? COLOR.rgb : vec3(1.0));
	ROUGHNESS = material_roughness;
	METALLIC = material_metallic;
	SPECULAR = material_specular;
}
