uniform sampler2D bone_rows : filter_nearest, repeat_disable;

mat4 pose_matrix(uint bone_index, int row) {
	int column = int(bone_index) * 3;
	vec4 x = texelFetch(bone_rows, ivec2(column, row), 0);
	vec4 y = texelFetch(bone_rows, ivec2(column + 1, row), 0);
	vec4 z = texelFetch(bone_rows, ivec2(column + 2, row), 0);
	return transpose(mat4(x, y, z, vec4(0.0, 0.0, 0.0, 1.0)));
}

mat4 skin_pose(uvec4 indices, vec4 weights, int row) {
	return pose_matrix(indices.x, row) * weights.x
		+ pose_matrix(indices.y, row) * weights.y
		+ pose_matrix(indices.z, row) * weights.z
		+ pose_matrix(indices.w, row) * weights.w;
}
