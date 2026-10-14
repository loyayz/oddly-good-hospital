uniform int value_kind = 0;
uniform int component_axis = 0;
uniform int columns = 128;
uniform int rows_per_actor = 16;
uniform vec2 image_size = vec2(128.0, 32.0);
varying flat float measured_value;

float probe_value(vec3 position, vec3 normal, vec3 tangent, int row, int instance_id, vec2 grid) {
	if (value_kind == 0) {
		return (position[component_axis] + 4.0) / 8.0;
	} else if (value_kind == 1) {
		return (normalize(normal)[component_axis] + 1.0) / 2.0;
	} else if (value_kind == 2) {
		return (normalize(tangent)[component_axis] + 1.0) / 2.0;
	} else if (value_kind == 3) {
		return float(row) / 63.0;
	} else if (value_kind == 4) {
		return mod(grid.x + grid.y * float(columns), 256.0) / 255.0;
	}
	return float(instance_id) / 63.0;
}

vec4 probe_grid(vec2 grid, int row) {
	ivec2 pixel = ivec2(grid) + ivec2(0, row * rows_per_actor);
	vec2 ndc = (vec2(pixel) + vec2(0.5)) / image_size * 2.0 - 1.0;
	return vec4(ndc.x, -ndc.y, 0.0, 1.0);
}

void fragment() {
	uint code = uint(min(16777215.0, floor(clamp(measured_value, 0.0, 1.0) * 16777215.0 + 0.5)));
	vec3 bytes = vec3(float((code >> uint(16)) & uint(255)), float((code >> uint(8)) & uint(255)), float(code & uint(255)));
	if (value_kind == 4) {
		bytes = vec3(round(measured_value * 255.0));
	}
	// Invert Godot 4.7 GLES's measured sRGB output path for diagnostic bytes.
	vec3 target = pow((bytes / 255.0 + 0.055) / 1.055, vec3(2.4));
	vec3 lower = vec3(0.0);
	vec3 upper = vec3(1.0);
	for (int i = 0; i < 24; i++) {
		vec3 middle = (lower + upper) * 0.5;
		vec3 decoded = middle * (middle * (middle * 0.305306011 + 0.682171111) + 0.012522878);
		vec3 below = vec3(lessThan(decoded, target));
		lower = mix(lower, middle, below);
		upper = mix(middle, upper, below);
	}
	ALBEDO = (lower + upper) * 0.5;
	ALPHA = 1.0;
}
