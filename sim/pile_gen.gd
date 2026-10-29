class_name PileGen
extends RefCounted
## Seed → pile heights. A paraboloid dome with two octaves of integer value noise, so the
## flanks are lumpy and the foot is ragged. Integers only; same seed, same bytes everywhere.

const COARSE_SHIFT := 6  # 64-cell lattice: big lumps
const FINE_SHIFT := 4  # 16-cell lattice: small lumps
const COARSE_AMP_PCT := 4
const FINE_AMP_PCT := 1


## C++ port of generate_gdscript (addons/haystack_native, G2b); loaded when this platform's
## library was built. Both produce the same bytes (test/unit/test_native_parity.gd).
const NATIVE_CLASS := &"SimNative"
const FIRST_NEEDLE_DEPTH := 400  # pile 1's needle: 40 cm under the flank you see first
const NEEDLE_REACH_PCT := 85  # needles lie within this share of the pile's radius
const MIN_NEEDLE_COVER := 1000  # never under less than 1 m of hay (except pile 1's)


static func native_available() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## Fills `grid` in place. `peak` is the dome's top height in height units.
static func generate(grid: HeightGrid, seed: int, peak: int) -> void:
	if native_available():
		grid.bytes = generate_native(grid.size, seed, peak)
		grid.mark_all_dirty()
	else:
		generate_gdscript(grid, seed, peak)


static func generate_native(size: int, seed: int, peak: int) -> PackedByteArray:
	return ClassDB.class_call_static(NATIVE_CLASS, &"generate", size, seed, peak, COARSE_SHIFT, FINE_SHIFT, COARSE_AMP_PCT, FINE_AMP_PCT)


## The reference implementation: the spec the native port must match byte for byte.
static func generate_gdscript(grid: HeightGrid, seed: int, peak: int) -> void:
	var n := grid.size
	var centre := n >> 1
	var radius := (n * 47) / 100
	var r2_max := radius * radius
	var coarse_amp := (peak * COARSE_AMP_PCT) / 100
	var fine_amp := (peak * FINE_AMP_PCT) / 100
	var coarse_cols := (n >> COARSE_SHIFT) + 2
	var fine_cols := (n >> FINE_SHIFT) + 2
	var coarse_row := PackedInt32Array()
	coarse_row.resize(coarse_cols)
	var fine_row := PackedInt32Array()
	fine_row.resize(fine_cols)
	var coarse_fade := _fade_table(COARSE_SHIFT)
	var fine_fade := _fade_table(FINE_SHIFT)
	var bytes := grid.bytes
	for y in n:
		var dy := y - centre
		var dy2 := dy * dy
		var row_start := y * n
		if dy2 >= r2_max:
			continue
		_lattice_row(coarse_row, seed, y, COARSE_SHIFT, coarse_amp, coarse_fade)
		_lattice_row(fine_row, seed ^ 0x5bd1e995, y, FINE_SHIFT, fine_amp, fine_fade)
		for x in n:
			var dx := x - centre
			var r2 := dx * dx + dy2
			if r2 >= r2_max:
				continue
			var dome := (peak * (r2_max - r2)) / r2_max
			var cx := x >> COARSE_SHIFT
			var fx := coarse_fade[x & ((1 << COARSE_SHIFT) - 1)]
			var coarse := (coarse_row[cx] * ((1 << COARSE_SHIFT) - fx) + coarse_row[cx + 1] * fx) >> COARSE_SHIFT
			var gx := x >> FINE_SHIFT
			var gfx := fine_fade[x & ((1 << FINE_SHIFT) - 1)]
			var fine := (fine_row[gx] * ((1 << FINE_SHIFT) - gfx) + fine_row[gx + 1] * gfx) >> FINE_SHIFT
			# Noise scales with the dome so the top stays round and the foot frays.
			var h := dome + ((coarse + fine) * dome) / peak
			if h > 0:
				bytes.encode_u16((row_start + x) << 1, mini(h, HeightGrid.MAX_HEIGHT))
	grid.mark_all_dirty()


## One row of the lattice, interpolated in y, into `out` (one value per lattice column).
static func _lattice_row(out: PackedInt32Array, seed: int, y: int, shift: int, amp: int, fade: PackedInt32Array) -> void:
	var ly := y >> shift
	var fy := fade[y & ((1 << shift) - 1)]
	for lx in out.size():
		var a := _lattice(seed, lx, ly, amp)
		var b := _lattice(seed, lx, ly + 1, amp)
		out[lx] = (a * ((1 << shift) - fy) + b * fy) >> shift


## Smoothstep weights 0..2^shift for each offset inside a lattice cell. Linear weights leave
## creases along the lattice lines that low light shows as gullies.
static func _fade_table(shift: int) -> PackedInt32Array:
	var cell := 1 << shift
	var table := PackedInt32Array()
	table.resize(cell)
	for f in cell:
		table[f] = (f * f * (3 * cell - 2 * f)) / (cell * cell)
	return table


## Deterministic lattice value in [-amp, amp].
static func _lattice(seed: int, x: int, y: int, amp: int) -> int:
	var h := (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return ((h & 0xFFFF) * 2 * amp) / 0xFFFF - amp


## Buries `spec.needles` needles in a generated grid. Pile 1's first needle goes under the flank
## the default camera frames (where players rake first); the rest are spread through the pile at
## 20–80% of the local height. Deterministic for the seed.
static func place_needles(grid: HeightGrid, spec: PileSpec) -> Array[Needle]:
	var rng := SeedRng.new(spec.seed ^ 0x6E656564)
	var needles: Array[Needle] = []
	var centre := grid.size >> 1
	var radius := (grid.size * 47) / 100
	var reach := (radius * NEEDLE_REACH_PCT) / 100
	for i in spec.needles:
		if spec.number == 1 and i == 0:
			var jitter := (radius * 6) / 100
			var x := centre + rng.range_int(-jitter, jitter)
			var y := centre + (radius * 55) / 100 + rng.range_int(-jitter, jitter)
			needles.append(Needle.new(x, y, maxi(0, grid.get_h(x, y) - FIRST_NEEDLE_DEPTH)))
			continue
		while true:
			var x := centre + rng.range_int(-reach, reach)
			var y := centre + rng.range_int(-reach, reach)
			var dx := x - centre
			var dy := y - centre
			var h := grid.get_h(x, y)
			if dx * dx + dy * dy <= reach * reach and h >= MIN_NEEDLE_COVER * 2:
				needles.append(Needle.new(x, y, (h * rng.range_int(20, 80)) / 100))
				break
	return needles
