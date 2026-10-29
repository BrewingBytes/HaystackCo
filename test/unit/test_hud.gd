extends GutTest
## G9a: the Yard HUD (DESIGN.md "Layout", "Components"; design D4, D8, D13), the Shop stub and
## the tapped-machine label, driven through the yard.

var yard: Yard


func before_each() -> void:
	yard = Yard.new()
	add_child_autofree(yard)
	await yard.generate(128, false)
	await get_tree().process_frame


func _hay(amount: int) -> void:
	yard.wallet.credit(amount * yard.economy.units_per_hay)


# --- Numbers ------------------------------------------------------------------------------

func test_counter_shows_full_digits_then_three_significant_figures() -> void:
	assert_eq(UiTheme.abbreviated(0), "0")
	assert_eq(UiTheme.abbreviated(12_480), "12,480")
	assert_eq(UiTheme.abbreviated(999_999), "999,999")
	assert_eq(UiTheme.abbreviated(1_000_000), "1M")
	assert_eq(UiTheme.abbreviated(1_240_000), "1.24M")
	assert_eq(UiTheme.abbreviated(12_345_678), "12.3M")
	assert_eq(UiTheme.abbreviated(999_999_999), "1B")
	assert_eq(UiTheme.abbreviated(3_500_000_000), "3.5B")
	assert_eq(UiTheme.grouped(-1234), "-1,234")


func test_rates_and_timers_for_mono() -> void:
	assert_eq(UiTheme.rate(0.9), "+0.9/s")
	assert_eq(UiTheme.rate(2.0), "+2/s")
	assert_eq(UiTheme.rate(38.4), "+38/s")
	assert_eq(UiTheme.clock(479_001), "8:00")
	assert_eq(UiTheme.clock(59_000), "0:59")


# --- Tray ---------------------------------------------------------------------------------

func test_tray_has_five_tools_in_price_order_and_locks_unowned_ones() -> void:
	assert_eq(yard.hud.cells.keys(), [&"rake", &"pitchfork", &"magnet", &"blower", &"detector"])
	var rake: YardHud.ToolCell = yard.hud.cells[&"rake"]
	var fork: YardHud.ToolCell = yard.hud.cells[&"pitchfork"]
	assert_true(rake.outline.visible, "the rake starts in hand")
	assert_false(fork.name_label.visible)
	assert_true(fork.lock_row.visible)
	assert_eq(fork.price_label.text, "2,500")
	assert_string_contains(fork.accessibility_name, "locked")


func test_a_locked_tool_opens_the_shop_and_an_owned_one_is_picked_up() -> void:
	yard.hud.tool_pressed.emit(&"pitchfork")
	assert_true(yard.hud.shop.visible, "locked: the Shop opens")
	assert_eq(yard.tool, &"rake")
	yard.hud.shop.close()
	yard.inventory.owned[&"pitchfork"] = 1
	yard.hud.tool_pressed.emit(&"pitchfork")
	assert_false(yard.hud.shop.visible)
	assert_eq(yard.tool, &"pitchfork")


func test_tray_labels_fit_their_cell_at_200_percent_font() -> void:
	UiTheme.font_scale_override = 2.0
	var hud := YardHud.new()
	add_child_autofree(hud)
	hud.set_tools(yard.economy)
	for id: StringName in hud.cells:
		var l: Label = hud.cells[id].name_label
		var width := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
		assert_lte(width, (72 - 8) * UiTheme.DP, "%s fits its 72dp cell" % id)
	UiTheme.font_scale_override = null


# --- Shop ---------------------------------------------------------------------------------

func test_buying_a_tool_spends_the_hay_and_puts_it_in_hand() -> void:
	_hay(3000)
	yard.open_shop()
	yard.hud.shop.buy_pressed.emit(&"pitchfork")
	assert_eq(yard.wallet.hay, 500)
	assert_eq(yard.tool, &"pitchfork")
	assert_true(yard.hud.shop.visible, "a tool keeps the Shop open")


func test_buying_a_machine_closes_the_shop_and_starts_placement() -> void:
	_hay(20_000)
	yard.open_shop()
	yard.hud.shop.buy_pressed.emit(&"conveyor")
	assert_false(yard.hud.shop.visible)
	assert_not_null(yard.placing)
	assert_true(yard.hud.placement_shown(), "the placement bar replaces the tray")


func test_shop_lists_the_shelf_first_with_one_orange_place() -> void:
	yard.park.buy(SimDefaults.CONVEYOR)
	yard.park.buy(SimDefaults.CONVEYOR)
	yard.open_shop()
	var shop := yard.hud.shop
	var places := shop.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "PLACE")
	assert_eq(places.size(), 1, "one plate per kind on the shelf")
	var labels := shop.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_lt(labels.find("YOUR MACHINES"), labels.find("TOOLS"))
	assert_has(labels, "CONVEYOR × 2")
	places[0].pressed.emit()
	assert_false(shop.visible)
	assert_not_null(yard.placing)


func test_short_of_hay_buy_is_disabled_and_says_how_much_more() -> void:
	_hay(1000)
	yard.open_shop()
	var shop := yard.hud.shop
	var labels := shop.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_has(labels, "1,500 more hay")
	var buys := shop.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.accessibility_name.begins_with("Buy pitchfork"))
	assert_true(buys[0].disabled)


