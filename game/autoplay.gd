class_name Autoplay
extends Node
## G2 frame harness. Plays scripted phases (orbit, rake, conveyor) on the real yard and logs
## every frame. Pass line: a missed frame is an interval > 1.5 × the frame period; ≤ 5% missed
## per phase. A warm-up runs every phase first; hitches there are shader compiles, logged apart.
## Writes user://frames.jsonl and user://spike_results.json, and the Test Lab results file.

## While true the game shows no ads (G8 checks this).
static var active := false

const MISSED_FACTOR := 1.5
const PASS_MISSED_PCT := 5.0
const HITCH_FACTOR := 4.0
const MAX_HITCHES_LOGGED := 20
const WARMUP_SLICE_S := 20.0
const PHASES: Array[String] = ["orbit", "rake", "conveyor"]
const OFFLINE_MS := 8 * 60 * 60 * 1000
const CONVEYOR_PHASE_SPEED := 60
const TIMING_REPEATS := 100

var yard: Yard
var status := "generating"

var _config: Dictionary
var _scenario := 0
var _period_ms := 1000.0 / 60.0
var _state := "waiting"
var _phase_index := 0
var _t := 0.0
var _last_usec := 0
var _frames := {}  # phase → Array of per-frame rows
var _thermal := {}
var _hitches: Array[Dictionary] = []  # the first MAX_HITCHES_LOGGED
var _hitch_count := 0
var _warmup_phase := ""
var _placements := 0


func run(scenario: int, config: Dictionary, p_yard: Yard) -> void:
	active = true
	_scenario = scenario
	_config = config
	yard = p_yard
	process_priority = -100  # log the previous frame before anything else runs this frame
	var refresh := DisplayServer.screen_get_refresh_rate()
	var target_fps := mini(60, int(round(refresh))) if refresh > 0.0 else 60
	Engine.max_fps = target_fps
	_period_ms = 1000.0 / target_fps
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if yard.grid == null:
		await yard.pile_ready
	_begin("warmup")


func _process(delta: float) -> void:
	if _state == "waiting" or _state == "done":
		return
	_log_previous_frame()
	_t += delta
	match _state:
		"warmup":
			_drive_warmup()
		"orbit":
			_drive_orbit(_t)
			_maybe_next(_config.phase_s)
		"rake":
			_drive_rake(_t)
			_maybe_next(_config.phase_s)
		"conveyor":
			_drive_conveyor(_t)
			_maybe_next(_config.phase_s)


# --- Phases ------------------------------------------------------------------------------

func _begin(state: String) -> void:
	_leave(_state)
	_state = state
	_t = 0.0
	_last_usec = 0
	status = state
	if state in PHASES:
		_frames[state] = []
		_thermal[state] = {"start": GameLoop.thermal_status()}
		_enter(state)
	elif state == "warmup":
		_frames["warmup"] = []


func _enter(phase: String) -> void:
	if phase == "conveyor":
		_placements += 1
		yard.place_conveyors(4, _placements * 0.7)
		yard.conveyor_speed = CONVEYOR_PHASE_SPEED


func _leave(state: String) -> void:
	if _thermal.has(state):
		_thermal[state]["end"] = GameLoop.thermal_status()
	_cleanup(state)


func _cleanup(phase: String) -> void:
	if phase == "conveyor":
		yard.clear_conveyors()
		yard.conveyor_speed = 1
	elif phase == "rake":
		yard.end_stroke()


func _maybe_next(seconds: float) -> void:
	if _t < seconds:
		return
	_phase_index += 1
	if _phase_index < PHASES.size():
		_begin(PHASES[_phase_index])
	else:
		_leave(_state)
		_state = "done"
		_report()


func _drive_warmup() -> void:
	var slice := PHASES[int(_t / WARMUP_SLICE_S) % PHASES.size()]
	var t_in_slice := fmod(_t, WARMUP_SLICE_S)
	if slice != _warmup_phase:
		_cleanup(_warmup_phase)
		_warmup_phase = slice
		_enter(slice)
		status = "warmup · " + slice
	match slice:
		"orbit":
			_drive_orbit(t_in_slice)
		"rake":
			_drive_rake(t_in_slice)
		"conveyor":
			_drive_conveyor(t_in_slice)
	if _t >= _config.warmup_s:
		_cleanup(_warmup_phase)
		_warmup_phase = ""
		_phase_index = 0
		_begin(PHASES[0])


## Sweeps yaw, pitch and zoom out to the whole pile (the heaviest view) and back.
func _drive_orbit(t: float) -> void:
	var camera := yard.camera
	var near := camera.max_distance * 0.14
	var far := camera.max_distance
	var distance := lerpf(near, far, 0.5 - 0.5 * cos(t * 0.25))
	if camera.fixed:
		camera.focus.x = sin(t * 0.2) * 20.0
		camera.set_view(camera.yaw, camera.pitch, distance)
	else:
		camera.set_view(t * 0.35, deg_to_rad(18.0 + 20.0 * (0.5 - 0.5 * cos(t * 0.3))), distance)


