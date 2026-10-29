extends GutTest
## G4: footprint rules, the shelf, placement mode, channel digging and new-pile shelving.

const SIZE := 256

var spec := SimDefaults.CONVEYOR


func _sim(seed := 3) -> PileSim:
	return PileSim.create(PileSpec.new(2, SIZE, 12000, seed, 2))


func test_footprint_spans_its_length_on_every_heading() -> void:
	for yaw in 8:
		var pose := Pose.new(0, 0, yaw)
		var cells := Placement.footprint(spec, pose)
		assert_true(cells.size() >= spec.length * spec.width * 9 / 10, "covers about length × width")
		# No gaps: every cell inside the outline has a footprint neighbour on each side.
		for cell in cells:
			var neighbours := 0
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if cells.has(cell + offset):
					neighbours += 1
			assert_true(neighbours >= 1, "isolated cell on heading %d" % yaw)
		assert_true(cells.has(Vector2i(0, 0)), "covers its centre")
		var front := Placement.front(spec, pose)
		var tip := Vector2i(front.x - ((pose.dir().x * 3) >> 8), front.y - ((pose.dir().y * 3) >> 8))
		assert_true(cells.has(tip), "reaches its front edge on heading %d" % yaw)


func test_bounds() -> void:
	var sim := _sim()
	var far := -Placement.YARD_MARGIN - spec.length
	assert_eq(Placement.check(sim.grid, {}, spec, Pose.new(far, 20, 0)), Placement.Problem.OUT_OF_BOUNDS)
	assert_eq(Placement.check(sim.grid, {}, spec, Pose.new(-40, -40, 0)), Placement.Problem.NONE, "bare yard outside the grid is fine")


func test_not_on_hay() -> void:
	var sim := _sim()
	assert_eq(Placement.check(sim.grid, {}, spec, Pose.new(SIZE / 2, SIZE / 2, 0)), Placement.Problem.ON_HAY)
	assert_eq(Placement.check(sim.grid, {}, spec, Pose.new(10, 10, 1)), Placement.Problem.NONE, "the grid's bare corner")


func test_no_overlap() -> void:
	var sim := _sim()
	var park := MachinePark.new()
	park.place(sim, spec, Pose.new(-40, -40, 0))
	assert_eq(Placement.check(sim.grid, Placement.occupied_by(park.placed), spec, Pose.new(-30, -40, 2)), Placement.Problem.OVERLAP)
	assert_eq(Placement.check(sim.grid, Placement.occupied_by(park.placed), spec, Pose.new(-40, -40 + spec.width + 1, 0)), Placement.Problem.NONE, "side by side")


func test_buy_puts_it_on_the_shelf() -> void:
	var park := MachinePark.new()
	park.buy(spec)
	assert_eq(park.shelf_count(&"conveyor"), 1)
	assert_eq(park.placed.size(), 0)


func test_ghost_starts_at_a_valid_edge_spot_facing_the_centre() -> void:
	var sim := _sim()
	var park := MachinePark.new()
	park.buy(spec)
	var session := PlacementSession.begin(park, sim, &"conveyor", Vector2i(SIZE / 2, SIZE))
	assert_not_null(session)
	assert_eq(park.shelf_count(), 0, "off the shelf while placing")
	assert_true(session.can_place())
	var to_centre := Vector2i(SIZE / 2 - session.pose.x, SIZE / 2 - session.pose.y)
	assert_gt(session.pose.dir().x * to_centre.x + session.pose.dir().y * to_centre.y, 0, "faces the centre")
	assert_gt(session.pose.y, SIZE / 2, "on the side nearest the requested cell")


func test_cancel_returns_the_machine_to_the_shelf() -> void:
	var sim := _sim()
	var park := MachinePark.new()
	park.buy(spec)
	var session := PlacementSession.begin(park, sim, &"conveyor", Vector2i(0, 0))
	session.cancel()
	assert_eq(park.shelf_count(&"conveyor"), 1)
	assert_eq(park.placed.size(), 0)
	session.cancel()
	assert_eq(park.shelf_count(&"conveyor"), 1, "cancelling twice doesn't duplicate it")