func test_the_shop_has_no_orange_with_an_empty_shelf() -> void:
	_hay(100_000)
	yard.open_shop()
	for b: Button in yard.hud.shop.find_children("*", "Button", true, false):
		var normal := b.get_theme_stylebox("normal") as StyleBoxFlat
		assert_false(normal != null and normal.bg_color == UiTheme.ACTION, "%s isn't orange" % b.text)


# --- First-run cues (design D8) -----------------------------------------------------------

func test_shop_cue_until_the_first_visit() -> void:
	await get_tree().process_frame
	assert_false(yard.hud._cue, "nothing affordable yet")
	_hay(2500)
	await get_tree().process_frame
	assert_true(yard.hud._cue, "first affordable item: SHOP pulses")
	yard.open_shop()
	yard.hud.shop.close()
	await get_tree().process_frame
	assert_false(yard.hud._cue, "gone after the first visit")
	assert_true(yard.state.flags[&"cueShopSeen"])


func test_ghost_hint_on_the_first_placement_only() -> void:
	yard.give_and_place(SimDefaults.CONVEYOR)
	assert_eq(yard.hud.notice_text(), Yard.GHOST_HINT)
	yard.cancel_placement()
	yard.hud._next_notice()  # the hint times out
	yard.give_and_place(SimDefaults.CONVEYOR)
	assert_eq(yard.hud.notice_text(), "", "only the first ghost")


# --- Machines -----------------------------------------------------------------------------

func _place_one() -> MachinePark.Placed:
	yard.place_conveyors(1)
	return yard.park.placed[0]


func _screen_of(machine: MachinePark.Placed) -> Vector2:
	var half := yard.grid.size * 0.5
	var at := Vector3((machine.pose.x - half) * SpikeConfig.CELL_M, 0.0, (machine.pose.y - half) * SpikeConfig.CELL_M)
	yard.camera.focus = at
	yard.camera.set_view(yard.camera.yaw, deg_to_rad(60.0), 12.0)
	return yard.camera.unproject_position(at)


func test_tapping_a_machine_shows_its_label_and_shelve_returns_it() -> void:
	var machine := _place_one()
	await get_tree().process_frame
	yard.tap(_screen_of(machine))
	await get_tree().process_frame
	assert_true(yard.hud.machine_label_shown(), "tapped: the label shows")
	assert_eq(yard.hud._label_rate.text, UiTheme.rate(0.9))
	yard.hud.shelve_pressed.emit()
	assert_eq(yard.park.placed.size(), 0)
	assert_eq(yard.park.shelf_count(&"conveyor"), 1)
	assert_false(yard.hud.machine_label_shown())


func test_move_picks_the_machine_up_into_placement() -> void:
	var machine := _place_one()
	await get_tree().process_frame
	yard.tap(_screen_of(machine))
	yard.hud.move_pressed.emit()
	assert_eq(yard.park.placed.size(), 0)
	assert_not_null(yard.placing, "straight into placement")
	assert_eq(yard.placing.spec.id, &"conveyor")


func test_tapping_empty_ground_clears_the_selection() -> void:
	var machine := _place_one()
	await get_tree().process_frame
	yard.tap(_screen_of(machine))
	yard.camera.set_view(yard.camera.yaw + PI, deg_to_rad(60.0), 12.0)
	yard.tap(Vector2(10, 10))
	await get_tree().process_frame
	assert_false(yard.hud.machine_label_shown())


func test_rate_counts_digging_machines_and_the_boost() -> void:
	assert_eq(yard.hay_per_s(), 0.0)
	_place_one()
	assert_almost_eq(yard.hay_per_s(), 0.9, 0.001)
	yard.state.grant_boost()
	assert_almost_eq(yard.hay_per_s(), 1.8, 0.001)
	await get_tree().process_frame
	assert_string_contains(yard.hud.rate_label.text, "+1.8/s · 2× ")


# --- Notice line --------------------------------------------------------------------------

func test_notices_queue_and_a_sticky_one_waits_for_clear() -> void:
	var hud := yard.hud
	hud.notice("Restored your last save")
	hud.notice("Restored your last save")  # no duplicates
	hud.notice("Away: +3 hay")
	assert_eq(hud.notice_text(), "Restored your last save")
	hud._process(YardHud.NOTICE_S + 0.1)
	assert_eq(hud.notice_text(), "Away: +3 hay", "next after 4 s")
	hud.notice("Storage is full, progress isn't saving", YardHud.NoticeKind.WARNING, true)
	assert_eq(hud.notice_text(), "Storage is full, progress isn't saving", "a warning shows at once")
	hud._process(YardHud.NOTICE_S + 1.0)
	assert_eq(hud.notice_text(), "Storage is full, progress isn't saving", "sticky: stays")
	hud.clear_sticky()
	assert_eq(hud.notice_text(), "")


# --- Mute ---------------------------------------------------------------------------------

func test_mute_persists_apart_from_the_save() -> void:
	var path := Settings.path
	Settings.path = "user://test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	assert_false(Settings.muted(), "sound on by default")
	yard.hud.mute_pressed.emit()
	assert_true(Settings.muted())
	assert_true(AudioServer.is_bus_mute(0))
	yard.hud.mute_pressed.emit()
	assert_false(AudioServer.is_bus_mute(0))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.path = path
