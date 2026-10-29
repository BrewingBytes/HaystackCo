class_name Yard
extends Node3D
## The yard: ground, light, the pile, the orbit camera, the hand tools and the player's machines,
## all driving one PileSim. Touch goes through the GestureRouter (eng state machine with design
## D4/D15); placement mode follows design D4. Hay that leaves the pile goes straight into the
## wallet (design D16) and the Shop spends it. The HUD (G9a) picks tools, opens the Shop, and
## selects a tapped machine for Move or Shelve. Desktop: keys 1–5 pick the tools in tray order;
## B gives a free conveyor.

signal pile_ready
signal needles_found(needles: Array[Needle])

const TOP_BAND_DP := 140.0  # design D15: a drag starting here always orbits
const MAX_STAMPS_PER_FRAME := 8
const TOOLS: Array[StringName] = [&"rake", &"pitchfork", &"magnet", &"blower", &"detector"]  # tray order
const ORBIT_RAD_PER_DP := 0.008  # a full-width swipe (≈ 360dp) turns about 165°
const GHOST_GRAB_CELLS := 8  # a finger this close to the ghost's outline grabs it
const PING_S := 8.0
const SELECT_SLOP_CELLS := 6  # a tap this close to a machine's footprint selects it
const GHOST_HINT := "Drag to move · ⟳ to turn · PLACE when the lines are white"

var state: GameState
var sim: PileSim  # state.sim
var grid: HeightGrid  # sim.grid
var tool := &"rake"
var detector_strength := 0  # last detector reading, 0..1000
var camera: OrbitCamera
var pile: HayPile
var conveyors: Array[ConveyorDig] = []  # sim.machines (the same array)
var conveyor_speed := 1  # time multiplier (the spike's conveyor phase runs fast)
var economy := Economy.bundled()
var park: MachinePark  # state.park
var wallet: Wallet  # state.wallet
var inventory: Inventory  # state.inventory
var placing: PlacementSession
var hud: YardHud
var router: GestureRouter
var pile_gen_ms := 0.0
var texture_build_ms := 0.0
## Per-frame sim cost (picking + rake + conveyors + tile upload), for the frame log.
var sim_us_last_frame := 0
var rake_stamps_last_frame := 0

var _particles: GPUParticles3D
var _mouse_down := false
var _last_rake_cell := Vector2i(-1, -1)
var _views := {}  # MachinePark.Placed → MachineView
var _ghost: MachineView
var _grab_offset := Vector2i.ZERO
var _gen_task := -1
var _pending: GameState
var _needle_bodies: Array[Node3D] = []
var _holds := 0
var _selected: MachinePark.Placed  # the machine whose label is up


func _ready() -> void:
	_build_environment()
	camera = OrbitCamera.new()
	camera.name = "OrbitCamera"
	add_child(camera)
	camera.current = true
	pile = HayPile.new()
	pile.name = "HayPile"
	add_child(pile)
	_build_particles()
	router = GestureRouter.new(self)
	router.dp = _dp()
	hud = YardHud.new()
	hud.name = "YardHud"
	add_child(hud)
	hud.place_pressed.connect(_on_place_pressed)
	hud.cancel_pressed.connect(cancel_placement)
	hud.turn_pressed.connect(func() -> void: _turn_ghost(1))
	hud.recenter_pressed.connect(func() -> void: camera.recenter(A11y.system_reduce_motion()))
	hud.tool_pressed.connect(_on_tool_pressed)
	hud.shop_pressed.connect(open_shop)
	hud.mute_pressed.connect(func() -> void:
		Settings.set_muted(not Settings.muted())
		hud.set_muted(Settings.muted()))
	hud.move_pressed.connect(_on_move_pressed)
	hud.shelve_pressed.connect(_on_shelve_pressed)
	hud.shop.buy_pressed.connect(_on_shop_buy)
	hud.shop.place_pressed.connect(func(id: StringName) -> void:
		hud.shop.close()
		begin_placement(id))
	hud.set_tools(economy)
	hud.set_muted(Settings.muted())


## A new game with pile 1 at `grid_size`, generated off the main thread. Emits pile_ready.
func generate(grid_size: int, fixed_camera: bool, install_seed := 1) -> void:
	await start_from(func() -> GameState: return GameState.new_game(economy, install_seed, new_pile_spec(grid_size)), fixed_camera)


