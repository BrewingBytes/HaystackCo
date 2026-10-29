extends GutTest
## G8: interstitial ceilings (Game Rules "Interstitial policy", eng D3/D7). One test per ceiling;
## the "Next pile" tap is the only moment.

const V := AdPolicy.Verdict
const BREAK := AdPolicy.Moment.PILE_COMPLETE_BREAK
const DAY := 20_000
const MIN := 60_000

var policy: AdPolicy
var clock: ClockGuard


func before_each() -> void:
	policy = AdPolicy.new()
	policy.first_session = false
	clock = ClockGuard.new()
	clock.start(DAY * 86_400, DAY)


## The verdict for the break after `pile` at `now_ms`, with a machine and no pointer down.
func _at(pile: int, now_ms: int, today := DAY) -> AdPolicy.Verdict:
	return policy.check(BREAK, pile, true, false, now_ms, clock, today)


func test_shows_at_the_pile_break_when_every_ceiling_passes() -> void:
	assert_eq(_at(2, 0), V.SHOW)


func test_only_the_next_pile_tap_is_a_moment() -> void:
	assert_eq(policy.check(AdPolicy.Moment.OTHER, 2, true, false, 0, clock, DAY), V.WRONG_MOMENT)


func test_never_with_a_pointer_down() -> void:
	assert_eq(policy.check(BREAK, 2, true, true, 0, clock, DAY), V.POINTER_DOWN)


func test_none_in_the_first_session() -> void:
	policy.first_session = true
	assert_eq(_at(2, 0), V.FIRST_SESSION)
	policy.came_back(29 * MIN)
	assert_eq(_at(2, 0), V.FIRST_SESSION, "under 30 min away: still the first session")
	policy.came_back(30 * MIN)
	assert_eq(_at(2, 0), V.SHOW, "30 min away ends it (Gemmory's definition)")


func test_none_before_the_first_machine() -> void:
	assert_eq(policy.check(BREAK, 2, false, false, 0, clock, DAY), V.NO_MACHINE_YET)


func test_one_per_pile() -> void:
	policy.shown(2, 0, clock, DAY)
	assert_eq(_at(2, 10 * MIN), V.PILE_HAD_ONE)
	assert_eq(_at(3, 10 * MIN), V.SHOW)


func test_at_least_four_minutes_apart() -> void:
	policy.shown(2, 0, clock, DAY)
	assert_eq(_at(3, 4 * MIN - 1), V.TOO_SOON)
	assert_eq(_at(3, 4 * MIN), V.SHOW)


func test_two_minutes_after_a_rewarded_ad() -> void:
	policy.rewarded(10 * MIN)
	assert_eq(_at(2, 12 * MIN - 1), V.AFTER_REWARDED)
	assert_eq(_at(2, 12 * MIN), V.SHOW)


func test_six_a_day_on_the_forward_only_day() -> void:
	for i in 6:
		assert_eq(_at(10 + i, i * 5 * MIN), V.SHOW)
		policy.shown(10 + i, i * 5 * MIN, clock, DAY)
	assert_eq(_at(20, 60 * MIN), V.DAILY_CAP)
	assert_eq(_at(20, 60 * MIN, DAY - 1), V.DAILY_CAP, "clock set back a day: the cap stands")
	assert_eq(_at(20, 60 * MIN, DAY + 1), V.SHOW, "the next day")


func test_the_daily_count_survives_a_save() -> void:
	var state := GameState.new_game(Economy.bundled(), 3, PileSpec.new(2, 128, 8000, 5, 1))
	state.clock.start(DAY * 86_400, DAY)
	state.ads.shown(4, 0, state.clock, DAY)
	var back: GameState = SaveCodec.decode(SaveCodec.encode(state, DAY * 86_400), Economy.bundled()).state
	assert_eq(back.clock.interstitials_today, 1)
	assert_eq(back.ads.last_pile, 4)
	assert_false(back.ads.first_session, "a loaded save is a later cold start")
