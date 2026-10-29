extends GutTest
## G2b: the C++ pile generator must produce the same bytes as the GDScript reference.
## Skipped (pending) where this platform's native library isn't built; CI sets
## HAYSTACK_REQUIRE_NATIVE=1 so a missing library fails instead.


func _native_or_skip() -> bool:
	if PileGen.native_available():
		return true
	if OS.get_environment("HAYSTACK_REQUIRE_NATIVE") == "1":
		fail_test("native library not loaded (HAYSTACK_REQUIRE_NATIVE=1)")
	else:
		pending("native library not built for this platform")
	return false


func _gdscript_digest(size: int, seed: int, peak: int) -> String:
	var grid := HeightGrid.new(size)
	PileGen.generate_gdscript(grid, seed, peak)
	return grid.digest()


func _native_digest(size: int, seed: int, peak: int) -> String:
	var grid := HeightGrid.new(size)
	grid.bytes = PileGen.generate_native(size, seed, peak)
	return grid.digest()


func test_native_matches_gdscript() -> void:
	if not _native_or_skip():
		return
	for case in [[128, 7, 8000], [256, 1, 20000], [512, 99, 30000], [1024, SpikeConfig.PILE_SEED, SpikeConfig.peak_for(1024)]]:
		assert_eq(_native_digest(case[0], case[1], case[2]), _gdscript_digest(case[0], case[1], case[2]), "grid %d seed %d" % [case[0], case[1]])


func test_native_sum_matches_gdscript() -> void:
	if not _native_or_skip():
		return
	var grid := HeightGrid.new(256)
	PileGen.generate_gdscript(grid, 5, 30000)
	grid.set_h(0, 0, HeightGrid.MAX_HEIGHT)
	assert_eq(grid.mass(), grid.mass_gdscript())


func test_generate_uses_native_when_loaded() -> void:
	if not _native_or_skip():
		return
	var grid := HeightGrid.new(128)
	PileGen.generate(grid, 7, 8000)
	assert_eq(grid.digest(), _gdscript_digest(128, 7, 8000))
	assert_gt(grid.take_dirty().size(), 0, "all tiles dirty after generation")


func test_native_stroke_matches_gdscript() -> void:
	if not _native_or_skip():
		return
	var tools: Array[BrushSpec] = [SimDefaults.RAKE, SimDefaults.PITCHFORK, SimDefaults.BLOWER]
	var dirs := [[256, 0], [181, 181], [0, -256], [-181, 181]]
	for case in 12:
		var rng := SeedRng.new(case + 77)
		var reference := HeightGrid.new(256)
		PileGen.generate_gdscript(reference, case, 30000)
		reference.take_dirty()
		var native := HeightGrid.new(256)
		native.bytes = reference.bytes.duplicate()
		# Stamps run off every edge too, and the blower's push lands off the grid.
		var stamps := PackedInt32Array()
		for i in 16:
			stamps.append(rng.range_int(-20, 276))
			stamps.append(rng.range_int(-20, 276))
		var tool := tools[case % 3]
		var d: Array = dirs[case % 4]
		var expected := BrushTool.stroke_gdscript(reference, tool, stamps, d[0], d[1])
		var got := BrushTool.stroke(native, tool, stamps, d[0], d[1])
		assert_eq(got, expected, "case %d: collected" % case)
		assert_eq(native.digest(), reference.digest(), "case %d: bytes" % case)
		var want := reference.take_dirty()
		var have := native.take_dirty()
		for tile in want:
			assert_true(tile in have, "case %d: tile %d dirty" % [case, tile])


func test_native_tile_delta_matches_gdscript() -> void:
	if not _native_or_skip():
		return
	var base := HeightGrid.new(256)
	PileGen.generate_gdscript(base, 3, 30000)
	var grid := HeightGrid.new(256)
	grid.bytes = base.bytes.duplicate()
	var stamps := PackedInt32Array()
	for i in 20:
		stamps.append_array([40 + i * 9, 128 + (i % 5) * 7])
	BrushTool.stroke_gdscript(grid, SimDefaults.BLOWER, stamps, 181, 181)  # removes and adds hay
	var tiles := PackedInt32Array([0, 5, 6, 9, 15])
	var expected := HeightGrid.tile_delta_gdscript(base.bytes, grid.bytes, 256, tiles, false)
	var got: PackedByteArray = ClassDB.class_call_static(PileGen.NATIVE_CLASS, &"tile_delta", base.bytes, grid.bytes, 256, tiles, false)
	assert_eq(got, expected, "delta")
	var undone: PackedByteArray = ClassDB.class_call_static(PileGen.NATIVE_CLASS, &"tile_delta", base.bytes, got, 256, tiles, true)
	assert_eq(undone, HeightGrid.tile_delta_gdscript(base.bytes, got, 256, tiles, true), "undo")
	var heights := PackedByteArray()
	for tile in tiles:
		heights.append_array(grid.tile_bytes(tile))
	assert_eq(undone, heights, "undo gives the heights back")


func test_native_rejects_mismatched_sizes_instead_of_reading_past_the_grid() -> void:
	if not _native_or_skip():
		return
	var grid := HeightGrid.new(128)
	var tiles := PackedInt32Array([0])
	var short := grid.bytes.slice(0, 100)
	assert_eq(ClassDB.class_call_static(PileGen.NATIVE_CLASS, &"tile_delta", short, grid.bytes, 128, tiles, false), PackedByteArray())
	assert_eq(ClassDB.class_call_static(PileGen.NATIVE_CLASS, &"tile_delta", grid.bytes, short, 128, tiles, true), PackedByteArray())
	assert_eq(ClassDB.class_call_static(PileGen.NATIVE_CLASS, &"tile_delta", grid.bytes, grid.bytes, 128, PackedInt32Array([4]), false), PackedByteArray(), "tile past the grid")
	assert_eq(ClassDB.class_call_static(PileGen.NATIVE_CLASS, &"brush_stroke", short, 128, PackedInt32Array([5, 5]), 256, 0, 12, 90, 4, 35, 0, 0), [])
