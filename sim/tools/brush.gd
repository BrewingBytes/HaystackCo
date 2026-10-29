class_name BrushTool
extends RefCounted
## The hand tools that move hay: lower the pile under a disc (in furrows along the stroke if the
## tool has tines) and either collect the hay or push part of it ahead. Pushed hay that would
## overflow a cell or land off the grid is collected instead (eng D4), so pile mass + collected
## hay never changes. Integers only.

static var _falloff_by_radius := {}
## A library built before brush_stroke existed (bin/ isn't committed) has the class but not
## the method: fall back to GDScript then.
static var _native_stroke := PileGen.native_available() and ClassDB.class_has_method(PileGen.NATIVE_CLASS, &"brush_stroke")


## Stamps `spec` at cell (cx, cy). The stroke direction (dir_x, dir_y) is in 1/256 units.
## Returns the hay collected, in height units.
static func apply(grid: HeightGrid, spec: BrushSpec, cx: int, cy: int, dir_x: int, dir_y: int) -> int:
	var falloff := _falloff(spec.radius)
	var r := spec.radius
	var collected := 0
	var bytes := grid.bytes
	var n := grid.size
	var push_dx := (dir_x * spec.push_cells) >> 8
	var push_dy := (dir_y * spec.push_cells) >> 8
	var half_tine := spec.tine_spacing >> 1
	for dy in range(-r, r + 1):
		var y := cy + dy
		if y < 0 or y >= n:
			continue
		for dx in range(-r, r + 1):
			var d2 := dx * dx + dy * dy
			if d2 > r * r:
				continue
			var x := cx + dx
			if x < 0 or x >= n:
				continue
			var offset := (y * n + x) << 1
			var h := bytes.decode_u16(offset)
			if h == 0:
				continue
			var share := 100
			if spec.tine_spacing > 0:
				var across := (dx * -dir_y + dy * dir_x) >> 8
				share = 100 if posmod(across, spec.tine_spacing) < half_tine else spec.ridge_pct
			var take := mini(h, (spec.depth * falloff[d2] * share) / 25600)
			if take <= 0:
				continue
			bytes.encode_u16(offset, h - take)
			grid.mark_dirty(x, y)
			var pushed := (take * spec.push_pct) / 100
			collected += take - pushed
			if pushed > 0:
				collected += _deposit(grid, x + push_dx, y + push_dy, pushed)
	return collected


## Stamps `spec` at every cell in `stamps` (x, y pairs), in order: one stroke. Returns the hay
## collected. Uses the C++ port when it's loaded (same bytes and total: test_native_parity.gd);
## it marks every tile in the box of changed cells dirty.
static func stroke(grid: HeightGrid, spec: BrushSpec, stamps: PackedInt32Array, dir_x: int, dir_y: int) -> int:
	if not _native_stroke:
		return stroke_gdscript(grid, spec, stamps, dir_x, dir_y)
	var result: Array = ClassDB.class_call_static(PileGen.NATIVE_CLASS, &"brush_stroke", grid.bytes, grid.size, stamps, dir_x, dir_y,
			spec.radius, spec.depth, spec.tine_spacing, spec.ridge_pct, spec.push_pct, spec.push_cells)
	grid.bytes = result[0]
	for ty in range(result[3] >> HeightGrid.TILE_SHIFT, (result[5] >> HeightGrid.TILE_SHIFT) + 1):
		for tx in range(result[2] >> HeightGrid.TILE_SHIFT, (result[4] >> HeightGrid.TILE_SHIFT) + 1):
			grid.mark_dirty(tx << HeightGrid.TILE_SHIFT, ty << HeightGrid.TILE_SHIFT)
	return result[1]


## The reference for the C++ stroke.
static func stroke_gdscript(grid: HeightGrid, spec: BrushSpec, stamps: PackedInt32Array, dir_x: int, dir_y: int) -> int:
	var collected := 0
	for i in range(0, stamps.size() - 1, 2):
		collected += apply(grid, spec, stamps[i], stamps[i + 1], dir_x, dir_y)
	return collected


## Adds `amount` to a cell. Returns what didn't fit (off the grid or above MAX_HEIGHT).
static func _deposit(grid: HeightGrid, x: int, y: int, amount: int) -> int:
	if not grid.in_bounds(x, y):
		return amount
	var h := grid.get_h(x, y)
	var room := HeightGrid.MAX_HEIGHT - h
	var placed := mini(amount, room)
	if placed > 0:
		grid.set_h(x, y, h + placed)
	return amount - placed


## Weight 0..256 by squared distance from the centre, cached per radius.
static func _falloff(radius: int) -> PackedInt32Array:
	if _falloff_by_radius.has(radius):
		return _falloff_by_radius[radius]
	var table := PackedInt32Array()
	var r2 := radius * radius
	table.resize(r2 + 1)
	for d2 in r2 + 1:
		table[d2] = ((r2 - d2) * 256) / r2
	_falloff_by_radius[radius] = table
	return table
