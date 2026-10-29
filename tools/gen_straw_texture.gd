extends SceneTree
## Generates the tileable straw textures the hay shader samples (run once; outputs are committed):
##   godot --headless -s res://tools/gen_straw_texture.gd
## world/textures/straw_albedo.png: RGB colour, A = strand height (cavities are dark and low).
## world/textures/straw_normal.png: tangent-space normal from that height (OpenGL, +Y up).
## Thousands of crossing strands, painted bottom to top; deterministic for a fixed seed.

const SIZE := 512
const STRANDS := 5200
const SEED := 20261027
const NORMAL_STRENGTH := 3.0
const OUT_DIR := "res://world/textures/"

# DESIGN.md: straw mid-tones #B8873A–#E9C77A with deep shadows; a little old, grey straw.
const PALETTE := [
	[Color("#B8873A"), 40],
	[Color("#E9C77A"), 28],
	[Color("#D2AB5C"), 18],
	[Color("#9C8A5E"), 9],
	[Color("#8A6A2E"), 5],
]
const GAP := Color("#2E2010")

var _rng := RandomNumberGenerator.new()
var _rgb := PackedFloat32Array()
var _height := PackedFloat32Array()


func _init() -> void:
	_rng.seed = SEED
	_rgb.resize(SIZE * SIZE * 3)
	_height.resize(SIZE * SIZE)
	for i in SIZE * SIZE:
		_rgb[i * 3] = GAP.r
		_rgb[i * 3 + 1] = GAP.g
		_rgb[i * 3 + 2] = GAP.b
	for i in STRANDS:
		_strand()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_albedo_image().save_png(OUT_DIR + "straw_albedo.png")
	_normal_image().save_png(OUT_DIR + "straw_normal.png")
	print("straw textures written to ", OUT_DIR)
	quit()


func _pick_color() -> Color:
	var total := 0
	for entry in PALETTE:
		total += entry[1]
	var roll := _rng.randi_range(0, total - 1)
	for entry in PALETTE:
		roll -= entry[1]
		if roll < 0:
			return entry[0]
	return PALETTE[0][0]


## One strand: a slightly bent cylinder painted over whatever is below it.
func _strand() -> void:
	var centre := Vector2(_rng.randf() * SIZE, _rng.randf() * SIZE)
	var angle := _rng.randf() * TAU
	var length := _rng.randf_range(28.0, 115.0)
	var half_width := _rng.randf_range(1.1, 2.6)
	var bend := _rng.randf_range(-0.004, 0.004)
	var base := _pick_color()
	var shade := _rng.randf_range(0.8, 1.12)
	var lift := _rng.randf_range(0.0, 0.25)
	var dir := Vector2.from_angle(angle)
	var across := dir.orthogonal()
	var t := -length * 0.5
	while t <= length * 0.5:
		var along := t / (length * 0.5)  # -1..1
		var taper := 1.0 - pow(absf(along), 6.0)
		var spine := centre + dir * t + across * (bend * t * t)
		var s := -half_width
		while s <= half_width:
			var u := s / half_width  # -1..1 across
			var bulge := sqrt(maxf(0.0, 1.0 - u * u)) * taper
			if bulge > 0.05:
				var p := spine + across * s
				var x := posmod(int(floor(p.x)), SIZE)
				var y := posmod(int(floor(p.y)), SIZE)
				var i := y * SIZE + x
				# Light runs along the strand's top; the flanks fall into shadow.
				var light := shade * (0.62 + 0.45 * bulge) * (0.95 + 0.05 * sin(t * 0.9))
				_rgb[i * 3] = base.r * light
				_rgb[i * 3 + 1] = base.g * light
				_rgb[i * 3 + 2] = base.b * light
				_height[i] = 0.35 + 0.4 * bulge + lift
			s += 0.6
		t += 0.7


func _albedo_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(SIZE * SIZE * 4)
	for i in SIZE * SIZE:
		bytes[i * 4] = clampi(int(_rgb[i * 3] * 255.0), 0, 255)
		bytes[i * 4 + 1] = clampi(int(_rgb[i * 3 + 1] * 255.0), 0, 255)
		bytes[i * 4 + 2] = clampi(int(_rgb[i * 3 + 2] * 255.0), 0, 255)
		bytes[i * 4 + 3] = clampi(int(_height[i] * 255.0), 0, 255)
	return Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, bytes)


func _normal_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(SIZE * SIZE * 3)
	for y in SIZE:
		for x in SIZE:
			var dx := _height[y * SIZE + posmod(x + 1, SIZE)] - _height[y * SIZE + posmod(x - 1, SIZE)]
			var dy := _height[posmod(y + 1, SIZE) * SIZE + x] - _height[posmod(y - 1, SIZE) * SIZE + x]
			var n := Vector3(-dx * NORMAL_STRENGTH, dy * NORMAL_STRENGTH, 1.0).normalized()
			var i := (y * SIZE + x) * 3
			bytes[i] = int((n.x * 0.5 + 0.5) * 255.0)
			bytes[i + 1] = int((n.y * 0.5 + 0.5) * 255.0)
			bytes[i + 2] = int((n.z * 0.5 + 0.5) * 255.0)
	return Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, bytes)
