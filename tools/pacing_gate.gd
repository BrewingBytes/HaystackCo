extends RefCounted
## checkPacing (CEO D12, eng D5/D9): plays the pacing bot against an economy and checks the
## targets. Pile 1's needle within 60 s on its fixed seed; the first machine within 10 min, the
## worst case over the install seeds. Also reports piles and ad breaks per hour over a 60-minute
## session (report only, eng D9).

const Bot := preload("res://tools/pacing_bot.gd")
const FIRST_NEEDLE_MAX_MS := 60_000
const FIRST_MACHINE_MAX_MS := 10 * 60_000
const REPORT_MS := 60 * 60_000


## { ok: bool, lines: Array[String], first_needle_ms, worst_machine_ms, worst_seed }.
## Install seeds 1..`seeds`; `report` adds the 60-minute session.
static func run(economy: Economy, seeds: int, report := true) -> Dictionary:
	# Pile 1 is the same for every install: play it once, then fork per install seed.
	var start := Bot.new(economy, 0)
	start.play(FIRST_MACHINE_MAX_MS + 1, true, 1)
	# Sequential: the native stroke copies the grid, and threads only fight over the allocator
	# (measured slower on 3 threads than on 1).
	var machine_ms: Array[int] = []
	for i in seeds:
		if start.first_machine_ms < 0 and start.piles_completed == 0:
			machine_ms.append(FIRST_MACHINE_MAX_MS + 1)  # pile 1 never finished: no later pile to play
			continue
		var bot: RefCounted = start
		if start.first_machine_ms < 0:
			bot = start.fork(i + 1)
			bot.play(FIRST_MACHINE_MAX_MS + 1, true)
		machine_ms.append(bot.first_machine_ms if bot.first_machine_ms >= 0 else FIRST_MACHINE_MAX_MS + 1)
	var worst := 0
	for i in seeds:
		if machine_ms[i] > machine_ms[worst]:
			worst = i
	var sorted := machine_ms.duplicate()
	sorted.sort()
	var needle_ok: bool = start.first_needle_ms >= 0 and start.first_needle_ms <= FIRST_NEEDLE_MAX_MS
	var machine_ok: bool = machine_ms[worst] <= FIRST_MACHINE_MAX_MS
	var lines: Array[String] = []
	lines.append("economyVersion %d, %d install seeds" % [economy.economy_version, seeds])
	lines.append("%s first needle (pile 1): %s (≤ %s)" % [_mark(needle_ok), _time(start.first_needle_ms), _time(FIRST_NEEDLE_MAX_MS)])
	lines.append("%s first machine: worst %s (seed %d), median %s, best %s (≤ %s)" % [_mark(machine_ok), _time(machine_ms[worst]),
			worst + 1, _time(sorted[seeds / 2]), _time(sorted[0]), _time(FIRST_MACHINE_MAX_MS)])
	if report:
		var session := Bot.new(economy, 1)
		session.play(REPORT_MS)
		var buys := ", ".join(session.buys.map(func(b: Array) -> String: return "%s %s" % [b[0], _time(b[1])]))
		lines.append("  buys (seed 1): %s" % buys)
		lines.append("  60-min session (seed 1): %d piles/hour, %d ad breaks/hour (AdPolicy ceilings, first session over), %d hay left" % [
				session.piles_completed, session.ad_breaks, session.wallet.hay])
	return {ok = needle_ok and machine_ok, lines = lines, first_needle_ms = start.first_needle_ms, worst_machine_ms = machine_ms[worst], worst_seed = worst + 1}


static func _mark(ok: bool) -> String:
	return "PASS" if ok else "FAIL"


## m:ss. A run stops just past the machine limit, so anything past it didn't happen in time.
static func _time(ms: int) -> String:
	if ms < 0:
		return "never"
	if ms > FIRST_MACHINE_MAX_MS:
		return "not within %s" % _time(FIRST_MACHINE_MAX_MS)
	return "%d:%02d" % [ms / 60_000, (ms / 1000) % 60]
