extends RefCounted
## The simulated default player (Game Rules "Pacing guarantee", design D16, eng D5/D9):
## 4 brush strokes a second along a raster path, always with the best brush it owns (the most
## hay per stroke on fresh hay, from the catalog numbers); it buys the cheapest item it doesn't own the moment it can afford it, and stands
## each machine at the nearest valid edge spot facing the centre. A finished pile goes straight
## to the next one after the pile-done card.
##
## The raster: the pile is tiled into square windows, visited nearest-first from the flank the
## default camera frames (where players rake first). The bot rakes back and forth across the
## current window, one stroke per row, and moves on when a pass over it yields under a quarter of
## its first pass. Pure sim: no Nodes, runs headless.

const STROKE_MS := 250  # 4 strokes a second
const PILE_BREAK_MS := 3000  # the pile-done card and the Next-pile tap
const WINDOW := 64  # cells per side (8 m): one stroke crosses it
const MOVE_ON_PCT := 25  # move to the next window when a pass yields under this share of its first

var economy: Economy
var install_seed: int
var sim: PileSim
var wallet: Wallet
var inventory: Inventory
var park := MachinePark.new()
var now_ms := 0
var pile_number := 0
## Results, in ms of play (-1 = not yet).
var first_needle_ms := -1
var first_machine_ms := -1
var buys: Array = []  # [id, ms]
var piles_completed := 0
var ad_breaks := 0
## The game's interstitial ceilings, with the first session over (eng O3: the report counts
## opportunities for a returning player). Its day is the bot's play time in days.
var ads := AdPolicy.new()
var ad_clock := ClockGuard.new()

var _brush: BrushSpec
var _windows: Array[Vector2i] = []
var _window := 0
var _row := 0
var _pass_yield := 0
var _first_pass_yield := -1


func _init(p_economy: Economy, p_install_seed: int) -> void:
	economy = p_economy
	install_seed = p_install_seed
	ads.first_session = false
	ad_clock.start(0, 1)
	wallet = Wallet.new(economy.units_per_hay)
	inventory = Inventory.starting(economy)
	_pick_brush()


## Plays until `until_ms` or, with `stop_at_first_machine`, until the first machine is bought.
## Pile 1 is the same for every install, so `stop_after_pile` lets a caller fork() at the
## boundary and replay only the piles that depend on the install seed.
func play(until_ms: int, stop_at_first_machine := false, stop_after_pile := 0) -> void:
	if sim == null:
		_next_pile()
	while now_ms < until_ms:
		if stop_at_first_machine and first_machine_ms >= 0:
			return
		if sim.is_complete():
			_pile_done()
			if stop_after_pile > 0 and pile_number >= stop_after_pile:
				return
			_next_pile()
			continue
		if not park.shelf.is_empty():
			_place_shelved()  # the tick after Buy: placement mode, PLACE
		var before := sim.collected
		_stroke()
		var found := sim.advance_machines(STROKE_MS)
		now_ms += STROKE_MS
		_found(found)
		_pass_yield += sim.collected - before
		wallet.credit(sim.collected - before)
		_buy_what_it_can()


## A copy at a pile boundary (after play(..., stop_after_pile)), for another install seed.
func fork(p_install_seed: int) -> RefCounted:
	var bot: RefCounted = get_script().new(economy, p_install_seed)
	bot.now_ms = now_ms
	bot.pile_number = pile_number
	bot.first_needle_ms = first_needle_ms
	bot.first_machine_ms = first_machine_ms
	bot.buys = buys.duplicate()
	bot.piles_completed = piles_completed
	bot.ad_breaks = ad_breaks
	bot.ads.last_pile = ads.last_pile
	bot.ads._last_shown_ms = ads._last_shown_ms
	bot.ad_clock.day = ad_clock.day
	bot.ad_clock.interstitials_today = ad_clock.interstitials_today
	bot.wallet.hay = wallet.hay
	bot.wallet._carry = wallet._carry
	bot.inventory.owned = inventory.owned.duplicate()
	bot.inventory.magnet_tutorial_done = inventory.magnet_tutorial_done
	bot.park.shelf = park.shelf.duplicate()
	for machine in park.placed:
		bot.park.placed.append(MachinePark.Placed.new(machine.spec, machine.pose))
	bot._pick_brush()
	return bot


func _next_pile() -> void:
	pile_number += 1
	sim = PileSim.create(SimDefaults.spec_for(pile_number, install_seed, economy))
	sim.reveal_cell = economy.reveal_cell
	sim.reveal_threshold = economy.reveal_threshold
	park.on_new_pile(sim)
	_place_shelved()
	_windows = _raster_windows(sim.grid.size)
	_window = 0
	_row = 0
	_pass_yield = 0
	_first_pass_yield = -1