func test_place_only_when_valid() -> void:
	var sim := _sim()
	var park := MachinePark.new()
	park.buy(spec)
	var session := PlacementSession.begin(park, sim, &"conveyor", Vector2i(0, 0))
	var good := session.pose.copy()
	session.move_to(Vector2i(SIZE / 2, SIZE / 2))
	assert_false(session.can_place(), "on hay")
	assert_null(session.confirm())
	assert_true(session.is_open(), "an invalid PLACE leaves placement open")
	session.move_to(Vector2i(good.x, good.y))
	session.turn(8)  # a full turn
	assert_true(session.can_place())
	var machine := session.confirm()
	assert_not_null(machine)
	assert_eq(park.placed.size(), 1)
	assert_true(sim.machines.has(machine.dig), "digs on the pile")


func test_turn_is_45_degree_steps() -> void:
	var pose := Pose.new(0, 0, 7)
	assert_eq(pose.turned(1).yaw, 0)
	assert_eq(pose.turned(-8).yaw, 7)


func test_channel_runs_along_the_heading_up_to_reach() -> void:
	var sim := _sim()
	var park := MachinePark.new()
	var short := MachineSpec.new(&"short", 32, 10, 8, 40, 100_000_000)
	# South of the pile, facing north (+y is heading 2; the machine faces -y = heading 6).
	var pose := Pose.new(SIZE / 2, SIZE + 20, 6)
	assert_eq(Placement.check(sim.grid, Placement.occupied_by(park.placed), short, pose), Placement.Problem.NONE)
	var machine := park.place(sim, short, pose)
	sim.advance_machines(60_000)
	assert_true(machine.dig.done(), "advanced to its reach")
	var front := Placement.front(short, pose)
	assert_eq(front, Vector2i(SIZE / 2, SIZE + 20 - 17))
	for step in range(0, 40):
		var y := front.y - step
		if sim.grid.in_bounds(SIZE / 2, y):
			assert_eq(sim.grid.get_h(SIZE / 2, y), 0, "channel floor at %d" % y)
	var past := front.y - 41
	if sim.grid.in_bounds(SIZE / 2, past):
		assert_gt(sim.grid.get_h(SIZE / 2, past - 20), 0, "hay past the reach")


func test_pick_up_is_free_and_returns_it_to_the_shelf() -> void:
	var sim := _sim()
	var park := MachinePark.new()
	var machine := park.place(sim, spec, Pose.new(-40, -40, 0))
	park.pick_up(sim, machine)
	assert_eq(park.placed.size(), 0)
	assert_eq(park.shelf_count(&"conveyor"), 1)
	assert_false(sim.machines.has(machine.dig))


func test_new_pile_shelves_buried_machines_and_keeps_the_rest() -> void:
	var small := _sim()
	var park := MachinePark.new()
	# Close to the small pile's foot: under hay once the next, bigger pile arrives.
	var near := park.place(small, spec, Pose.new(SIZE / 2, SIZE + 8, 6))
	var far := park.place(small, spec, Pose.new(-60, -60, 1))
	var bigger := PileSim.create(PileSpec.new(3, 512, 24000, 9, 2))
	# The bigger pile is centred on its own grid; shift the old poses by the growth.
	for machine in park.placed:
		machine.pose = Pose.new(machine.pose.x + 128, machine.pose.y + 128, machine.pose.yaw)
	var shelved := park.on_new_pile(bigger)
	assert_true(shelved.has(near), "buried by the bigger pile → shelf")
	assert_true(park.placed.has(far), "still on bare yard → stays")
	assert_eq(park.shelf_count(&"conveyor"), 1)
	assert_eq(bigger.machines.size(), 1, "the kept machine digs the new pile")