## Rakes a raster across the lower screen while the view turns slowly.
func _drive_rake(t: float) -> void:
	var camera := yard.camera
	if camera.fixed:
		camera.focus.x = sin(t * 0.05) * 10.0
		camera.set_view(camera.yaw, camera.pitch, camera.max_distance * 0.14)
	else:
		camera.set_view(t * 0.05, deg_to_rad(28.0), camera.max_distance * 0.14)
	var size := get_viewport().get_visible_rect().size
	var line_s := 1.2
	var line := int(t / line_s)
	var along := fmod(t, line_s) / line_s
	if along < 0.05:
		yard.end_stroke()
		return
	var x := lerpf(0.15, 0.85, along if line % 2 == 0 else 1.0 - along)
	var y := lerpf(0.45, 0.8, float(line % 8) / 7.0)
	yard.use_tool_at(Vector2(x, y) * size)


## Four conveyors dig at 60× speed, so tiles go dirty every frame, while the view turns.
func _drive_conveyor(t: float) -> void:
	var camera := yard.camera
	if camera.fixed:
		camera.set_view(camera.yaw, camera.pitch, camera.max_distance * 0.4)
	else:
		camera.set_view(t * 0.15, deg_to_rad(35.0), camera.max_distance * 0.4)


# --- Logging -----------------------------------------------------------------------------

func _log_previous_frame() -> void:
	var now := Time.get_ticks_usec()
	var bucket := "warmup" if _state == "warmup" else _state
	if _last_usec > 0 and _frames.has(bucket):
		var vp := get_viewport().get_viewport_rid()
		var row := {
			"interval_ms": (now - _last_usec) / 1000.0,
			"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
			"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(vp),
			"sim_ms": yard.sim_us_last_frame / 1000.0,
			"stamps": yard.rake_stamps_last_frame,
			"tiles": yard.pile.tiles_uploaded_last_frame,
		}
		_frames[bucket].append(row)
		if bucket == "warmup" and row.interval_ms > _period_ms * HITCH_FACTOR:
			_hitch_count += 1
			if _hitches.size() < MAX_HITCHES_LOGGED:
				_hitches.append({"t": snappedf(_t, 0.01), "phase": _warmup_phase, "ms": snappedf(row.interval_ms, 0.1)})
	_last_usec = now
	yard.reset_frame_counters()


func _phase_stats(rows: Array) -> Dictionary:
	var intervals := PackedFloat32Array()
	var sim := PackedFloat32Array()
	var gpu := PackedFloat32Array()
	var cpu := PackedFloat32Array()
	var missed := 0
	for row in rows:
		intervals.append(row.interval_ms)
		sim.append(row.sim_ms)
		gpu.append(row.gpu_ms)
		cpu.append(row.cpu_ms)
		if row.interval_ms > _period_ms * MISSED_FACTOR:
			missed += 1
	var missed_pct := 100.0 * missed / maxi(1, rows.size())
	return {
		"frames": rows.size(),
		"missed": missed,
		"missed_pct": snappedf(missed_pct, 0.01),
		"pass": rows.size() >= 30 and missed_pct <= PASS_MISSED_PCT,
		"interval_ms": _percentiles(intervals),
		"render_cpu_ms": _percentiles(cpu),
		"render_gpu_ms": _percentiles(gpu),
		"sim_ms": _percentiles(sim),
	}


