extends GutTest
## G7: while machines catch up on a worker thread after a resume, the yard is held still. Its
## HUD buttons must not act then: PLACE would add to the machine list the worker is stepping
## and Buy would spend from the wallet the worker is crediting.
# Found by /review on 2026-10-28: the hold stopped the yard's own input but not its HUD.


func _click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_tree().root.push_input(motion, true)
	await get_tree().process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		get_tree().root.push_input(click, true)
		await get_tree().process_frame


func test_held_yard_ignores_its_buttons() -> void:
	var yard := Yard.new()
	add_child_autofree(yard)
	await yard.generate(128, false)
	yard.wallet.credit(5 * yard.economy.item(&"conveyor").price * yard.economy.units_per_hay)
	var hay := yard.wallet.hay
	yard.hud.layer = 128  # above GUT's runner panel, which covers the right of the window
	await get_tree().process_frame
	# A locked tray tool opens the Shop.
	var cell_at: Vector2 = yard.hud.cells[&"pitchfork"].get_global_rect().get_center()
	yard.hold(true)
	await _click(cell_at)
	assert_false(yard.hud.shop.visible, "held: the tray does nothing")
	yard.hold(false)
	await _click(cell_at)
	assert_true(yard.hud.shop.visible, "released: a locked tool opens the Shop")
	await get_tree().process_frame
	var buy := _buy_button(yard.hud.shop, "conveyor")
	var buy_at := buy.get_global_rect().get_center()
	yard.hold(true)
	await _click(buy_at)
	assert_eq(yard.wallet.hay, hay, "held: Buy does nothing")
	assert_null(yard.placing)
	yard.hold(false)
	await _click(buy_at)
	assert_lt(yard.wallet.hay, hay, "released: Buy works again")
	assert_not_null(yard.placing)


func _buy_button(shop: ShopScreen, id: String) -> Button:
	for b: Button in shop.find_children("*", "Button", true, false):
		if b.accessibility_name.begins_with("Buy %s" % id):
			return b
	return null
