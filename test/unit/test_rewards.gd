extends GutTest
## G8: the rewarded offers' effects (design D16/D17, Game Rules "Offline time") and the
## pile-to-pile step the pile-complete break leads to (re-review D10).

const HOUR := 3600
const DAY := 20_000
const T0 := DAY * 86_400


func _state() -> GameState:
	var state := GameState.new_game(Economy.bundled(), 3, PileSpec.new(2, 128, 8000, 5, 1))
	state.clock.start(T0, DAY)
	return state


func test_two_x_hay_doubles_for_its_play_time_then_stops() -> void:
	var state := _state()
	var units := 7 * state.economy.units_per_hay
	state.grant_boost()
	assert_eq(state.wallet.credit(units), 14)
	state.tick(state.economy.hay_boost_minutes * 60_000 - 1)
	assert_eq(state.wallet.credit(units), 14, "a millisecond left: still double")
	state.tick(1)
	assert_eq(state.boost_ms_left, 0)
	assert_eq(state.wallet.credit(units), 7)


func test_hay_raked_before_the_reward_stays_single() -> void:
	var state := _state()
	var needle := state.sim.needles[0]
	state.sim.brush(SimDefaults.PITCHFORK, needle.x + 20, needle.y, 0, 256)
	var expected := state.sim.collected / state.economy.units_per_hay
	state.grant_boost()
	assert_eq(state.wallet.hay, expected)


func test_two_x_hay_survives_a_save() -> void:
	var state := _state()
	state.grant_boost()
	state.tick(60_000)
	var back: GameState = SaveCodec.decode(SaveCodec.encode(state, T0), Economy.bundled()).state
	assert_eq(back.boost_ms_left, state.economy.hay_boost_minutes * 60_000 - 60_000)
	assert_eq(back.wallet.boost, 2)


func test_time_away_is_never_doubled_by_the_hay_reward() -> void:
	var plain := _state()
	var boosted := _state()
	boosted.grant_boost()
	for state: GameState in [plain, boosted]:
		var needle := state.sim.needles[0]
		state.sim.machines.append(ConveyorDig.new(needle.x, 0, 0, 256, 8, 400, 40_000))
	var a := plain.come_back(T0 + HOUR, DAY)
	var b := boosted.come_back(T0 + HOUR, DAY)
	assert_gt(a.hay, 0)
	assert_eq(b.hay, a.hay)
	assert_eq(boosted.wallet.boost, 2, "the reward still runs afterwards")


func test_next_pile_keeps_machines_on_clear_ground_and_starts_clean() -> void:
	var economy := Economy.bundled()
	var state := GameState.new_game(economy, 3)
	var conveyor := economy.machine(&"conveyor")
	var pose := Placement.nearest_edge_spot(state.sim.grid, state.park.placed, conveyor, Vector2i(0, state.sim.grid.size / 2))
	state.park.place(state.sim, conveyor, pose)
	state.sim.advance_machines(60_000)
	state.credit_hay()
	var hay := state.wallet.hay
	var next := state.make_next_pile()
	assert_eq(next.spec.number, 2)
	assert_eq(next.spec.size, economy.pile_size(2))
	var shelved := state.enter_pile(next)
	assert_eq(state.sim, next)
	assert_eq(state.credited, 0)
	assert_eq(state.wallet.hay, hay, "the wallet carries over")
	assert_eq(state.park.placed.size() + state.park.shelf.size(), 1, "the machine carries over (placed or shelved)")
	assert_eq(state.sim.machines.size(), state.park.placed.size())
	assert_eq(shelved.size(), state.park.shelf.size())
	var back: GameState = SaveCodec.decode(SaveCodec.encode(state, T0), economy).state
	assert_eq(back.sim.spec.number, 2)
	assert_eq(back.sim.grid.digest(), state.sim.grid.digest())
