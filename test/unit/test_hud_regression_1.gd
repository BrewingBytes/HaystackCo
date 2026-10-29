extends GutTest
## G9a QA regressions (DESIGN.md Shop, Navigation, Notice line).
# Found by /qa on 2026-10-29
# Report: .gstack/qa-reports/g9a/qa-report-g9a-hud-2026-10-29.md


func _press(at: Vector2, pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.position = at
	click.global_position = at
	get_tree().root.push_input(click, true)


# Regression: ISSUE-001 — every hay change rebuilt the Shop's list, so a Buy press that spanned
# a hay tick (any digging machine) landed on a freed button and did nothing.
func test_a_buy_press_survives_hay_arriving() -> void:
	var yard := Yard.new()
	add_child_autofree(yard)
	await yard.generate(128, false)
	yard.hud.layer = 128  # above GUT's runner panel
	yard.wallet.credit(30_000 * yard.economy.units_per_hay)
	yard.open_shop()
	await get_tree().process_frame
	await get_tree().process_frame
	var buy: Button
	for b: Button in yard.hud.shop.find_children("*", "Button", true, false):
		if b.accessibility_name.begins_with("Buy pitchfork"):
			buy = b
	var at := buy.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_tree().root.push_input(motion, true)
	await get_tree().process_frame
	_press(at, true)
	await get_tree().process_frame
	yard.wallet.credit(1 * yard.economy.units_per_hay)  # a machine earns 1 hay mid-press
	await get_tree().process_frame
	await get_tree().process_frame
	_press(at, false)
	await get_tree().process_frame
	assert_true(yard.inventory.owns(&"pitchfork"), "the press bought the pitchfork")


# Regression: ISSUE-002 — Godot quits on Android Back by default, so Back with the Shop open
# closed the game. Back closes the top screen; on the Yard it does nothing (DESIGN.md).
func test_back_never_quits_the_game() -> void:
	assert_false(ProjectSettings.get_setting("application/config/quit_on_go_back", true))


# Regression: ISSUE-003 — on the 720-wide phone canvas a notice covered PING for 4 s.
func test_a_notice_never_covers_ping() -> void:
	get_tree().root.size = Vector2i(720, 1600)
	await get_tree().process_frame
	var yard := Yard.new()
	add_child_autofree(yard)
	await yard.generate(128, false)
	yard.hud.set_ping_visible(true)
	yard.hud.notice("Couldn't load your save, starting fresh")
	await get_tree().process_frame
	assert_false(yard.hud._notice.get_global_rect().intersects(yard.hud._ping.get_global_rect()))
