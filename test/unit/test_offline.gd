extends GutTest
## G7: time away (Game Rules "Offline time", CEO D5/D8, eng D8 ForwardDay) and offline digging
## within the current pile (CUT-OFFX).

const HOUR := 3600
const MIN_MS := 60_000
const CAP := 480  # minutes per visit (catalog default)
const DAILY := 720  # minutes per day
const DAY := 20_000  # an arbitrary calendar day number
const T0 := DAY * 86_400 + 9 * HOUR  # 09:00 that day


func _clock() -> ClockGuard:
	var clock := ClockGuard.new()
	clock.start(T0, DAY)
	return clock


# --- Clock guard -------------------------------------------------------------------------

func test_negative_zero_at_and_past_the_cap() -> void:
	var clock := _clock()
	assert_eq(clock.credit(T0 - HOUR, DAY, CAP, DAILY), 0, "clock moved back: nothing owed")
	assert_eq(clock.last_seen_unix, T0 - HOUR, "and last seen resets to now")
	assert_eq(clock.credit(T0 - HOUR, DAY, CAP, DAILY), 0, "no time passed")
	clock = _clock()
	assert_eq(clock.credit(T0 + 8 * HOUR, DAY, CAP, DAILY), CAP * MIN_MS, "exactly the cap")
	clock = _clock()
	assert_eq(clock.credit(T0 + 2 * HOUR, DAY + 1, CAP, DAILY), 2 * HOUR * 1000)
	assert_eq(clock.credit(T0 + 2 * HOUR + 20 * HOUR, DAY + 1, CAP, DAILY), CAP * MIN_MS, "20 h away: the cap")


func test_daily_cap_spans_visits() -> void:
	var clock := ClockGuard.new()
	clock.start(DAY * 86_400, DAY)
	var t := DAY * 86_400
	var credited: Array[int] = []
	for visit in 3:
		t += 8 * HOUR  # 8 h away three times, all on DAY + 1's allowance below
		credited.append(clock.credit(t, DAY + 1, CAP, DAILY))
	assert_eq(credited, [8 * HOUR * 1000, 4 * HOUR * 1000, 0] as Array[int])
	assert_eq(clock.credit(t + 8 * HOUR, DAY + 2, CAP, DAILY), 8 * HOUR * 1000, "a new day, a new allowance")


# Found by /qa on 2026-10-28: an edited save with negative counts lifted the daily caps.
func test_negative_counts_from_a_save_dont_lift_the_daily_cap() -> void:
	var clock := _clock()
	clock.offline_ms_today = -1_000_000_000_000
	clock.interstitials_today = -50
	var credited := 0
	for visit in 3:
		credited += clock.credit(T0 + (visit + 1) * 8 * HOUR, DAY, CAP, DAILY)
	assert_eq(credited, DAILY * MIN_MS)
	assert_eq(clock.interstitials_today, 0)


func test_clock_back_a_day_gives_no_fresh_allowance() -> void:
	var clock := _clock()
	clock.credit(T0 + 8 * HOUR, DAY, CAP, DAILY)
	clock.credit(T0 + 12 * HOUR, DAY, CAP, DAILY)  # 12 h used today
	assert_eq(clock.offline_ms_today, DAILY * MIN_MS)
	clock.advance(DAY - 1)  # set back a day
	assert_eq(clock.day, DAY, "the day never moves back")
	assert_eq(clock.offline_ms_today, DAILY * MIN_MS, "today's use stands")
	assert_eq(clock.credit(T0 + 30 * HOUR - 86_400, DAY - 1, CAP, DAILY), 0)


func test_forward_and_back_within_a_day_keeps_the_caps() -> void:
	var clock := _clock()
	clock.credit(T0 + 8 * HOUR, DAY + 1, CAP, DAILY)  # clock set to tomorrow: tomorrow's allowance
	clock.interstitials_today = 2
	clock.advance(DAY)  # back to the real today
	assert_eq(clock.day, DAY + 1, "within one day ahead: the day stays")
	assert_eq(clock.offline_ms_today, 8 * HOUR * 1000)
	assert_eq(clock.interstitials_today, 2)
	assert_false(clock.reanchored)


func test_forward_a_year_then_back_resumes_the_next_real_day() -> void:
	var clock := _clock()
	clock.credit(T0 + 365 * 86_400, DAY + 365, CAP, DAILY)  # clock a year ahead (one allowance, D8)
	assert_eq(clock.day, DAY + 365)
	var back := T0 + 2 * HOUR
	assert_eq(clock.credit(back, DAY, CAP, DAILY), 0, "clock fixed: nothing more today")
	assert_true(clock.reanchored)
	assert_eq(clock.day, DAY, "re-anchored to the real day, not locked out for a year")
	assert_eq(clock.interstitials_today, ClockGuard.INTERSTITIALS_PER_DAY, "today's ads used up too")
	var next_day := back + 86_400
	assert_eq(clock.credit(next_day, DAY + 1, CAP, DAILY), CAP * MIN_MS, "the next real day pays again")
	assert_false(clock.reanchored)


# --- Offline digging -----------------------------------------------------------------------

