class_name AdPolicy
extends RefCounted
## When an interstitial may show (Game Rules "Interstitial policy", eng D3/D7, Gemmory's AdPolicy
## adapted; G8). Pure: the game passes the session clock (monotonic ms), the pile, whether a
## pointer is down and the clock guard (whose day only moves forward, CEO D5).
##
## The only moment is the pile-complete break, checked on the "Next pile" tap. Ceilings, all
## hard-coded (a catalog may only tighten them): none in the first session, none before the
## first machine, none with a pointer down, 1 per pile, 6 per day, at least 4 min apart and
## 2 min after a rewarded ad.

enum Moment { PILE_COMPLETE_BREAK, OTHER }
enum Verdict {
	SHOW,
	WRONG_MOMENT,
	POINTER_DOWN,
	FIRST_SESSION,
	NO_MACHINE_YET,
	PILE_HAD_ONE,
	DAILY_CAP,
	TOO_SOON,
	AFTER_REWARDED,
}

const SPACING_MS := 4 * 60_000
const AFTER_REWARDED_MS := 2 * 60_000
## Gemmory's first session ends on a later cold start or on coming back after this long away.
const FIRST_SESSION_AWAY_MS := 30 * 60_000

## True from a new game until the next cold start (a loaded save) or a long absence.
var first_session := true
var last_pile := 0  # the pile the last interstitial followed (saved)
var _last_shown_ms := -1  # session clock; -1 = none this session
var _last_rewarded_ms := -1


## Whether an interstitial may show now. `today` moves the clock guard's day first.
func check(moment: Moment, pile: int, owns_machine: bool, pointer_down: bool, now_ms: int, clock: ClockGuard, today: int) -> Verdict:
	if moment != Moment.PILE_COMPLETE_BREAK:
		return Verdict.WRONG_MOMENT
	if pointer_down:
		return Verdict.POINTER_DOWN
	if first_session:
		return Verdict.FIRST_SESSION
	if not owns_machine:
		return Verdict.NO_MACHINE_YET
	if pile == last_pile:
		return Verdict.PILE_HAD_ONE
	clock.advance(today)
	if clock.interstitials_today >= ClockGuard.INTERSTITIALS_PER_DAY:
		return Verdict.DAILY_CAP
	if _last_shown_ms >= 0 and now_ms - _last_shown_ms < SPACING_MS:
		return Verdict.TOO_SOON
	if _last_rewarded_ms >= 0 and now_ms - _last_rewarded_ms < AFTER_REWARDED_MS:
		return Verdict.AFTER_REWARDED
	return Verdict.SHOW


## An interstitial showed after `pile`.
func shown(pile: int, now_ms: int, clock: ClockGuard, today: int) -> void:
	clock.advance(today)
	clock.interstitials_today += 1
	last_pile = pile
	_last_shown_ms = now_ms


## A rewarded ad finished (earned or not).
func rewarded(now_ms: int) -> void:
	_last_rewarded_ms = now_ms


## Back from the background after `away_ms`.
func came_back(away_ms: int) -> void:
	if away_ms >= FIRST_SESSION_AWAY_MS:
		first_session = false
