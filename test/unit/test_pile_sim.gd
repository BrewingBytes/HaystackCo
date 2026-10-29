extends GutTest
## G3: the sim's rules. Mass ledger (eng D4), seeds (eng D5), needle placement, reveal,
## magnet, detector, NeedleFound sources, and a determinism golden for scripted strokes.

const SIZE := 128


func _spec(seed: int, needles := 3, number := 2) -> PileSpec:
	return PileSpec.new(number, SIZE, 8000, seed, needles)


func _flat(height: int) -> HeightGrid:
	var grid := HeightGrid.new(64)
	for y in 64:
		for x in 64:
			grid.set_h(x, y, height)
	grid.take_dirty()
	return grid


# --- Mass ledger ---------------------------------------------------------------------------

func test_mass_is_conserved_over_200_seeds_of_random_strokes() -> void:
	var tools: Array[BrushSpec] = [SimDefaults.RAKE, SimDefaults.PITCHFORK, SimDefaults.BLOWER]
	for seed in 200:
		var sim := PileSim.create(_spec(seed))
		var rng := SeedRng.new(seed + 1000)
		sim.machines.append(ConveyorDig.new(SIZE / 2, 0, 0, 256, 6, SIZE / 2, 40_000))
		for i in 24:
			# Includes stamps off the grid's edge and strokes pointing off it.
			var x := rng.range_int(-10, SIZE + 10)
			var y := rng.range_int(-10, SIZE + 10)
			var angle := rng.range_int(0, 7)
			var dirs := [[256, 0], [181, 181], [0, 256], [-181, 181], [-256, 0], [-181, -181], [0, -256], [181, -181]]
			sim.brush(tools[i % 3], x, y, dirs[angle][0], dirs[angle][1])
			if i % 8 == 0:
				sim.advance_machines(500)
		assert_true(sim.mass_balanced(), "seed %d: pile + collected == initial" % seed)
		if not sim.mass_balanced():
			return


func test_blower_pushes_hay_and_off_grid_hay_is_collected() -> void:
	var grid := _flat(1000)
	var before := grid.mass()
	# Blow from the right edge outward: everything pushed lands off the grid.
	var collected := BrushTool.apply(grid, SimDefaults.BLOWER, 63, 32, 256, 0)
	assert_eq(grid.mass() + collected, before)
	assert_gt(collected, 0)


func test_blower_keeps_most_hay_on_the_pile() -> void:
	var grid := _flat(1000)
	var before := grid.mass()
	var collected := BrushTool.apply(grid, SimDefaults.BLOWER, 20, 32, 256, 0)
	assert_eq(grid.mass() + collected, before)
	var b := SimDefaults.BLOWER
	var no_push := BrushSpec.new(&"no_push", b.radius, b.depth, b.tine_spacing, b.ridge_pct, 0, 0)
	var all_taken := BrushTool.apply(_flat(1000), no_push, 20, 32, 256, 0)
	assert_lt(collected * 2, all_taken, "most of the hay it moves stays on the pile")
	assert_gt(grid.get_h(20 + b.push_cells, 32), 1000, "a ridge builds ahead")


func test_push_overflow_is_collected() -> void:
	var grid := _flat(1000)
	grid.set_h(50, 32, HeightGrid.MAX_HEIGHT - 5)
	var before := grid.mass()
	var collected := BrushTool.apply(grid, SimDefaults.BLOWER, 20, 32, 256, 0)
	assert_eq(grid.get_h(50, 32), HeightGrid.MAX_HEIGHT)
	assert_eq(grid.mass() + collected, before)


# --- Seeds ----------------------------------------------------------------------------------

func test_pile_1_seed_is_fixed_for_every_install() -> void:
	assert_eq(SimDefaults.spec_for(1, 111).seed, SimDefaults.spec_for(1, 999).seed)
	assert_eq(SimDefaults.spec_for(1, 111).seed, SimDefaults.PILE1_SEED)


func test_later_piles_depend_on_install_and_number() -> void:
	assert_ne(SimDefaults.spec_for(2, 111).seed, SimDefaults.spec_for(2, 999).seed)
	assert_ne(SimDefaults.spec_for(2, 111).seed, SimDefaults.spec_for(3, 111).seed)
	assert_eq(SimDefaults.spec_for(4, 111).seed, SimDefaults.spec_for(4, 111).seed)


func test_each_pile_is_at_least_as_big() -> void:
	for n in range(1, 12):
		assert_true(SimDefaults.pile_size(n + 1) >= SimDefaults.pile_size(n))
		assert_eq(SimDefaults.pile_size(n) % HeightGrid.TILE, 0)
	assert_eq(SimDefaults.needles_for(1), 1)


func test_rng_golden_sequence() -> void:
	var rng := SeedRng.new(42)
	assert_eq([rng.next(), rng.next(), rng.next()], [1137218979, 2129100477, 3072479877])


# --- Needles ---------------------------------------------------------------------------------

func test_needles_start_buried_inside_the_pile() -> void:
	for seed in 50:
		var sim := PileSim.create(_spec(seed, 5))
		for needle in sim.needles:
			assert_true(sim.grid.in_bounds(needle.x, needle.y))
			assert_lt(needle.z, sim.grid.get_h(needle.x, needle.y), "under the surface")
			assert_false(Reveal.uncovered(sim.grid, needle, sim.reveal_cell, sim.reveal_threshold), "seed %d starts covered" % seed)


