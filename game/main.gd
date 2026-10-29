extends Node
## Game entry: the yard and its HUD, plus a debug line (engine, a11y values, fps, autoplay
## phase) shown only with `--info` or under autoplay.
## A Game Loop launch (Test Lab, `--ei scenario N`, or `godot -- --scenario=N`) runs Autoplay.
## Normal play loads the save at boot and saves every 30 s, on pause or quit, and when a pile is
## finished (G6); time away is credited at boot and on resume (G7). Consent comes before the
## yard; a finished pile shows its card, and "Next pile" is the one interstitial moment (G8).
## The harnesses (autoplay, --shot, --no-save) never read or write saves and never touch ads.

@onready var _yard: Yard = $Yard
@onready var _info: Label = $Hud/Info

const SAVE_EVERY_S := 30.0
const AD_RESUME_GRACE_MS := 5000  # a resume this soon after an ad closes is that ad's

var _autoplay: Autoplay
var _a11y_line := ""
var _store: SaveStore  # null when this run doesn't persist
var _save_line := ""
var _away_line := ""
var _coming_back := false
var _ads: AdsGate  # null when this run has no ads (the harnesses)
var _card: PileCard
var _offers: DevOffers
var _privacy := false  # Privacy options required (cached: UMP asks the platform)
var _away_hay := 0  # hay from the last time away, while its "2× offline" offer stands
var _pointers := {}  # touch index (mouse: -1) → true while down
var _card_open := false
var _next_task := -1
var _next := {}  # the next pile, built behind the card
## A full-screen ad pauses the app: the resume it causes isn't time away worth an offer.
var _in_ad := false
var _ad_closed_ms := -AD_RESUME_GRACE_MS


func _ready() -> void:
	_refresh_a11y()
	var scenario := GameLoop.scenario()
	var config: Dictionary = SpikeConfig.SCENARIOS.get(scenario, {})
	var grid_size: int = config.get("grid", SpikeConfig.DEFAULT_GRID)
	if not config.is_empty():
		_autoplay = Autoplay.new()
		_autoplay.name = "Autoplay"
		add_child(_autoplay)
		_autoplay.run(scenario, config, _yard)
	Settings.apply()
	_info.text = "Raking the yard…"
	_info.visible = not config.is_empty() or OS.get_cmdline_user_args().has("--info")
	var fixed: bool = config.get("camera", "orbit") == "fixed"
	if config.is_empty() and _user_arg("--shot=").is_empty() and not OS.get_cmdline_user_args().has("--no-save"):
		_add_ads()
		await _ads.resolve_consent()  # design D6: consent first, before the yard
		await _load_or_start(fixed)
		if _yard.sim.is_complete():
			_on_pile_done()  # a pile finished before the save (or offline) still waits on its card
	else:
		await _yard.generate(grid_size, fixed)
	print("[yard] ready")
	var shot := _user_arg("--shot=")
	if not shot.is_empty():
		_screenshot(shot, OS.get_cmdline_user_args().has("--rake"))


## Boot: the save if there is one (backup if the primary is bad; a newer app's save is left
## alone and this session doesn't save), else a new game. Notices go to the HUD's notice line.
func _load_or_start(fixed: bool) -> void:
	_store = SaveStore.new()
	var economy := _yard.economy
	var loaded := {}  # filled in place: a lambda can't reassign a captured variable
	var now := int(Time.get_unix_time_from_system())
	var today := _today()
	await _yard.start_from(func() -> GameState:
		loaded.merge(_store.load_state(economy))
		if loaded.state != null:
			loaded.away = loaded.state.come_back(now, today)
			return loaded.state
		var state := GameState.new_game(economy, GameState.random_install_seed())
		state.clock.start(now, today)
		return state, fixed)
	if loaded.has("away"):
		_report_away(loaded.away)
		_away_hay = loaded.away.hay
	var hud := _yard.hud
	match loaded.notice:
		SaveStore.Notice.RESTORED:
			_save_line = "Restored your last save"
			hud.notice(_save_line)
		SaveStore.Notice.FRESH:
			_save_line = "Couldn't load your save, starting fresh"
			hud.notice(_save_line, YardHud.NoticeKind.WARNING)
		SaveStore.Notice.UPDATE_REQUIRED:
			# G9c turns this into the Update required screen.
			_save_line = "Update required: this save is from a newer version"
			hud.notice(_save_line, YardHud.NoticeKind.WARNING, true)
	if loaded.notice != SaveStore.Notice.NONE:
		print("[save] %s (%s)" % [_save_line, loaded.detail])
	print("[save] %s, install seed %d" % ["loaded" if loaded.state != null else "new game", _yard.state.install_seed])
	var timer := Timer.new()
	timer.wait_time = SAVE_EVERY_S
	timer.timeout.connect(_save)
	add_child(timer)
	timer.start()
	_yard.needles_found.connect(func(_found: Array[Needle]) -> void:
		if _yard.sim.is_complete():
			_save()
			_on_pile_done())


