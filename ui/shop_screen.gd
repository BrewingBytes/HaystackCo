class_name ShopScreen
extends Control
## The Shop (DESIGN.md "Shop", "Shop plate"; design D4, D18), first-playable stub for G9a: the
## title bar (← · SHOP · hay count), then YOUR MACHINES (only when the shelf has machines;
## "Place"), TOOLS and MACHINES as a single column of plates. Buy is a ghost button; the one
## orange is the first "Place". G9b adds the plate art, the Settings gear, "More soon" and the
## 2× hay plate.

signal buy_pressed(id: StringName)
signal place_pressed(id: StringName)
signal closed

const DP := UiTheme.DP

var _hay: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _plates := {}  # StringName → the item's plate (scroll target)
var _inventory: Inventory
var _park: MachinePark
var _wallet: Wallet
var _economy: Economy
var _shown_hay := -1
var _shown_shelf := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var paper := ColorRect.new()
	paper.color = UiTheme.GROUND
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(paper)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 64 * DP)
	bar.add_theme_constant_override("separation", int(8 * DP))
	column.add_child(_margin(bar, 8, 8))
	var back := Button.new()
	back.text = "←"
	back.accessibility_name = "Back to the yard"
	back.custom_minimum_size = Vector2(48, 48) * DP
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.add_theme_font_override("font", UiTheme.font(UiTheme.Style.BODY))
	back.add_theme_font_size_override("font_size", int(24 * DP))
	for state in ["normal", "hover", "focus"]:
		back.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	back.add_theme_stylebox_override("pressed", UiTheme.flat(UiTheme.RAISED))
	back.add_theme_color_override("font_color", UiTheme.TEXT)
	back.pressed.connect(close)
	bar.add_child(back)
	var title := UiTheme.label(UiTheme.Style.TITLE, "SHOP")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(title)
	var glyph := TextureRect.new()
	glyph.texture = UiTheme.icon("hay")
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.custom_minimum_size = Vector2(14, 14) * DP
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(glyph)
	_hay = UiTheme.label(UiTheme.Style.COUNT, "0")
	_hay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_hay)
	column.add_child(UiTheme.rule())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", int(12 * DP))
	_scroll.add_child(_margin(_list, 16, 16))


func _margin(c: Control, x_dp: float, y_dp: float) -> MarginContainer:
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, int(x_dp * DP))
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, int(y_dp * DP))
	m.add_child(c)
	return m


## Opens over the yard, scrolled to `focus` (a locked tray tool) if given.
func open(inventory: Inventory, park: MachinePark, wallet: Wallet, economy: Economy, focus := &"") -> void:
	_inventory = inventory
	_park = park
	_wallet = wallet
	_economy = economy
	_rebuild()
	visible = true
	_scroll.scroll_vertical = 0
	if _plates.has(focus):
		await get_tree().process_frame
		_scroll.ensure_control_visible(_plates[focus])


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(_delta: float) -> void:
	if visible and (_wallet.hay != _shown_hay or _park.shelf.size() != _shown_shelf):
		_rebuild()


## Android Back closes the Shop.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _rebuild() -> void:
	_shown_hay = _wallet.hay
	_shown_shelf = _park.shelf.size()
	_hay.text = UiTheme.grouped(_wallet.hay)
	_hay.accessibility_name = "%s hay" % _hay.text
	for child in _list.get_children():
		child.queue_free()
	_plates.clear()
	if not _park.shelf.is_empty():
		_section("YOUR MACHINES")
		var first := true
		for it in _economy.items:
			var count := _park.shelf_count(it.id)
			if count > 0:
				_list.add_child(_shelf_plate(it, count, first))
				first = false
	_section("TOOLS")
	for it in _economy.items:
		if it.machine == null:
			_list.add_child(_item_plate(it))
	_section("MACHINES")
	for it in _economy.items:
		if it.machine != null:
			_list.add_child(_item_plate(it))


func _section(text: String) -> void:
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", int(4 * DP))
	head.add_child(UiTheme.label(UiTheme.Style.LABEL, text, UiTheme.TEXT_MUTED, 1.5))
	head.add_child(UiTheme.rule())
	_list.add_child(head)


func _plate(it: Economy.Item, title: String) -> Array:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiTheme.plate(12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(12 * DP))
	plate.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", int(4 * DP))
	row.add_child(text)
	text.add_child(UiTheme.label(UiTheme.Style.LABEL, title, UiTheme.TEXT, 1.5))
	# Some specs have a decimal point, so the whole column is `count` (design D19).
	var spec := UiTheme.label(UiTheme.Style.COUNT, _spec(it), UiTheme.TEXT_MUTED, 1.5)
	spec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(spec)
	_plates[it.id] = plate
	return [plate, row]


func _shelf_plate(it: Economy.Item, count: int, primary: bool) -> PanelContainer:
	var parts := _plate(it, "%s × %d" % [String(it.id), count] if count > 1 else String(it.id))
	var place := UiTheme.button("Place", UiTheme.Kind.PRIMARY if primary else UiTheme.Kind.GHOST, "Place a %s" % it.id)
	place.custom_minimum_size.x = 88 * DP
	place.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	place.pressed.connect(func() -> void: place_pressed.emit(it.id))
	parts[1].add_child(place)
	return parts[0]


## Shop plate: name and spec row; then "Owned · in hand" or the price and a ghost Buy. Short of
## hay, Buy reads in `text-muted` on `raised` with "n more hay" under it (design D18).
func _item_plate(it: Economy.Item) -> PanelContainer:
	var parts := _plate(it, String(it.id))
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", int(4 * DP))
	parts[1].add_child(side)
	if it.machine == null and _inventory.owns(it.id):
		side.add_child(UiTheme.label(UiTheme.Style.LABEL, "Owned · in hand", UiTheme.SUCCESS, 1.5))
		return parts[0]
	var price := UiTheme.grouped(it.price)
	var short := it.price - _wallet.hay
	var buy := UiTheme.button("Buy · " + price, UiTheme.Kind.GHOST, "Buy %s for %s hay" % [it.id, price])
	buy.custom_minimum_size.x = 120 * DP
	if short > 0:
		buy.disabled = true
		buy.accessibility_name += ", %s more hay needed" % UiTheme.grouped(short)
	else:
		buy.add_theme_stylebox_override("normal", UiTheme.flat(UiTheme.GROUND, UiTheme.TEXT, 1))
	buy.pressed.connect(func() -> void: buy_pressed.emit(it.id))
	side.add_child(buy)
	if short > 0:
		var more := UiTheme.label(UiTheme.Style.COUNT, "%s more hay" % UiTheme.grouped(short), UiTheme.TEXT_MUTED, 1.5)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		side.add_child(more)
	return parts[0]


## The spec row, in metres.
func _spec(it: Economy.Item) -> String:
	var m := SpikeConfig.CELL_M
	match it.behavior:
		&"brush":
			return "WIDTH %s M" % UiTheme.decimal(it.brush.radius * 2 * m)
		&"magnet":
			return "PULL %s M" % UiTheme.decimal(it.radius * m)
		&"detector":
			return "RANGE %s M" % UiTheme.decimal(it.radius * m)
		&"conveyor":
			return "REACH %d M · %s" % [roundi(it.machine.reach * m), UiTheme.rate(it.machine.rate / float(_economy.units_per_hay))]
	return ""