func test_pile_1_needle_is_under_the_first_flank() -> void:
	var sim := PileSim.create(SimDefaults.spec_for(1, 7))
	var needle := sim.needles[0]
	var centre := sim.grid.size / 2
	var radius := sim.grid.size * 47 / 100
	assert_almost_eq(needle.x, centre, radius * 6 / 100)
	assert_almost_eq(needle.y, centre + radius * 55 / 100, radius * 6 / 100)
	assert_eq(sim.grid.get_h(needle.x, needle.y) - needle.z, PileGen.FIRST_NEEDLE_DEPTH)


func test_needle_placement_golden() -> void:
	var sim := PileSim.create(_spec(9, 3))
	var placed := sim.needles.map(func(n: Needle) -> Array: return [n.x, n.y, n.z])
	assert_eq(placed, [[37, 57, 4749], [69, 58, 6345], [74, 49, 2662]])


# --- Reveal, magnet, detector ---------------------------------------------------------------

func test_reveal_threshold_is_inclusive() -> void:
	var needle := Needle.new(32, 32, 900)
	assert_true(Reveal.uncovered(_flat(950), needle, 8, 50), "50 above at threshold 50: found")
	assert_false(Reveal.uncovered(_flat(951), needle, 8, 50), "51 above: still covered")
	assert_true(Reveal.uncovered(_flat(0), needle, 8, 50), "dug below the needle")


func test_reveal_uses_the_mean_over_the_square() -> void:
	var grid := _flat(900)
	var needle := Needle.new(32, 32, 900)
	grid.set_h(32, 32, 900 + 50 * 64)  # one tall cell: mean exactly at the threshold
	assert_true(Reveal.uncovered(grid, needle, 8, 50))
	grid.set_h(32, 32, 900 + 50 * 64 + 1)
	assert_false(Reveal.uncovered(grid, needle, 8, 50))


func test_magnet_radius_edge() -> void:
	var needles: Array[Needle] = [Needle.new(30, 20, 0)]
	assert_eq(MagnetTool.in_reach(needles, 20, 20, 10).size(), 1, "exactly at the radius")
	assert_eq(MagnetTool.in_reach(needles, 20, 20, 9).size(), 0, "one cell short")


func test_magnet_finds_under_any_hay() -> void:
	var sim := PileSim.create(_spec(3, 1))
	var needle := sim.needles[0]
	var found := sim.magnet(needle.x + 5, needle.y)
	assert_eq(found.size(), 1)
	assert_eq(needle.source, Needle.Source.PLAYER)
	assert_true(sim.is_complete())


func test_detector_never_finds_and_grows_closer() -> void:
	var sim := PileSim.create(_spec(4, 2))
	var needle := sim.needles[0]
	var far := sim.detector(needle.x + 60, needle.y)
	var near := sim.detector(needle.x + 5, needle.y)
	var on := sim.detector(needle.x, needle.y)
	assert_lt(far, near)
	assert_lt(near, on + 1)
	assert_eq(on, DetectorTool.MAX_STRENGTH)
	assert_eq(DetectorTool.strength(sim.needles, needle.x + SimDefaults.DETECTOR_RANGE, needle.y, SimDefaults.DETECTOR_RANGE) <= DetectorTool.MAX_STRENGTH / 2, true)
	for n in sim.needles:
		assert_false(n.found, "the detector never finds")


func test_detector_is_silent_when_all_found() -> void:
	var needles: Array[Needle] = [Needle.new(5, 5, 0)]
	needles[0].found = true
	assert_eq(DetectorTool.strength(needles, 5, 5, 40), 0)


# --- Sources ----------------------------------------------------------------------------------

func test_find_sources() -> void:
	var by_hand := PileSim.create(_spec(5, 1))
	var needle := by_hand.needles[0]
	var found: Array[Needle] = []
	for i in 400:
		found.append_array(by_hand.brush(SimDefaults.PITCHFORK, needle.x, needle.y, 0, 256))
		if not found.is_empty():
			break
	assert_eq(found.size(), 1)
	assert_eq(found[0].source, Needle.Source.PLAYER)

	var machine := PileSim.create(_spec(5, 1))
	var target := machine.needles[0]
	machine.machines.append(ConveyorDig.new(target.x, 0, 0, 256, 12, SIZE, 10_000_000))
	var by_machine := machine.advance_machines(60_000)
	assert_eq(by_machine.size(), 1)
	assert_eq(by_machine[0].source, Needle.Source.MACHINE)

	var away := PileSim.create(_spec(5, 1))
	away.machines.append(ConveyorDig.new(target.x, 0, 0, 256, 12, SIZE, 10_000_000))
	var offline := away.offline(60_000)
	assert_eq(offline.size(), 1)
	assert_eq(offline[0].source, Needle.Source.OFFLINE)


# --- Determinism golden ------------------------------------------------------------------------

func test_scripted_strokes_golden() -> void:
	var sim := PileSim.create(_spec(11, 2))
	var tools: Array[BrushSpec] = [SimDefaults.RAKE, SimDefaults.PITCHFORK, SimDefaults.BLOWER]
	for i in 60:
		sim.brush(tools[i % 3], 30 + i, 40 + (i * 7) % 50, 256, (i % 5) * 40 - 80)
	assert_eq("%s/%d" % [sim.grid.digest(), sim.collected], "2fb6c4bf71a6f1741ce43506054cd52d4658cfc7d844bcb471255a50d7141373/697835")
