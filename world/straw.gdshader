shader_type spatial;
// Loose straw cards on the pile surface. One MultiMesh with identity transforms: each instance
// finds its own spot on a lattice around the camera focus, so the CPU does nothing per frame.
// Spots are hashed in world space, so straws stay put as the lattice follows the camera.

render_mode cull_disabled, specular_disabled;

uniform sampler2DArray heights : filter_nearest, repeat_disable;
uniform int grid_size = 1024;
uniform int tiles_per_side = 16;
uniform float cell_m = 0.125;
uniform float height_unit_m = 0.001;
uniform int side = 141;
uniform float spacing = 0.2;
uniform vec3 focus = vec3(0.0);
uniform float fade_radius = 13.0;
// Each card takes its colour from the pile's own straw texture, so loose straws match the pile.
uniform sampler2D straw_albedo : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 v_color;

float height_at(ivec2 cell) {
	cell = clamp(cell, ivec2(0), ivec2(grid_size - 1));
	ivec2 tile = cell / 64;
	ivec2 local = cell - tile * 64;
	vec2 rg = texelFetch(heights, ivec3(local, tile.y * tiles_per_side + tile.x), 0).rg;
	return (round(rg.r * 255.0) + round(rg.g * 255.0) * 256.0) * height_unit_m;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	int id = INSTANCE_ID;
	vec2 lattice = vec2(float(id % side), float(id / side)) - float(side) * 0.5;
	vec2 base = floor(focus.xz / spacing) * spacing + lattice * spacing;
	vec2 spot = base + (vec2(hash(base), hash(base + 17.17)) - 0.5) * spacing;
	float half_grid = float(grid_size) * 0.5;
	float h = height_at(ivec2(floor(spot / cell_m + half_grid)));
	float fade = 1.0 - smoothstep(fade_radius * 0.6, fade_radius, distance(spot, focus.xz));
	float scale = (h > 0.05) ? fade : 0.0;
	float yaw = hash(base + 3.1) * 6.2831;
	// Most straws lie on the pile; one in five sticks up out of it.
	float roll = hash(base + 7.3);
	float lean = roll < 0.08 ? roll * 6.0 : mix(1.25, 1.5, roll);
	float length_scale = mix(0.6, 1.3, hash(base + 5.7));
	vec3 local_v = VERTEX * vec3(1.0, length_scale, 1.0) * scale;
	// Lean the card, then spin it around the vertical.
	local_v = vec3(local_v.x, local_v.y * cos(lean), local_v.y * sin(lean));
	local_v = vec3(local_v.x * cos(yaw) - local_v.z * sin(yaw), local_v.y, local_v.x * sin(yaw) + local_v.z * cos(yaw));
	VERTEX = vec3(spot.x, h - 0.02, spot.y) + local_v;
	vec4 sample_color = textureLod(straw_albedo, vec2(hash(base + 11.9), hash(base + 13.3)), 0.0);
	// Alpha is strand height: a low sample is a gap between strands, not a straw colour.
	v_color = sample_color.a > 0.3 ? sample_color.rgb : vec3(0.72, 0.53, 0.23);
}

void fragment() {
	ALBEDO = v_color;
	// Lit like the surface beneath, on both faces (a back face would otherwise go black).
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 0.8;
}