func _percentiles(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():
		return {}
	values.sort()
	var at := func(p: float) -> float: return snappedf(values[mini(values.size() - 1, int(p * values.size()))], 0.01)
	return {"p50": at.call(0.5), "p95": at.call(0.95), "p99": at.call(0.99), "max": snappedf(values[-1], 0.01)}


# --- Report ------------------------------------------------------------------------------

func _report() -> void:
	status = "timing"
	var timings := _sim_timings()
	var phases := {}
	var passed := true
	for phase in PHASES:
		phases[phase] = _phase_stats(_frames[phase])
		phases[phase]["thermal"] = _thermal[phase]
		passed = passed and phases[phase].pass
	var size_m := yard.grid.size * SpikeConfig.CELL_M
	var results := {
		"scenario": _scenario,
		"name": _config.name,
		"device": OS.get_model_name(),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"godot": Engine.get_version_info().string,
		"refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"period_ms": snappedf(_period_ms, 0.01),
		"camera": _config.camera,
		"grid": yard.grid.size,
		"cell_m": SpikeConfig.CELL_M,
		"pile_width_m": snappedf(size_m * 0.94, 0.1),
		"pile_peak_m": snappedf(SpikeConfig.peak_for(yard.grid.size) * SpikeConfig.HEIGHT_UNIT_M, 0.1),
		"pile_gen_ms": snappedf(yard.pile_gen_ms, 0.1),
		"pile_gen_native": PileGen.native_available(),
		"texture_build_ms": snappedf(yard.texture_build_ms, 0.1),
		"timings": timings,
		"warmup_frames": _frames.warmup.size(),
		"compile_hitch_count": _hitch_count,
		"compile_hitches": _hitches,
		"phases": phases,
		"budgets": {
			"frames": passed,
			"pile_gen_300ms": yard.pile_gen_ms <= 300.0,
			"offline_8h_500ms": timings.offline_8h_ms < 500.0,
			"come_back_8h_500ms": timings.come_back_8h_ms < 500.0,
			"brush_2ms": timings.rake_frame_ms_p95 <= 2.0,
		},
		"pass": passed,
	}
	var json := JSON.stringify(results, "  ")
	# Logcat truncates lines near 4 KB: one key per line (release builds can't pull user://).
	for key in results:
		if key == "phases":
			for phase in results.phases:
				print("[spike] phase.%s=%s" % [phase, JSON.stringify(results.phases[phase])])
		else:
			print("[spike] %s=%s" % [key, JSON.stringify(results[key])])
	_write("user://spike_results.json", json)
	_write_frames()
	GameLoop.write_results(json)
	status = "done · %s" % ("PASS" if passed else "MISS")
	await get_tree().create_timer(1.0).timeout
	GameLoop.finish(get_tree())


## Times the sim hot paths on this device: rake stamp, picking, 8 h offline, tile upload.
func _sim_timings() -> Dictionary:
	var grid := yard.grid
	var centre := grid.size / 2
	var flank := centre + int(grid.size * 0.25)
	var started := Time.get_ticks_usec()
	for i in TIMING_REPEATS:
		BrushTool.apply(grid, SimDefaults.RAKE, centre + (i % 20) * 3, flank, 256, 0)
	var stamp_ms := (Time.get_ticks_usec() - started) / 1000.0 / TIMING_REPEATS
	var screen := get_viewport().get_visible_rect().size
	started = Time.get_ticks_usec()
	for i in TIMING_REPEATS:
		var pos := Vector2(screen.x * (0.2 + 0.006 * i), screen.y * 0.6)
		HeightPicker.pick(grid, yard.camera.project_ray_origin(pos), yard.camera.project_ray_normal(pos))
	var pick_ms := (Time.get_ticks_usec() - started) / 1000.0 / TIMING_REPEATS
	var rake_rows: Array = _frames.rake
	var rake_sim := PackedFloat32Array()
	for row in rake_rows:
		if row.stamps > 0:
			rake_sim.append(row.sim_ms)
	var rake_p95: float = _percentiles(rake_sim).get("p95", 0.0)
	var offline: Array[ConveyorDig] = []
	var radius := int(grid.size * 0.47)
	for i in 4:
		var angle := TAU * i / 4.0 + 2.2
		offline.append(ConveyorDig.new(centre + int(cos(angle) * radius), centre + int(sin(angle) * radius), int(-cos(angle) * 256.0), int(-sin(angle) * 256.0), SimDefaults.CONVEYOR.dig_width, radius, SimDefaults.CONVEYOR.rate))
	grid.take_dirty()
	started = Time.get_ticks_usec()
	var offline_dug := OfflineSim.fast_forward(grid, offline, OFFLINE_MS)
	var offline_ms := (Time.get_ticks_usec() - started) / 1000.0
	var away_ms := _time_away_ms()
	started = Time.get_ticks_usec()
	var tiles := yard.pile.upload_dirty()
	var upload_ms := (Time.get_ticks_usec() - started) / 1000.0
	return {
		"rake_stamp_ms": snappedf(stamp_ms, 0.001),
		"rake_frame_ms_p95": rake_p95,
		"pick_ms": snappedf(pick_ms, 0.001),
		"offline_8h_ms": snappedf(offline_ms, 0.1),
		"come_back_8h_ms": snappedf(away_ms, 0.1),
		"offline_8h_conveyors": offline.size(),
		"offline_8h_dug": offline_dug,
		"offline_upload_tiles": tiles,
		"offline_upload_ms": snappedf(upload_ms, 0.1),
		"tile_upload_ms_each": snappedf(upload_ms / maxi(1, tiles), 0.001),
	}


## G7's return path (GameState.come_back: 1-minute steps, needles checked after each) for 8 h on
## a fresh 1024 pile with 4 conveyors, the same workload as test_offline.gd.
func _time_away_ms() -> float:
	var economy := Economy.bundled()
	var state := GameState.new_game(economy, 3, PileSpec.new(5, 1024, SimDefaults.peak_for(1024), 9, 4))
	var conveyor := economy.machine(&"conveyor")
	for heading in 4:
		var pose := Placement.nearest_edge_spot(state.sim.grid, state.park.placed, conveyor, Vector2i(512 + (heading % 2) * 400 - 200, 512 + (heading / 2) * 400 - 200))
		state.park.place(state.sim, conveyor, pose)
	state.clock.start(0, 1)
	var started := Time.get_ticks_usec()
	state.come_back(OFFLINE_MS / 1000, 1)
	return (Time.get_ticks_usec() - started) / 1000.0


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text)


func _write_frames() -> void:
	var file := FileAccess.open("user://frames.jsonl", FileAccess.WRITE)
	if not file:
		return
	for phase in ["warmup"] + PHASES:
		for i in _frames[phase].size():
			var row: Dictionary = _frames[phase][i].duplicate()
			row["phase"] = phase
			row["i"] = i
			file.store_line(JSON.stringify(row))
