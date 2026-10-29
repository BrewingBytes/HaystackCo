extends GutTest
## G2 sim pieces: heights round-trip, tiles, pile determinism, and the mass ledger
## (pile mass + dug hay never changes) for the rake, conveyors and offline time.

const SIZE := 128
const PEAK := 8000


func _pile() -> HeightGrid:
	var grid := HeightGrid.new(SIZE)
	PileGen.generate_gdscript(grid, 7, PEAK)
	grid.take_dirty()
	return grid


func test_height_round_trip_and_clamp() -> void:
	var grid := HeightGrid.new(64)
	grid.set_h(3, 5, 1234)
	assert_eq(grid.get_h(3, 5), 1234)
	grid.set_h(0, 0, 70000)
	assert_eq(grid.get_h(0, 0), HeightGrid.MAX_HEIGHT)
	grid.set_h(1, 0, -5)
	assert_eq(grid.get_h(1, 0), 0)


func test_dirty_tiles_are_tracked_once() -> void:
	var grid := HeightGrid.new(128)
	grid.set_h(1, 1, 5)
	grid.set_h(2, 2, 5)
	grid.set_h(127, 127, 5)
	assert_eq(Array(grid.take_dirty()), [0, 3])
	assert_eq(grid.take_dirty().size(), 0)


func test_tile_bytes_are_the_tile_rows() -> void:
	var grid := HeightGrid.new(128)
	grid.set_h(64, 0, 0x1234)  # tile 1, local (0, 0)
	grid.set_h(65, 63, 0x00FF)  # tile 1, local (1, 63)
	var bytes := grid.tile_bytes(1)
	assert_eq(bytes.size(), 64 * 64 * 2)
	assert_eq(bytes.decode_u16(0), 0x1234)
	assert_eq(bytes[0], 0x34, "low byte first (RG8: R = low)")
	assert_eq(bytes.decode_u16((63 * 64 + 1) * 2), 0x00FF)


func test_pile_is_deterministic_and_seeded() -> void:
	var a := HeightGrid.new(SIZE)
	var b := HeightGrid.new(SIZE)
	var c := HeightGrid.new(SIZE)
	PileGen.generate_gdscript(a, 7, PEAK)
	PileGen.generate_gdscript(b, 7, PEAK)
	PileGen.generate_gdscript(c, 8, PEAK)
	assert_eq(a.digest(), b.digest())
	assert_ne(a.digest(), c.digest())


func test_pile_golden_digest() -> void:
	# Pins the generator's bytes: any change to pile generation (or a C++ port) must match it.
	assert_eq(_pile().digest(), "82583502436713c0264e713c762b4a9db9923ee8221d52e58ef5dca8270c3cd9")


func test_pile_shape() -> void:
	var grid := _pile()
	var centre := grid.get_h(SIZE / 2, SIZE / 2)
	assert_gt(centre, PEAK / 2, "tall in the middle")
	assert_eq(grid.get_h(0, 0), 0, "bare ground at the corner")
	assert_eq(grid.get_h(SIZE / 2, 1), 0, "bare ground past the foot")


func test_rake_conserves_mass() -> void:
	var grid := _pile()
	var before := grid.mass()
	var removed := BrushTool.apply(grid, SimDefaults.RAKE, SIZE / 2, SIZE / 2 + 20, 256, 0)
	assert_gt(removed, 0)
	assert_eq(grid.mass() + removed, before)
	assert_gt(grid.take_dirty().size(), 0)


func test_rake_never_goes_below_ground() -> void:
	var grid := HeightGrid.new(64)
	grid.set_h(32, 32, 10)
	var removed := BrushTool.apply(grid, SimDefaults.RAKE, 32, 32, 0, 256)
	assert_eq(removed, 10)
	assert_eq(grid.get_h(32, 32), 0)
	assert_eq(BrushTool.apply(grid, SimDefaults.RAKE, 0, 0, 256, 0), 0, "rake off the edge of bare ground")


func test_rake_leaves_furrows() -> void:
	var grid := HeightGrid.new(64)
	for y in range(20, 44):
		for x in range(20, 44):
			grid.set_h(x, y, 5000)
	BrushTool.apply(grid, SimDefaults.RAKE, 32, 32, 256, 0)  # stroke along +x: furrows run along x
	assert_ne(grid.get_h(32, 32), grid.get_h(32, 34), "furrow and ridge differ across the stroke")