## Back from the background: machines dig through the time away, with the yard held still.
func _resume() -> void:
	if _store == null or _yard.state == null or _coming_back:
		return
	_coming_back = true
	_yard.hold(true)
	var state := _yard.state
	var now := int(Time.get_unix_time_from_system())
	var today := _today()
	state.ads.came_back(maxi(0, now - state.clock.last_seen_unix) * 1000)
	var away := {}
	var task := WorkerThreadPool.add_task(func() -> void: away.merge(state.come_back(now, today)), true, "come_back")
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_yard.hold(false)
	_coming_back = false
	_report_away(away)
	if not _in_ad and Time.get_ticks_msec() - _ad_closed_ms >= AD_RESUME_GRACE_MS:
		_away_hay = away.hay
	_yard._on_found(away.found)  # draws them; a finished pile saves through needles_found
	_save()


## G9c's away sheet shows this; for now, the log and a notice.
func _report_away(away: Dictionary) -> void:
	if _nothing_owed(away):
		return
	_away_line = "Away: +%d hay from %d min of digging%s%s" % [away.hay, away.used_ms / 60_000, " (capped)" if away.capped else "", ", pile finished" if away.pile_done else ""]
	_yard.hud.notice(_away_line)
	print("[away] %s; %d min owed, %d needles found" % [_away_line, away.owed_ms / 60_000, away.found.size()])
	if _yard.state.clock.reanchored:
		push_warning("[clock] the saved day was ahead of today: re-anchored with today's allowances used")


static func _nothing_owed(away: Dictionary) -> bool:
	return away.owed_ms == 0 and away.hay == 0 and away.found.is_empty()


## The local calendar day number (CEO D5: the day the caps count against).
static func _today() -> int:
	var bias_s: int = Time.get_time_zone_from_system().bias * 60
	return int(floor((Time.get_unix_time_from_system() + bias_s) / 86400.0))