func _pile_done() -> void:
	piles_completed += 1
	# PILE_COMPLETE_BREAK (eng D3/D7): the bot taps "Next pile" with no pointer down.
	var day := 1 + now_ms / 86_400_000
	if ads.check(AdPolicy.Moment.PILE_COMPLETE_BREAK, pile_number, first_machine_ms >= 0, false, now_ms, ad_clock, day) == AdPolicy.Verdict.SHOW:
		ads.shown(pile_number, now_ms, ad_clock, day)
		ad_breaks += 1
	now_ms += PILE_BREAK_MS


## One stroke: across the current window along row `_row`, alternating direction.
func _stroke() -> void:
	var rows := maxi(1, WINDOW / _brush.radius)
	var origin := _windows[_window]
	var y := origin.y + _row * _brush.radius + _brush.radius / 2
	var forward := _row % 2 == 0
	var dir_x := 256 if forward else -256
	var spacing := maxi(1, _brush.radius / 2)
	var steps := WINDOW / spacing
	var stamps := PackedInt32Array()
	for i in steps:
		stamps.append(origin.x + (i * spacing if forward else WINDOW - 1 - i * spacing))
		stamps.append(y)
	_found(sim.stroke(_brush, stamps, dir_x, 0))
	_row += 1
	if _row < rows:
		return
	_row = 0
	if _first_pass_yield < 0:
		_first_pass_yield = _pass_yield
	elif _pass_yield * 100 < _first_pass_yield * MOVE_ON_PCT:
		_window = (_window + 1) % _windows.size()
		_first_pass_yield = -1
	_pass_yield = 0


func _found(found: Array[Needle]) -> void:
	if not found.is_empty() and first_needle_ms < 0:
		first_needle_ms = now_ms


func _buy_what_it_can() -> void:
	while true:
		var it := inventory.cheapest_unowned(economy)
		if it == null or not inventory.buy(economy, it.id, wallet, park):
			return
		buys.append([it.id, now_ms])
		if it.machine != null and first_machine_ms < 0:
			first_machine_ms = now_ms
		_pick_brush()


## Every shelved machine goes to the nearest valid edge spot facing the centre (re-review D10).
func _place_shelved() -> void:
	var near := _windows[_window] + Vector2i(WINDOW / 2, WINDOW / 2) if not _windows.is_empty() else Vector2i(sim.grid.size / 2, sim.grid.size)
	for spec: MachineSpec in park.shelf.duplicate():
		var pose := Placement.nearest_edge_spot(sim.grid, park.placed, spec, near)
		if pose == null:
			return
		park.shelf.erase(spec)
		park.place(sim, spec, pose)


func _pick_brush() -> void:
	_brush = null
	var best := -1
	for it in economy.items:
		if it.brush != null and inventory.owns(it.id) and stroke_estimate(it.brush) > best:
			_brush = it.brush
			best = stroke_estimate(it.brush)


## Hay a stroke takes from deep hay, roughly: disc area × depth × the share it keeps (furrows
## and pushing leave some), over the stamp spacing. Only used to rank brushes.
static func stroke_estimate(spec: BrushSpec) -> int:
	var share := 100 if spec.tine_spacing == 0 else (100 + spec.ridge_pct) / 2
	return spec.radius * spec.radius * spec.depth * share * (100 - spec.push_pct) / maxi(1, spec.radius / 2)


## Window corners covering the pile's disc, nearest-first from the default camera's flank
## (pile centre + 55% of the radius toward +y, where pile 1's needle lies).
func _raster_windows(size: int) -> Array[Vector2i]:
	var centre := size / 2
	var radius := (size * 47) / 100
	var flank := Vector2i(centre, centre + (radius * 55) / 100)
	var windows: Array[Vector2i] = []
	var x0 := posmod(flank.x - WINDOW / 2, WINDOW) - WINDOW
	var y0 := posmod(flank.y - WINDOW / 2, WINDOW) - WINDOW
	for wy in range(y0, size, WINDOW):
		for wx in range(x0, size, WINDOW):
			var mid := Vector2i(wx + WINDOW / 2, wy + WINDOW / 2)
			if (mid - Vector2i(centre, centre)).length_squared() <= (radius + WINDOW / 2) * (radius + WINDOW / 2):
				windows.append(Vector2i(wx, wy))
	windows.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a + Vector2i(WINDOW / 2, WINDOW / 2) - flank).length_squared()
		var db := (b + Vector2i(WINDOW / 2, WINDOW / 2) - flank).length_squared()
		return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	return windows