func test_conveyor_digs_a_trench_to_the_ground_and_conserves_mass() -> void:
	var grid := _pile()
	var before := grid.mass()
	var conveyor := ConveyorDig.new(SIZE / 2, 2, 0, 256, 4, SIZE / 2, 50_000)
	var dug := 0
	for i in 200:
		dug += conveyor.step(grid, 100)
	assert_eq(grid.mass() + dug, before)
	assert_gt(conveyor.front, 10, "front advanced")
	assert_eq(grid.get_h(SIZE / 2, 2 + conveyor.front - 1), 0, "trench floor is the ground")


func test_conveyor_trench_walls_slope_instead_of_cliffs() -> void:
	var grid := HeightGrid.new(128)
	for y in 128:
		for x in 128:
			grid.set_h(x, y, 5000)
	var conveyor := ConveyorDig.new(64, 0, 0, 256, 4, 3, 10_000_000)  # digs along +y; floor is x 63..66
	conveyor.step(grid, 10_000)
	assert_true(conveyor.done())
	for x in range(63, 67):
		assert_eq(grid.get_h(x, 1), 0, "floor at the ground")
	for k in 4:
		# Walls start beside the floor (x 62 and x 67); each cell out is WALL_RISE higher, ± jitter.
		var expected := (k + 1) * ConveyorDig.WALL_RISE
		assert_almost_eq(grid.get_h(62 - k, 1), expected, ConveyorDig.WALL_JITTER, "wall cell %d (low x)" % k)
		assert_almost_eq(grid.get_h(67 + k, 1), expected, ConveyorDig.WALL_JITTER, "wall cell %d (high x)" % k)
	assert_eq(grid.get_h(62 - 25, 1), 5000, "untouched past the top of the wall")
	assert_eq(grid.get_h(63, 5), 5000, "untouched past the front")


func test_conveyor_never_raises_hay() -> void:
	var grid := _pile()
	var before := grid.bytes.duplicate()
	var conveyor := ConveyorDig.new(SIZE / 2, 2, 0, 256, 4, SIZE / 2, 200_000)
	for i in 50:
		conveyor.step(grid, 1000)
	for i in SIZE * SIZE:
		assert_true(grid.bytes.decode_u16(i << 1) <= before.decode_u16(i << 1), "cell %d rose" % i)
		if grid.bytes.decode_u16(i << 1) > before.decode_u16(i << 1):
			return


func test_conveyor_carries_sub_unit_rate() -> void:
	var grid := HeightGrid.new(64)
	grid.set_h(10, 10, 100)
	var conveyor := ConveyorDig.new(10, 10, 0, 256, 1, 10, 3)  # 3 units/s
	var dug := 0
	for i in 10:
		dug += conveyor.step(grid, 100)  # 10 × 0.3 units
	assert_eq(dug, 3)


func test_offline_matches_live_steps() -> void:
	var live := _pile()
	var away := _pile()
	var live_conveyor := ConveyorDig.new(SIZE / 2, 2, 0, 256, 4, SIZE / 2, 2_000)
	var away_conveyors: Array[ConveyorDig] = [ConveyorDig.new(SIZE / 2, 2, 0, 256, 4, SIZE / 2, 2_000)]
	var ms := 3 * OfflineSim.STEP_MS + 1234
	var live_dug := 0
	var left := ms
	while left > 0:
		live_dug += live_conveyor.step(live, mini(left, OfflineSim.STEP_MS))
		left -= OfflineSim.STEP_MS
	assert_eq(OfflineSim.fast_forward(away, away_conveyors, ms), live_dug)
	assert_eq(away.digest(), live.digest())


func test_picker_hits_the_pile_from_above() -> void:
	var grid := _pile()
	var hit := HeightPicker.pick(grid, Vector3(0.0, 100.0, 0.0), Vector3.DOWN)
	assert_true(hit.hit)
	assert_true(hit.hay)
	assert_almost_eq(hit.point.y, HeightPicker.height_at(grid, 0.0, 0.0), 0.05)


func test_picker_falls_through_to_ground() -> void:
	var grid := _pile()
	var far := SIZE * SpikeConfig.CELL_M
	var hit := HeightPicker.pick(grid, Vector3(far, 10.0, far), Vector3(0.3, -1.0, 0.0).normalized())
	assert_true(hit.hit)
	assert_false(hit.hay)
	assert_almost_eq(hit.point.y, 0.0, 0.001)