## Pile 1 as the spike sizes it (SpikeConfig grid; the catalog's sizes take over with G9's
## pile progression).
static func new_pile_spec(grid_size: int) -> PileSpec:
	return PileSpec.new(1, grid_size, SimDefaults.peak_for(grid_size), SimDefaults.PILE1_SEED, 1)


## Runs `make` (a new game or a loaded save; both generate a pile) off the main thread, then
## shows the state. Emits pile_ready.
func start_from(make: Callable, fixed_camera: bool) -> void:
	camera.fixed = fixed_camera
	var started := Time.get_ticks_usec()
	_gen_task = WorkerThreadPool.add_task(func() -> void: _pending = make.call(), true, "pile_gen")
	while not WorkerThreadPool.is_task_completed(_gen_task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(_gen_task)
	pile_gen_ms = (Time.get_ticks_usec() - started) / 1000.0
	_show(_pending)


## Shows `p_state`'s pile in place of the current one (a new pile after "Next pile").
func show_pile(p_state: GameState) -> void:
	cancel_placement()
	_show(p_state)


func _show(p_state: GameState) -> void:
	_deselect()
	for body in _needle_bodies:
		body.queue_free()
	_needle_bodies.clear()
	for view: Node in _views.values():
		view.queue_free()
	_views.clear()
	state = p_state
	sim = state.sim
	park = state.park
	wallet = state.wallet
	inventory = state.inventory
	grid = sim.grid
	conveyors = sim.machines
	var started := Time.get_ticks_usec()
	pile.setup(grid)
	texture_build_ms = (Time.get_ticks_usec() - started) / 1000.0
	for needle in sim.needles:
		if needle.found:
			_draw_needle(needle)  # found before the save: lying where they were found
	for machine in park.placed:
		var view := MachineView.new(machine.spec)
		add_child(view)
		view.set_pose(machine.pose, grid.size)
		view.print_in(true)
		_views[machine] = view
	var radius_m := grid.size * 0.47 * SpikeConfig.CELL_M
	camera.frame_flank(radius_m, HeightPicker.height_at(grid, 0.0, radius_m * 0.55))
	pile_ready.emit()


func _credit_hay() -> void:
	state.credit_hay()


## Saves through `store`. A machine still in placement mode is saved on the shelf, where
## Cancel would put it.
func save_to(store: SaveStore) -> Error:
	if state == null:
		return ERR_UNCONFIGURED
	var now := int(Time.get_unix_time_from_system())
	state.clock.seen(now)  # the game was running until now: nothing owed for it
	# A save can come mid-frame (the pile-complete save runs inside the stroke that found the
	# last needle): credit that hay now, since a loaded save counts all collected hay as credited.
	_credit_hay()
	if placing != null:
		park.shelf.append(placing.spec)
	var result := store.save(state, now)
	if placing != null:
		park.shelf.pop_back()
	return result


## Holds the yard still: while machines catch up on a worker thread (G7 resume) and behind the
## pile-done card (G8). The whole subtree stops, HUD included: its buttons change the machine
## list and the wallet. Holds nest: the yard runs again when every hold is released.
func hold(on: bool) -> void:
	_holds = maxi(0, _holds + (1 if on else -1))
	process_mode = Node.PROCESS_MODE_DISABLED if _holds > 0 else Node.PROCESS_MODE_INHERIT


func _process(delta: float) -> void:
	if grid == null:
		return
	var started := Time.get_ticks_usec()
	state.tick(int(delta * 1000.0))
	var found := sim.advance_machines(int(delta * 1000.0) * conveyor_speed)
	if not found.is_empty():
		_on_found(found)
	_credit_hay()
	pile.upload_dirty()
	pile.set_focus(camera.focus, camera.global_position)
	sim_us_last_frame += Time.get_ticks_usec() - started
	hud.set_recenter_visible(camera.is_off_default())
	hud.show_state(wallet.hay, hay_per_s(), state.boost_ms_left, sim.spec.number, inventory, economy, tool, park.shelf.size(), delta)
	var cheapest := inventory.cheapest_unowned(economy)
	hud.set_shop_cue(not state.flags[&"cueShopSeen"] and cheapest != null and wallet.can_afford(cheapest.price))
	_place_machine_label()
	if placing != null:
		hud.set_turn_anchor(camera.unproject_position(_ghost.global_position), get_viewport().get_visible_rect().size)


func _notification(what: int) -> void:
	# Backgrounding mid-placement returns the machine to the shelf (design D4).
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if router != null:
			router.reset()
		if what == NOTIFICATION_APPLICATION_PAUSED:
			cancel_placement()


## Called by Main after the frame is logged.
func reset_frame_counters() -> void:
	sim_us_last_frame = 0
	rake_stamps_last_frame = 0


# --- Tools -------------------------------------------------------------------------------

func select_tool(id: StringName) -> void:
	if id in TOOLS and inventory != null and inventory.owns(id):
		end_stroke()
		tool = id


## Uses the equipped tool on the pile point under `screen_pos`. Returns false if it isn't on hay.
func use_tool_at(screen_pos: Vector2) -> bool:
	var started := Time.get_ticks_usec()
	var hit := HeightPicker.pick(grid, camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	var on_hay: bool = hit.hit and hit.hay
	if on_hay:
		var cell := HeightPicker.cell_of(grid, hit.point)
		match tool:
			&"magnet":
				_on_found(sim.magnet(cell.x, cell.y, economy.item(&"magnet").radius, not inventory.magnet_tutorial_done))
				inventory.magnet_tutorial_done = true
			&"detector":
				detector_strength = sim.detector(cell.x, cell.y)
			_:
				if _last_rake_cell.x < 0:
					_last_rake_cell = cell
				_stamp_along(_brush(), _last_rake_cell, cell)
				_particles.global_position = hit.point
				_particles.emitting = true
	sim_us_last_frame += Time.get_ticks_usec() - started
	return on_hay


func end_stroke() -> void:
	_last_rake_cell = Vector2i(-1, -1)
	_particles.emitting = false


func _brush() -> BrushSpec:
	match tool:
		&"pitchfork":
			return SimDefaults.PITCHFORK
		&"blower":
			return SimDefaults.BLOWER
	return SimDefaults.RAKE


func _stamp_along(brush: BrushSpec, from: Vector2i, to: Vector2i) -> void:
	var spacing := maxi(1, brush.radius / 2)
	var delta := to - from
	var length := maxi(absi(delta.x), absi(delta.y))
	if length < spacing and from != to:
		return
	var dir := Vector2(delta).normalized() if length > 0 else Vector2(0.0, 1.0)
	var dir_x := int(dir.x * 256.0)
	var dir_y := int(dir.y * 256.0)
	var stamps := clampi(length / spacing, 1, MAX_STAMPS_PER_FRAME)
	var found: Array[Needle] = []
	for i in stamps:
		var cell := from + Vector2i(Vector2(delta) * float(i + 1) / stamps)
		found.append_array(sim.brush(brush, cell.x, cell.y, dir_x, dir_y))
	rake_stamps_last_frame += stamps
	_last_rake_cell = to
	if not found.is_empty():
		_on_found(found)


# --- Needles -----------------------------------------------------------------------------

## A found needle lies on the pile where it was buried (G10/G11 add the glint and clink).
func _on_found(found: Array[Needle]) -> void:
	if found.is_empty():
		return
	for needle in found:
		_draw_needle(needle)
		print("[sim] needle found by %s at cell (%d, %d)" % [Needle.Source.keys()[needle.source].to_lower(), needle.x, needle.y])
	if sim.is_complete():
		print("[sim] pile %d complete" % sim.spec.number)
	needles_found.emit(found)


func _draw_needle(needle: Needle) -> void:
	var half := grid.size * 0.5
	# A magnet pulls the needle out of the hay; a dug-out one lies where it was buried.
	var lies_at := maxi(needle.z, grid.get_h(needle.x, needle.y))
	var at := Vector3((needle.x + 0.5 - half) * SpikeConfig.CELL_M, lies_at * SpikeConfig.HEIGHT_UNIT_M, (needle.y + 0.5 - half) * SpikeConfig.CELL_M)
	var body := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = 0.012
	shape.bottom_radius = 0.004
	shape.height = 0.35
	body.mesh = shape
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("#C9D3DC")
	steel.metallic = 0.9
	steel.roughness = 0.25
	body.material_override = steel
	add_child(body)
	_needle_bodies.append(body)
	body.position = at + Vector3(0.0, 0.02, 0.0)
	body.rotation = Vector3(0.0, float(needle.x * 7 + needle.y) * 0.37, PI / 2.0)


## Whether a detector ping has anything to point at (the rewarded PING hides otherwise).
func can_ping() -> bool:
	return sim != null and sim.needles.any(func(n: Needle) -> bool: return not n.found and not n.tutorial)


## The rewarded detector PING (design D17): the same reading as the detector, once, over the
## whole pile. A ring marks where the detector would beep at half strength or more around the
## unfound needle nearest the camera's focus, for PING_S seconds.
func ping() -> void:
	var focus := HeightPicker.cell_of(grid, camera.focus)
	var nearest: Needle
	for needle in sim.needles:
		if needle.found or needle.tutorial:
			continue
		if nearest == null or Vector2i(needle.x, needle.y).distance_squared_to(focus) < Vector2i(nearest.x, nearest.y).distance_squared_to(focus):
			nearest = needle
	if nearest == null:
		return
	var half := grid.size * 0.5
	var radius_m := economy.item(&"detector").radius * SpikeConfig.CELL_M
	var ring := MeshInstance3D.new()
	var shape := TorusMesh.new()
	shape.inner_radius = radius_m - 0.08
	shape.outer_radius = radius_m
	ring.mesh = shape
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color("#FF5A1F")
	paint.no_depth_test = true
	ring.material_override = paint
	add_child(ring)
	ring.position = Vector3((nearest.x + 0.5 - half) * SpikeConfig.CELL_M, grid.get_h(nearest.x, nearest.y) * SpikeConfig.HEIGHT_UNIT_M + 0.1, (nearest.y + 0.5 - half) * SpikeConfig.CELL_M)
	get_tree().create_timer(PING_S).timeout.connect(ring.queue_free)
	print("[ads] ping: needle within %.1f m of the ring's centre" % radius_m)


# --- Machines and placement (design D4) -------------------------------------------------

## Buy spends the hay; a machine then goes to the shelf and placement opens (design D4).
## False when the wallet is short or the tool is already owned.
func buy(id: StringName) -> bool:
	if not inventory.buy(economy, id, wallet, park):
		print("[shop] can't buy %s: %d hay, price %d" % [id, wallet.hay, economy.item(id).price if economy.item(id) else -1])
		return false
	print("[shop] bought %s; %d hay left" % [id, wallet.hay])
	if economy.item(id).machine != null:
		begin_placement(id)
	return true


## Harness and dev: a machine on the shelf for free, then placement mode.
func give_and_place(spec: MachineSpec) -> void:
	park.buy(spec)
	begin_placement(spec.id)


## Opens placement for a shelved machine: the ghost appears at the nearest valid spot at the
## pile's edge, facing the centre. Waits for the current gesture to end before taking over.
func begin_placement(id: StringName) -> void:
	if placing != null or grid == null:
		return
	placing = PlacementSession.begin(park, sim, id, HeightPicker.cell_of(grid, camera.focus))
	if placing == null:
		return
	end_stroke()
	router.set_placing(true)
	_ghost = MachineView.new(placing.spec)
	add_child(_ghost)
	_refresh_ghost()
	hud.show_placement(String(placing.spec.id))
	if not state.flags[&"cueGhostSeen"]:
		state.flags[&"cueGhostSeen"] = true  # design D8: the first ghost only
		hud.notice(GHOST_HINT)


## Cancel (or app backgrounded): the machine goes back on the shelf, no hay lost.
func cancel_placement() -> void:
	if placing == null:
		return
	placing.cancel()
	_close_placement()
	_ghost.queue_free()
	_ghost = null


func _on_place_pressed() -> void:
	if placing == null:
		return
	var machine := placing.confirm()
	if machine == null:
		return
	_views[machine] = _ghost
	_ghost.print_in(A11y.system_reduce_motion())
	_ghost = null
	_close_placement()


func _close_placement() -> void:
	placing = null
	router.set_placing(false)
	hud.hide_placement()


func _turn_ghost(steps: int) -> void:
	if placing != null:
		placing.turn(steps)
		_refresh_ghost()


func _refresh_ghost() -> void:
	_ghost.set_pose(placing.pose, grid.size)
	var valid := placing.can_place()
	_ghost.show_ghost(valid)
	hud.set_can_place(valid)


## Harness and dev: stands `count` conveyors at the pile's foot, facing the centre, without the
## footprint rules (the spike's conveyor phase and the trench screenshot).
func place_conveyors(count: int, angle_offset := 0.4) -> void:
	var spec := SimDefaults.CONVEYOR
	var centre := grid.size / 2
	var r := int(grid.size * 0.47) + spec.length / 2 + 2
	for i in count:
		var angle := TAU * i / count + angle_offset
		var x := centre + int(cos(angle) * r)
		var y := centre + int(sin(angle) * r)
		var machine := park.place(sim, spec, Pose.new(x, y, Pose.yaw_toward(x, y, centre, centre)))
		var view := MachineView.new(spec)
		add_child(view)
		view.set_pose(machine.pose, grid.size)
		view.print_in(true)
		_views[machine] = view


func clear_conveyors() -> void:
	for machine in park.placed.duplicate():
		park.pick_up(sim, machine)
		_views[machine].queue_free()
		_views.erase(machine)
	park.shelf.clear()


# --- HUD: tray, Shop, the selected machine (G9a) ------------------------------------------

## Hay per second from the machines still digging, with the 2× reward (the HUD rate).
func hay_per_s() -> float:
	var units := 0
	for dig in sim.machines:
		if not dig.done():
			units += dig.rate
	return units * wallet.boost / float(economy.units_per_hay)


## A tray cell: an owned tool is picked up; a locked one opens the Shop scrolled to it.
func _on_tool_pressed(id: StringName) -> void:
	if inventory.owns(id):
		select_tool(id)
	else:
		open_shop(id)


func open_shop(focus := &"") -> void:
	if placing != null or state == null:
		return
	state.flags[&"cueShopSeen"] = true
	_deselect()
	router.reset()
	hud.shop.open(inventory, park, wallet, economy, focus)


## Shop Buy: a machine closes the Shop and starts placement (in buy()); a tool is picked up.
func _on_shop_buy(id: StringName) -> void:
	var machine := economy.item(id).machine != null
	if machine:
		hud.shop.close()
	if buy(id) and not machine:
		select_tool(id)


## A tap off the hay: selects the machine under it (its label shows) or clears the selection.
func tap(pos: Vector2) -> void:
	var cell := _ground_cell(pos)
	var best: MachinePark.Placed = null
	var best_d := INF
	for machine in park.placed:
		var d := Vector2(cell - Vector2i(machine.pose.x, machine.pose.y)).length()
		var reach := machine.spec.length / 2.0 + SELECT_SLOP_CELLS
		if d <= reach and d < best_d:
			best = machine
			best_d = d
	if best == _selected:
		return
	_deselect()
	if best != null:
		_selected = best
		_views[best].set_selected(true)


func _deselect() -> void:
	if _selected != null and _views.has(_selected):
		_views[_selected].set_selected(false)
	_selected = null
	if hud != null:
		hud.hide_machine_label()


func _place_machine_label() -> void:
	if _selected == null or placing != null or not _views.has(_selected):
		if hud.machine_label_shown():
			hud.hide_machine_label()
		return
	var top: Vector3 = _views[_selected].global_position + Vector3(0.0, MachineView.HEIGHT_M, 0.0)
	if camera.is_position_behind(top):
		hud.hide_machine_label()
		return
	var dig := _selected.dig
	var rate := 0.0 if dig.done() else dig.rate * wallet.boost / float(economy.units_per_hay)
	hud.show_machine_label(String(_selected.spec.id), UiTheme.rate(rate), camera.unproject_position(top), get_viewport().get_visible_rect().size)


## Move: the machine goes back to the shelf and straight into placement (moves are free).
func _on_move_pressed() -> void:
	var machine := _selected
	if machine == null:
		return
	_pick_up(machine)
	begin_placement(machine.spec.id)


## Shelve: the machine goes back on the shelf (Shop: YOUR MACHINES).
func _on_shelve_pressed() -> void:
	if _selected != null:
		_pick_up(_selected)


func _pick_up(machine: MachinePark.Placed) -> void:
	_deselect()
	park.pick_up(sim, machine)
	_views[machine].queue_free()
	_views.erase(machine)


# --- Input (GestureRouter delegate) -------------------------------------------------------

## Touches come through _input: the GUI marks touch releases handled, so _unhandled_input would
## never see a finger lift. Presses on a HUD control are left to the HUD.
func _input(event: InputEvent) -> void:
	if grid == null:
		return
	var now := Time.get_ticks_msec()
	if event is InputEventScreenTouch:
		if event.pressed:
			if not hud.blocks(event.position):
				router.touch_down(event.index, event.position, now)
		else:
			router.touch_up(event.index, now)
	elif event is InputEventScreenDrag:
		router.touch_move(event.index, event.position)


## Desktop mouse and keys. Mouse events Godot emulates from touches are ignored: the touch
## itself already went to the router.
func _unhandled_input(event: InputEvent) -> void:
	if grid == null or (event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION):
		return
	var now := Time.get_ticks_msec()
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_mouse_down = button.pressed
			if button.pressed:
				router.touch_down(0, button.position, now)
			else:
				router.touch_up(0, now)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom(0.9)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom(1.1)
	elif event is InputEventMouseMotion and _mouse_down:
		router.touch_move(0, event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var index: int = event.keycode - KEY_1
		if index >= 0 and index < TOOLS.size():
			select_tool(TOOLS[index])
		elif event.keycode == KEY_B:
			give_and_place(SimDefaults.CONVEYOR)
		elif event.keycode == KEY_R:
			_turn_ghost(1)


func in_top_band(pos: Vector2) -> bool:
	return pos.y < TOP_BAND_DP * _dp()


func hits_hay(pos: Vector2) -> bool:
	var hit := HeightPicker.pick(grid, camera.project_ray_origin(pos), camera.project_ray_normal(pos))
	return hit.hit and hit.hay


func hits_ghost(pos: Vector2) -> bool:
	if placing == null:
		return false
	var cell := _ground_cell(pos)
	var d := cell - Vector2i(placing.pose.x, placing.pose.y)
	var reach := placing.spec.length / 2 + GHOST_GRAB_CELLS
	if d.x * d.x + d.y * d.y > reach * reach:
		return false
	_grab_offset = d
	return true


func orbit(delta: Vector2) -> void:
	if camera.fixed:
		camera.pan(-delta.x * camera.distance * 0.002, delta.y * camera.distance * 0.002)
	else:
		camera.orbit(-delta.x / router.dp * ORBIT_RAD_PER_DP, delta.y / router.dp * ORBIT_RAD_PER_DP)


func zoom(factor: float) -> void:
	camera.zoom(factor)


func tool_start(pos: Vector2) -> void:
	_deselect()
	use_tool_at(pos)


func tool_move(pos: Vector2) -> void:
	use_tool_at(pos)


func tool_end() -> void:
	end_stroke()


func ghost_drag(pos: Vector2) -> void:
	if placing == null:
		return
	placing.move_to(_ground_cell(pos) - _grab_offset)
	_refresh_ghost()


func ghost_turn(steps: int) -> void:
	_turn_ghost(steps)


## The yard cell under a screen point: the pile surface or the ground around it.
func _ground_cell(pos: Vector2) -> Vector2i:
	var hit := HeightPicker.pick(grid, camera.project_ray_origin(pos), camera.project_ray_normal(pos))
	return HeightPicker.cell_of(grid, hit.point)


func _dp() -> float:
	return DisplayServer.screen_get_scale() if OS.get_name() != "Android" else DisplayServer.screen_get_dpi() / 160.0


# --- Scene -------------------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#18263A")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#5A7AA8")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# One warm key light from the upper left (DESIGN.md Yard); no real-time shadows in the spike.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#FFE6C4")
	sun.light_energy = 1.45
	# Low and from the side: grazing light shows the lumps and furrows.
	sun.rotation = Vector3(deg_to_rad(-24.0), deg_to_rad(-70.0), 0.0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(800.0, 800.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#3B3A33")
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	ground.position.y = -0.01
	add_child(ground)


func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = 192
	_particles.lifetime = 0.9
	_particles.emitting = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 60.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 3.5
	process.gravity = Vector3(0.0, -6.0, 0.0)
	process.angle_max = 180.0
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.8
	_particles.process_material = process
	var strand := QuadMesh.new()
	strand.size = Vector2(0.02, 0.16)
	var strand_material := StandardMaterial3D.new()
	strand_material.albedo_color = Color("#B8873A")
	strand_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	strand_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	strand.material = strand_material
	_particles.draw_pass_1 = strand
	add_child(_particles)