func _save() -> void:
	# Not persisting, a newer app's save, still loading, or machines catching up on a worker
	# thread (the pile is changing under it; the resume saves when it's done).
	if _store == null or not _store.writable or _yard.state == null or _coming_back:
		return
	var started := Time.get_ticks_usec()
	var error := _yard.save_to(_store)
	if error == OK:
		if not _save_line.is_empty():
			_yard.hud.clear_sticky()
		_save_line = ""
		print("[save] saved in %.1f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	else:
		# Disk full and the like: the last good files stay; the next save tries again. The
		# notice stays until a save works.
		_save_line = "Couldn't save (%s)" % error_string(error)
		push_warning("[save] " + _save_line)
		_yard.hud.notice("Storage is full, progress isn't saving", YardHud.NoticeKind.WARNING, true)


func _process(_delta: float) -> void:
	if _yard.grid == null:
		return
	var lines := PackedStringArray([
		"%d fps · %s · grid %d" % [Engine.get_frames_per_second(), RenderingServer.get_current_rendering_method(), _yard.grid.size],
		"pile %d · tool %s%s · hay %d%s · needles %d/%d" % [_yard.sim.spec.number, _yard.tool, " %d" % _yard.detector_strength if _yard.tool == &"detector" else "", _yard.wallet.hay, _boost_text(), _yard.sim.needles.filter(func(n: Needle) -> bool: return n.found).size(), _yard.sim.needles.size()],
		_a11y_line,
	])
	if not _save_line.is_empty():
		lines.append(_save_line)
	if not _away_line.is_empty():
		lines.append(_away_line)
	if _autoplay:
		lines.append("autoplay: " + _autoplay.status)
	_info.text = "\n".join(lines)
	if _ads != null:
		var live := _ads.offers_visible() and not _card_open and not _coming_back
		_offers.refresh(live and _yard.state.boost_ms_left == 0, _away_hay if live else 0, _privacy)
		_yard.hud.set_ping_visible(live and _yard.tool == &"detector" and _yard.can_ping())


## The HUD rate's "2× m:ss" while the 2× hay reward runs (design D17; G9 moves it to the rate).
func _boost_text() -> String:
	var left := _yard.state.boost_ms_left if _yard.state != null else 0
	if left <= 0:
		return ""
	var s := ceili(left / 1000.0)
	return " · 2× %d:%02d" % [s / 60, s % 60]


# --- Ads (G8) ----------------------------------------------------------------------------

func _add_ads() -> void:
	_ads = AdsGate.new()
	_ads.name = "Ads"
	add_child(_ads)
	_ads.offers_changed.connect(func() -> void: _privacy = _ads.privacy_options_required())
	_card = PileCard.new()
	add_child(_card)
	_card.next_pressed.connect(_on_next_pressed)
	_offers = DevOffers.new()
	add_child(_offers)
	_offers.double_hay_pressed.connect(_on_double_hay)
	_offers.double_away_pressed.connect(_on_double_away)
	_offers.privacy_pressed.connect(func() -> void: await _ads.show_privacy_options())
	_yard.hud.ping_pressed.connect(_on_ping)


## The pile is done (eng D7): its card, with pile n+1 generating behind it. The yard holds
## still (machines idle, leftover hay stays) until "Next pile".
func _on_pile_done() -> void:
	if _card_open or _card == null:
		return
	_card_open = true
	var state := _yard.state
	_yard.pile.upload_dirty()  # the last stroke shows behind the card
	_yard.cancel_placement()
	_yard.hud.shop.close()
	_yard.hold(true)
	var next := {}
	_next = next
	_next_task = WorkerThreadPool.add_task(func() -> void: next.sim = state.make_next_pile(), true, "next_pile")
	_card.show_for(state.sim.spec.number, state.sim.collected / state.economy.units_per_hay, state.sim.needles.filter(func(n: Needle) -> bool: return n.found and not n.tutorial).size())
	print("[pile] pile %d done; pile %d generating" % [state.sim.spec.number, state.sim.spec.number + 1])


## "Next pile": the one interstitial moment (eng D3/D7), checked now with no pointer down, then
## pile n+1. "Loading…" covers the ad wait (≤ 3 s) and the rest of the generation.
func _on_next_pressed() -> void:
	var state := _yard.state
	var pile := state.sim.spec.number
	_card.set_loading(true)
	var verdict := state.ads.check(AdPolicy.Moment.PILE_COMPLETE_BREAK, pile, state.owns_machine(), not _pointers.is_empty(), Time.get_ticks_msec(), state.clock, _today())
	print("[ads] pile %d break: %s" % [pile, AdPolicy.Verdict.keys()[verdict].to_lower()])
	if verdict == AdPolicy.Verdict.SHOW:
		_in_ad = true
		var shown := await _ads.show_interstitial()
		await _ad_closed()
		if shown:
			state.ads.shown(pile, Time.get_ticks_msec(), state.clock, _today())
	while not WorkerThreadPool.is_task_completed(_next_task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(_next_task)
	var shelved := state.enter_pile(_next.sim)
	_next = {}
	_yard.show_pile(state)
	_card.visible = false
	_card_open = false
	_yard.hold(false)
	print("[pile] pile %d (%d cells); %d machines back on the shelf" % [state.sim.spec.number, state.sim.grid.size, shelved.size()])
	_save()


func _on_double_hay() -> void:
	if await _watch():
		_yard.state.grant_boost()
		_save()


## "2× offline" doubles the hay from the time away, never the needles (Game Rules).
func _on_double_away() -> void:
	var hay := _away_hay
	_away_hay = 0
	if await _watch():
		_yard.wallet.hay += hay
		print("[ads] 2× offline: +%d hay" % hay)
		_save()
	else:
		_away_hay = hay


func _on_ping() -> void:
	if await _watch():
		_yard.ping()


## Shows a rewarded ad; true only if the reward was earned.
func _watch() -> bool:
	if not _ads.offers_visible():
		return false  # gone since the button showed: nothing to watch, no 2 min block
	_in_ad = true
	var earned := await _ads.show_rewarded()
	await _ad_closed()
	_yard.state.ads.rewarded(Time.get_ticks_msec())
	return earned


## After a full-screen ad: the resume it caused may still be catching machines up on a worker
## thread, so the ad's result (hay, a new pile) waits for it before touching the state.
func _ad_closed() -> void:
	while _coming_back:
		await get_tree().process_frame
	_in_ad = false
	_ad_closed_ms = Time.get_ticks_msec()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_pointers[event.index] = true
		else:
			_pointers.erase(event.index)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointers[-1] = true
		else:
			_pointers.erase(-1)


## Dev hook for judging the look on desktop: `godot -- --shot=/tmp/a.png [--rake] [--trench] [--zoom=F]`.
## --trench places four conveyors and fast-forwards them two hours; --dig-needle digs pile 1's needle
## out; --place opens placement mode; --placed also presses PLACE and lets it dig a second;
## --label then taps it (its label shows); --shop opens the Shop with 6,000 hay and a shelved conveyor.
func _screenshot(path: String, rake: bool) -> void:
	if OS.get_cmdline_user_args().has("--trench"):
		_yard.place_conveyors(4, 0.0)
		OfflineSim.fast_forward(_yard.grid, _yard.conveyors, 2 * 60 * 60 * 1000)
		_yard.clear_conveyors()
		_yard.place_conveyors(4, 0.0)  # the machines again, without the dig state
		_yard.conveyors.clear()
	if OS.get_cmdline_user_args().has("--dig-needle"):
		# Pitchfork straight down on pile 1's needle until it's found, then look at it.
		var needle := _yard.sim.needles[0]
		while not needle.found:
			_yard._on_found(_yard.sim.brush(SimDefaults.PITCHFORK, needle.x, needle.y, 0, 256))
		var half := _yard.grid.size * 0.5
		_yard.camera.focus = Vector3((needle.x - half) * SpikeConfig.CELL_M, needle.z * SpikeConfig.HEIGHT_UNIT_M, (needle.y - half) * SpikeConfig.CELL_M)
		_yard.camera.set_view(0.3, deg_to_rad(40.0), 3.0)
	if OS.get_cmdline_user_args().has("--place") or OS.get_cmdline_user_args().has("--placed"):
		_yard.give_and_place(SimDefaults.CONVEYOR)
		var spot := _yard.placing.pose
		var half := _yard.grid.size * 0.5
		_yard.camera.focus = Vector3((spot.x - half) * SpikeConfig.CELL_M, 1.0, (spot.y - half) * SpikeConfig.CELL_M)
		_yard.camera.set_view(_yard.camera.yaw + 0.6, deg_to_rad(35.0), 14.0)
		if OS.get_cmdline_user_args().has("--placed"):
			for i in 5:
				await get_tree().process_frame
			_yard._on_place_pressed()
			for i in 60:
				await get_tree().process_frame
			if OS.get_cmdline_user_args().has("--label"):
				var machine: MachinePark.Placed = _yard.park.placed[0]
				_yard.tap(_yard.camera.unproject_position(Vector3((machine.pose.x - half) * SpikeConfig.CELL_M, 0.0, (machine.pose.y - half) * SpikeConfig.CELL_M)))
	if OS.get_cmdline_user_args().has("--shop"):
		_yard.wallet.credit(6000 * _yard.economy.units_per_hay)
		_yard.park.buy(SimDefaults.CONVEYOR)
		_yard.open_shop()
	var zoom := _user_arg("--zoom=")
	if not zoom.is_empty():
		_yard.camera.zoom(zoom.to_float())
	for i in 30:
		await get_tree().process_frame
	if rake:
		var size := get_viewport().get_visible_rect().size
		for line in 6:
			for step in 40:
				var x := lerpf(0.15, 0.85, step / 39.0)
				_yard.use_tool_at(Vector2(x, 0.55 + line * 0.05) * size)
				await get_tree().process_frame
			_yard.end_stroke()
	for i in 10:
		await get_tree().process_frame
	_info.visible = OS.get_cmdline_user_args().has("--info")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _user_arg(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_refresh_a11y()
		_resume()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_pointers.clear()
		_away_hay = 0  # the away sheet's offer stands until the player leaves again
		_save()


func _refresh_a11y() -> void:
	var lines := PackedStringArray([
		"HAYSTACK CO.",
		"Godot %s" % Engine.get_version_info().string,
		"font scale %.2f" % A11y.font_scale(),
		"reduce motion %s" % A11y.system_reduce_motion(),
		"screen reader %s" % A11y.screen_reader_on(),
	])
	_a11y_line = "font %.2f · reduce motion %s · screen reader %s" % [A11y.font_scale(), A11y.system_reduce_motion(), A11y.screen_reader_on()]
	print("[a11y] ", " | ".join(lines))
