shader_type spatial;
// A placed machine printing from blueprint into steel (DESIGN.md "Printing"): the steel fills
// in from the base up as `progress` goes 0 → 1 over 400 ms; above the fill line it's still the
// blueprint wash. Reduced motion sets progress straight to 1.

render_mode cull_back;

uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float height_m = 1.1;
uniform vec3 steel : source_color = vec3(0.788, 0.827, 0.863); // machine-paint #C9D3DC
uniform vec3 blueprint : source_color = vec3(0.173, 0.435, 0.718); // ghost-fill #2C6FB7

varying float v_up;

void vertex() {
	v_up = VERTEX.y / height_m + 0.5; // box centred on its origin: 0 at the base, 1 at the top
}

void fragment() {
	float filled = step(v_up, progress);
	ALBEDO = mix(blueprint, steel, filled);
	METALLIC = mix(0.0, 0.35, filled);
	ROUGHNESS = mix(0.9, 0.5, filled);
	EMISSION = blueprint * 0.35 * (1.0 - filled);
}