## A 128 pile whose one needle sits in a conveyor's path.
func _state_with_conveyor(reach := 400) -> GameState:
	var economy := Economy.bundled()
	var state := GameState.new_game(economy, 3, PileSpec.new(2, 128, 8000, 5, 1))
	var needle := state.sim.needles[0]
	state.sim.machines.append(ConveyorDig.new(needle.x, 0, 0, 256, 8, reach, 40_000))
	state.clock.start(T0, DAY)
	return state


func test_offline_stops_when_the_pile_is_complete() -> void:
	var state := _state_with_conveyor()
	var away := state.come_back(T0 + 8 * HOUR, DAY)
	assert_eq(away.owed_ms, CAP * MIN_MS)
	assert_true(away.pile_done)
	assert_lt(away.used_ms, away.owed_ms, "the rest of the time isn't spent")
	assert_eq(away.found.size(), 1)
	assert_eq(away.found[0].source, Needle.Source.OFFLINE)
	assert_true(state.sim.mass_balanced())
	var digest := state.sim.grid.digest()
	var again := state.come_back(T0 + 16 * HOUR, DAY + 1)
	assert_eq(again.used_ms, 0, "a finished pile digs no more offline")
	assert_eq(state.sim.grid.digest(), digest)


func test_offline_stops_when_every_machine_is_done() -> void:
	var state := _state_with_conveyor(10)  # reaches 10 cells: done long before the needle
	var away := state.come_back(T0 + 8 * HOUR, DAY)
	assert_false(away.pile_done)
	assert_true(state.sim.machines[0].done())
	assert_lt(away.used_ms, away.owed_ms, "nothing left to dig: the rest of the time isn't stepped through")


func test_hay_from_time_away_is_credited_once() -> void:
	var state := _state_with_conveyor()
	var away := state.come_back(T0 + HOUR, DAY)
	assert_gt(away.hay, 0)
	assert_eq(state.wallet.hay, away.hay)
	assert_eq(state.credit_hay(), 0, "the yard's next credit finds nothing new")


func test_coming_back_is_deterministic() -> void:
	var digests := []
	for run in 2:
		var bytes := SaveCodec.encode(_state_with_conveyor(), T0)
		var state: GameState = SaveCodec.decode(bytes, Economy.bundled()).state
		var away := state.come_back(T0 + 3 * HOUR + 1234, DAY)
		digests.append([state.sim.grid.digest(), away.hay, away.used_ms])
	assert_eq(digests[0], digests[1])


func test_clock_survives_a_save() -> void:
	var state := _state_with_conveyor()
	state.come_back(T0 + 5 * HOUR, DAY)
	state.clock.interstitials_today = 3
	var back: GameState = SaveCodec.decode(SaveCodec.encode(state, T0 + 5 * HOUR), Economy.bundled()).state
	var c := back.clock
	assert_eq([c.last_seen_unix, c.day, c.offline_ms_today, c.interstitials_today], [T0 + 5 * HOUR, DAY, 5 * HOUR * 1000, 3])
	assert_eq(back.credited, back.sim.collected)


func test_a_save_from_before_the_clock_counts_from_when_it_was_saved() -> void:
	var state := _state_with_conveyor()
	var bytes := SaveCodec.encode(state, T0)
	# Rebuild the same save without its "clock" entry, as G6 wrote it.
	var json_size := bytes.decode_u32(SaveCodec.HEADER)
	var start := SaveCodec.HEADER + 4
	var meta: Dictionary = JSON.parse_string(bytes.slice(start, start + json_size).get_string_from_utf8())
	meta.erase("clock")
	var json := JSON.stringify(meta).to_utf8_buffer()
	var body := PackedByteArray([0, 0, 0, 0])
	body.encode_u32(0, json.size())
	body.append_array(json)
	body.append_array(bytes.slice(start + json_size, bytes.size() - SaveCodec.HASH))
	var out := bytes.slice(0, SaveCodec.HEADER)
	out.encode_u32(6, body.size())
	out.append_array(body)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(out)
	out.append_array(ctx.finish())
	var back: GameState = SaveCodec.decode(out, Economy.bundled()).state
	assert_eq(back.clock.last_seen_unix, T0)
	assert_eq(back.come_back(T0 + HOUR, DAY).owed_ms, HOUR * 1000)


func test_eight_hours_on_the_biggest_pile_reports_its_time() -> void:
	# The budget (< 500 ms) is checked on the emulator; this prints the desktop figure.
	var economy := Economy.bundled()
	var state := GameState.new_game(economy, 3, PileSpec.new(5, 1024, SimDefaults.peak_for(1024), 9, 4))
	var conveyor := economy.machine(&"conveyor")
	for heading in 4:
		var pose := Placement.nearest_edge_spot(state.sim.grid, state.park.placed, conveyor, Vector2i(512 + (heading % 2) * 400 - 200, 512 + (heading / 2) * 400 - 200))
		state.park.place(state.sim, conveyor, pose)
	state.clock.start(T0, DAY)
	var started := Time.get_ticks_usec()
	var away := state.come_back(T0 + 8 * HOUR, DAY)
	gut.p("8 h away, 1024 pile, 4 conveyors: %.1f ms, %d min used, +%d hay" % [(Time.get_ticks_usec() - started) / 1000.0, away.used_ms / MIN_MS, away.hay])
	assert_true(state.sim.mass_balanced())
