shader_type spatial;
// The pile: grid meshes displaced by the sim's heights. Heights live in a texture array of
// 64×64 RG8 tiles (R = low byte, G = high byte of the 16-bit height), read exactly with texelFetch.
// Two meshes share this shader: the coarse pile (one vertex per `stride` cells) and a fine patch
// (one vertex per cell) that follows the camera so rake furrows show up close. The coarse mesh
// sinks under the patch; the patch's edge vertices follow the coarse edge so there are no cracks.
// Hay colours live here and in the straw textures, not in the UI tokens (DESIGN.md).

render_mode cull_back;

uniform sampler2DArray heights : filter_nearest, repeat_disable;
uniform int grid_size = 1024;
uniform int tiles_per_side = 16;
uniform int stride = 4;
uniform float cell_m = 0.125;
uniform float height_unit_m = 0.001;

// Fine patch: cells [fine_min, fine_min + fine_cells]; `is_fine` marks the patch mesh itself.
uniform bool is_fine = false;
uniform ivec2 fine_min = ivec2(0);
uniform int fine_cells = 0;

uniform sampler2D straw_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D straw_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float straw_scale = 0.55; // texture repeats per metre
uniform vec3 ground_color : source_color = vec3(0.231, 0.227, 0.2);

varying float v_height;
varying float v_occlusion;
varying vec2 v_world_xz;
varying vec3 v_world_normal;

float height_at(ivec2 cell) {
	cell = clamp(cell, ivec2(0), ivec2(grid_size - 1));
	ivec2 tile = cell / 64;
	ivec2 local = cell - tile * 64;
	vec2 rg = texelFetch(heights, ivec3(local, tile.y * tiles_per_side + tile.x), 0).rg;
	return (round(rg.r * 255.0) + round(rg.g * 255.0) * 256.0) * height_unit_m;
}

// Height along a coarse edge: linear between the stride-aligned cells, as the coarse mesh draws it.
float coarse_edge_height(ivec2 cell, bool along_x) {
	int coord = along_x ? cell.x : cell.y;
	int lo = (coord / stride) * stride;
	float f = float(coord - lo) / float(stride);
	ivec2 a = along_x ? ivec2(lo, cell.y) : ivec2(cell.x, lo);
	ivec2 b = along_x ? ivec2(lo + stride, cell.y) : ivec2(cell.x, lo + stride);
	return mix(height_at(a), height_at(b), f);
}

void vertex() {
	float half_grid = float(grid_size) * 0.5;
	vec2 world_xz = VERTEX.xz;
	if (is_fine) {
		world_xz += (vec2(fine_min) - half_grid) * cell_m + float(fine_cells) * cell_m * 0.5;
	}
	// Vertices sit on cell corners; +0.5 keeps float error from flooring into the neighbour.
	ivec2 cell = ivec2(floor(world_xz / cell_m + half_grid + 0.5));
	int step_cells = is_fine ? 1 : stride;
	float h = height_at(cell);
	float left = height_at(cell - ivec2(step_cells, 0));
	float right = height_at(cell + ivec2(step_cells, 0));
	float back = height_at(cell - ivec2(0, step_cells));
	float front = height_at(cell + ivec2(0, step_cells));
	ivec2 rel = cell - fine_min;
	bool inside = rel.x > 0 && rel.y > 0 && rel.x < fine_cells && rel.y < fine_cells;
	if (is_fine) {
		// Stitch: edge vertices take the coarse mesh's height along that edge.
		if (rel.y == 0 || rel.y == fine_cells) {
			h = coarse_edge_height(cell, true);
		} else if (rel.x == 0 || rel.x == fine_cells) {
			h = coarse_edge_height(cell, false);
		}
	} else if (fine_cells > 0 && inside) {
		h -= 4.0; // hidden under the fine patch
	}
	VERTEX = vec3(world_xz.x, h, world_xz.y);
	NORMAL = normalize(vec3(left - right, 2.0 * float(step_cells) * cell_m, back - front));
	// Furrows and dips are darker: how far this cell sits below its neighbours.
	float concavity = (left + right + back + front) * 0.25 - h;
	v_occlusion = clamp(1.0 - concavity * (is_fine ? 5.0 : 0.6), 0.65, 1.0);
	// The foot of the pile and anything near the ground sits in its own shadow.
	v_occlusion *= mix(0.7, 1.0, smoothstep(0.0, 3.0, h));
	v_height = h;
	v_world_xz = world_xz;
	v_world_normal = NORMAL;
}

void fragment() {
	// Two samples at different scales and angles hide the tiling.
	vec2 uv_a = v_world_xz * straw_scale;
	vec2 uv_b = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * v_world_xz * (straw_scale * 0.37) + vec2(0.31, 0.77);
	vec4 a = texture(straw_albedo, uv_a);
	vec4 b = texture(straw_albedo, uv_b);
	float pick = smoothstep(0.35, 0.65, texture(straw_albedo, v_world_xz * 0.021).a);
	vec4 straw = mix(a, b, pick * 0.5);
	vec3 n = mix(texture(straw_normal, uv_a).rgb, texture(straw_normal, uv_b).rgb, pick * 0.5);
	// Steep faces (trench ends, cut walls): a top-down projection smears into streaks there,
	// so blend in a side projection. Sampled outside any branch: implicit-LOD texture reads in
	// per-pixel control flow are undefined in GLSL ES and blanked the frame on the emulator.
	vec3 wn = normalize(v_world_normal);
	float steep = smoothstep(0.55, 0.8, 1.0 - wn.y);
	vec2 side_uv = mix(vec2(v_world_xz.x, v_height), vec2(v_world_xz.y, v_height), step(abs(wn.z), abs(wn.x))) * straw_scale;
	vec4 side = texture(straw_albedo, side_uv);
	straw = mix(straw, side, steep);
	n = mix(n, vec3(0.5, 0.5, 1.0), steep * 0.6);
	// Alpha is strand height: the gaps between strands are cavities.
	float cavity = mix(0.45, 1.0, smoothstep(0.1, 0.55, straw.a));
	// Clumps: patches of older, greyer or darker hay across metres, so distance isn't one flat colour.
	// A high mip level blurs the strands into soft blobs (a sharp sample would streak).
	float clump = textureLod(straw_albedo, v_world_xz * 0.013, 6.0).a;
	float age = textureLod(straw_albedo, v_world_xz * 0.0071 + vec2(0.5), 6.0).a;
	vec3 color = straw.rgb * mix(0.9, 1.04, smoothstep(0.42, 0.58, clump));
	color = mix(color, vec3(dot(color, vec3(0.33))) * vec3(1.0, 0.94, 0.82), smoothstep(0.5, 0.6, age) * 0.22);
	float hayness = smoothstep(0.0, 0.06, v_height);
	ALBEDO = mix(ground_color, color, hayness);
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 1.4;
	AO = cavity * v_occlusion;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
}
