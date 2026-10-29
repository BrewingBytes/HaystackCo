class_name HeightGrid
extends RefCounted
## The pile's heightfield: size × size cells, each an unsigned 16-bit height in height units (1 mm).
## Stored little-endian, so a GPU tile (RG8: R = low byte, G = high byte) copies straight out of
## the rows without a per-cell loop. Integers only (eng determinism rule). Mass = sum of heights.

const TILE_SHIFT := 6
const TILE := 1 << TILE_SHIFT
const MAX_HEIGHT := 65535

var size: int
var tiles_per_side: int
var bytes := PackedByteArray()
var _dirty := PackedByteArray()
var _dirty_list := PackedInt32Array()
## Tiles changed since the pile was generated (the dirty list is drained every frame; this
## isn't). A save stores only these tiles and regenerates the rest from the seed.
var _touched := PackedByteArray()
## Tiles changed since the last save or load: only these are packed again (SaveCodec).
var _unsaved := PackedByteArray()


func _init(p_size: int) -> void:
	assert(p_size > 0 and p_size % TILE == 0, "grid size must be a multiple of %d" % TILE)
	size = p_size
	tiles_per_side = size >> TILE_SHIFT
	bytes.resize(size * size * 2)
	_dirty.resize(tiles_per_side * tiles_per_side)
	_touched.resize(tiles_per_side * tiles_per_side)
	_unsaved.resize(tiles_per_side * tiles_per_side)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < size and y < size


func get_h(x: int, y: int) -> int:
	return bytes.decode_u16((y * size + x) << 1)


func set_h(x: int, y: int, value: int) -> void:
	bytes.encode_u16((y * size + x) << 1, clampi(value, 0, MAX_HEIGHT))
	mark_dirty(x, y)


func mark_dirty(x: int, y: int) -> void:
	var tile := (y >> TILE_SHIFT) * tiles_per_side + (x >> TILE_SHIFT)
	_touched[tile] = 1
	_unsaved[tile] = 1
	if _dirty[tile] == 0:
		_dirty[tile] = 1
		_dirty_list.append(tile)


func mark_all_dirty() -> void:
	for tile in tiles_per_side * tiles_per_side:
		if _dirty[tile] == 0:
			_dirty[tile] = 1
			_dirty_list.append(tile)


## Tiles changed since the last clear_touched() (row-major indices).
func touched_tiles() -> PackedInt32Array:
	var tiles := PackedInt32Array()
	for tile in _touched.size():
		if _touched[tile] != 0:
			tiles.append(tile)
	return tiles


func is_unsaved(tile: int) -> bool:
	return _unsaved[tile] != 0


func clear_unsaved() -> void:
	_unsaved.fill(0)


## Called once the pile is generated: from here on, only play changes count.
func clear_touched() -> void:
	_touched.fill(0)


## Replaces whole tiles (index → tile_bytes() layout) in one pass over the rows, marking them
## dirty and touched. Builds the grid row by row: GDScript has no in-place block copy.
func set_tiles(tiles: Dictionary) -> void:
	var out := PackedByteArray()
	var row_bytes := TILE << 1
	for y in size:
		var ty := y >> TILE_SHIFT
		var in_tile := (y & (TILE - 1)) * row_bytes
		var row_start := (y * size) << 1
		var tx := 0
		while tx < tiles_per_side:
			var tile := ty * tiles_per_side + tx
			if tiles.has(tile):
				out.append_array((tiles[tile] as PackedByteArray).slice(in_tile, in_tile + row_bytes))
				tx += 1
				continue
			# A run of untouched tiles on this row comes straight from the current bytes.
			var run_end := tx + 1
			while run_end < tiles_per_side and not tiles.has(ty * tiles_per_side + run_end):
				run_end += 1
			out.append_array(bytes.slice(row_start + tx * row_bytes, row_start + run_end * row_bytes))
			tx = run_end
	bytes = out
	for tile: int in tiles:
		mark_dirty((tile % tiles_per_side) << TILE_SHIFT, (tile / tiles_per_side) << TILE_SHIFT)


## Returns the dirty tile indices (row-major) and clears them.
func take_dirty() -> PackedInt32Array:
	var tiles := _dirty_list
	_dirty_list = PackedInt32Array()
	_dirty.fill(0)
	return tiles


## A tile's TILE × TILE cells as RG8 bytes, copied row by row.
func tile_bytes(tile: int) -> PackedByteArray:
	var tx := (tile % tiles_per_side) << TILE_SHIFT
	var ty := (tile / tiles_per_side) << TILE_SHIFT
	var row_bytes := TILE << 1
	var out := PackedByteArray()
	for row in TILE:
		var start := ((ty + row) * size + tx) << 1
		out.append_array(bytes.slice(start, start + row_bytes))
	return out


## For each tile in `tiles`: (base - grid) mod 2^16 per cell, tile_bytes() layout, concatenated.
## With `undo`, `grid` is that output and the result is the tiles' heights (base - delta). Hay
## that play removed is small and regular next to the heights themselves, so saves store this.
## Uses the native module when it's loaded (test_native_parity.gd).
static func tile_delta(base: PackedByteArray, grid: PackedByteArray, grid_size: int, tiles: PackedInt32Array, undo: bool) -> PackedByteArray:
	if PileGen.native_available() and ClassDB.class_has_method(PileGen.NATIVE_CLASS, &"tile_delta"):
		return ClassDB.class_call_static(PileGen.NATIVE_CLASS, &"tile_delta", base, grid, grid_size, tiles, undo)
	return tile_delta_gdscript(base, grid, grid_size, tiles, undo)


static func tile_delta_gdscript(base: PackedByteArray, grid: PackedByteArray, grid_size: int, tiles: PackedInt32Array, undo: bool) -> PackedByteArray:
	var per_side := grid_size >> TILE_SHIFT
	var out := PackedByteArray()
	out.resize(tiles.size() * TILE * TILE * 2)
	var at := 0
	for tile in tiles:
		var tx := (tile % per_side) << TILE_SHIFT
		var ty := (tile / per_side) << TILE_SHIFT
		for row in TILE:
			for col in TILE:
				var cell := ((ty + row) * grid_size + tx + col) << 1
				out.encode_u16(at, (base.decode_u16(cell) - grid.decode_u16(at if undo else cell)) & 0xFFFF)
				at += 2
	return out


## Sum of all heights (the pile's mass). Whole-grid pass: once per pile and in tests; uses the
## native module when it's loaded.
func mass() -> int:
	if ClassDB.class_exists(PileGen.NATIVE_CLASS):
		return ClassDB.class_call_static(PileGen.NATIVE_CLASS, &"sum_heights", bytes)
	return mass_gdscript()


func mass_gdscript() -> int:
	var total := 0
	for i in size * size:
		total += bytes.decode_u16(i << 1)
	return total


## SHA-256 of the grid bytes: the determinism golden (same on desktop, device and any C++ port).
func digest() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()
