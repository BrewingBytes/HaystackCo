class_name ClockGuard
extends RefCounted
## Time away and the game's day (Game Rules "Offline time", CEO D5, eng D8; G7). Pure: the game
## passes the wall clock (unix seconds) and the local calendar day in.
##
## - Time away is now − last seen, clamped to 0..cap. A clock moved back gives 0 and resets
##   last seen to now.
## - Offline credit per game day is capped (dailyCapMinutes), so moving the clock forward and back
##   can't farm it.
## - The game's day only moves forward (D5). A saved day more than one day ahead of today (a clock
##   that jumped ahead and was fixed) snaps back to today with today's allowances used up (D8):
##   no lockout for an honest player, no fresh allowance for a cheat. That's reported for G12.
## The day's interstitial count lives here too, so G8's 6-a-day cap follows the same day.

const INTERSTITIALS_PER_DAY := 6
const MS_PER_MINUTE := 60_000

var last_seen_unix := 0
var day := 0  # the game's current day (local calendar day number); 0 = not started
var offline_ms_today := 0
var interstitials_today := 0
## Set by the last advance() that snapped a future day back to today (for the event log).
var reanchored := false


## A new game: nothing is owed yet.
func start(now_unix: int, today: int) -> void:
	last_seen_unix = now_unix
	day = today


## Moves the game's day to `today` per D5/D8. Call before reading or spending today's counts.
func advance(today: int) -> void:
	reanchored = false
	if day == 0 or today > day:
		day = today
		offline_ms_today = 0
		interstitials_today = 0
	elif day > today + 1:
		day = today
		reanchored = true
	# today ≤ day ≤ today + 1: the day never moves back, so its counts stand.
	# Counts below zero only come from an edited save: they'd lift the daily caps.
	offline_ms_today = maxi(offline_ms_today, 0)
	interstitials_today = maxi(interstitials_today, 0)
	if reanchored:
		offline_ms_today = 1 << 40  # used up: clamped to the cap where it's read
		interstitials_today = INTERSTITIALS_PER_DAY


## The offline time to credit now, in ms, within the per-visit cap and today's remaining
## allowance; records it against today and moves last seen to now.
func credit(now_unix: int, today: int, cap_minutes: int, daily_cap_minutes: int) -> int:
	advance(today)
	var away_ms := (now_unix - last_seen_unix) * 1000
	last_seen_unix = now_unix
	if away_ms <= 0:
		return 0  # a clock moved back (or no time passed): nothing owed
	var daily_cap_ms := daily_cap_minutes * MS_PER_MINUTE
	offline_ms_today = mini(offline_ms_today, daily_cap_ms)
	var granted := mini(mini(away_ms, cap_minutes * MS_PER_MINUTE), daily_cap_ms - offline_ms_today)
	offline_ms_today += granted
	return granted


## Last seen moves to now without crediting anything (the game was running: pause, save).
func seen(now_unix: int) -> void:
	last_seen_unix = now_unix
