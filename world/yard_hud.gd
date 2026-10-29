class_name YardHud
extends CanvasLayer
## The Yard HUD (DESIGN.md "Layout", "Components"; design D3, D4, D7, D8, D12, D13): the hay
## counter with its rate, "PILE n", the top-right column (mute, SHOP, recenter), the measured
## fades, the five-cell tool tray, the placement bar that replaces it while placing, the ⟳
## beside the ghost, the notice line, the label anchored over a tapped machine, and PING above
## the DETECTOR cell. It shows what the yard tells it; every press is a signal.

signal place_pressed
signal cancel_pressed
signal turn_pressed
signal recenter_pressed
signal ping_pressed
signal tool_pressed(id: StringName)
signal shop_pressed
signal mute_pressed
signal move_pressed
signal shelve_pressed

const DP := UiTheme.DP
const TRAY_DP := 76.0
const MARGIN_DP := 16.0
const COLUMN_STEP_DP := 56.0
const NOTICE_S := 4.0
const PULSE_S := 0.6
const COUNTER_TICK_S := 0.6
const FINGER_SLOP_DP := 24.0
const TOP_SOLID_DP := 64.0
const TOP_EASE_DP := 76.0  # 64 → 140dp
const TRAY_LABEL_MAX_SCALE := 1.3  # design D13: one-word labels fit a 72dp cell at 200% font
const COUNTER_MAX_SCALE := 56.0 / 44.0  # the counter caps at 56sp

# Colors kept for the G8 stand-ins (PileCard, DevOffers) until G9c restyles them.
const GROUND := UiTheme.GROUND
const RAISED := UiTheme.RAISED
const TEXT := UiTheme.TEXT
const TEXT_MUTED := UiTheme.TEXT_MUTED
const ACTION := UiTheme.ACTION
const ACTION_PRESSED := UiTheme.ACTION_PRESSED
const ON_ACTION := UiTheme.ON_ACTION
const LINE := UiTheme.LINE

class ToolCell:
	extends Button
	var id: StringName
	var icon_rect: TextureRect
	var name_label: Label
	var lock_row: HBoxContainer
	var price_label: Label
	var outline: Panel


var counter: Label
var rate_label: Label
var pile_label: Label
var tray: HBoxContainer
var cells := {}  # StringName → ToolCell
var shop: ShopScreen

var _top: VBoxContainer  # counter, rate (and "PILE n" at large font)
var _top_solid: ColorRect
var _top_ease: TextureRect
var _column: VBoxContainer
var _mute: Button
var _shop_button: Button
var _shop_outline: StyleBoxFlat
var _recenter: Button
var _tray_panel: PanelContainer
var _bar: PanelContainer
var _name: Label
var _place: Button
var _turn: Button
var _ping: Button
var _notice: PanelContainer
var _notice_icon: TextureRect
var _notice_text: Label
var _notice_left := 0.0
var _notice_sticky := false
var _notices: Array[Dictionary] = []
var _label: PanelContainer  # anchored over a tapped machine
var _label_name: Label
var _label_rate: Label
var _pulse_t := -1.0
var _cue := false
var _shown_hay := -1.0
var _target_hay := 0
var _tick_from := 0.0
var _reduce_motion := false


func _ready() -> void:
	_build_fades()
	_build_top()
	_build_column()
	_build_tray()
	_build_bar()
	_build_notice()
	_build_label()
	_ping = UiTheme.button("PING", UiTheme.Kind.GHOST, "Watch a video for a detector ping")
	_ping.custom_minimum_size = Vector2(72, 48) * DP
	_anchor_bottom_right(_ping, 72, 48, TRAY_DP + 4)
	_ping.visible = false
	_ping.pressed.connect(ping_pressed.emit)
	add_child(_ping)
	shop = ShopScreen.new()
	shop.name = "Shop"
	add_child(shop)


# --- Building -----------------------------------------------------------------------------

## Design D12: `ground` at 90% from the top to 64dp, easing to 0% by 140dp; the same mirrored
## from the tray up 56dp. No text shadow, outline or blur. At large font the counter block
## grows, so the solid band reaches 8dp below it and the 76dp ease follows.
func _build_fades() -> void:
	_top_solid = ColorRect.new()
	_top_solid.color = Color(GROUND, 0.9)
	_top_solid.anchor_right = 1.0
	_top_solid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_solid)
	_top_ease = _fade([0.0, 1.0], [0.9, 0.0], TOP_EASE_DP)
	_top_ease.anchor_right = 1.0
	add_child(_top_ease)
	_set_top_band(TOP_SOLID_DP * DP)
	var bottom := _fade([0.0, 1.0], [0.0, 0.9], 56)
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_top = -(TRAY_DP + 56) * DP
	bottom.offset_bottom = -TRAY_DP * DP
	add_child(bottom)


func _set_top_band(solid: float) -> void:
	_top_solid.offset_bottom = solid
	_top_ease.offset_top = solid
	_top_ease.offset_bottom = solid + TOP_EASE_DP * DP


func _fade(offsets: Array, alphas: Array, height_dp: float) -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	var colors := PackedColorArray()
	for a: float in alphas:
		colors.append(Color(GROUND, a))
	gradient.colors = colors
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 256
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.offset_bottom = height_dp * DP
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _build_top() -> void:
	_top = VBoxContainer.new()
	_top.position = Vector2(MARGIN_DP, 12) * DP
	_top.add_theme_constant_override("separation", 0)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(6 * DP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(row)
	var glyph := TextureRect.new()
	glyph.texture = UiTheme.icon("hay")
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.custom_minimum_size = Vector2(28, 28) * DP
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)
	counter = UiTheme.label(UiTheme.Style.DISPLAY, "0", UiTheme.TEXT, COUNTER_MAX_SCALE)
	row.add_child(counter)
	rate_label = UiTheme.label(UiTheme.Style.MONO, "", UiTheme.TEXT_MUTED)
	_top.add_child(rate_label)
	pile_label = UiTheme.label(UiTheme.Style.LABEL, "PILE 1")
	# "PILE n" sits top-center; at font scale ≥ 1.5 it moves under the rate (DESIGN.md).
	if UiTheme.font_scale() >= 1.5:
		_top.add_child(pile_label)
	else:
		pile_label.anchor_left = 0.5
		pile_label.anchor_right = 0.5
		pile_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		pile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pile_label.offset_top = 28 * DP
		add_child(pile_label)
	pile_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Top right, 48dp controls: mute, SHOP, recenter (only when the camera is off its default).
func _build_column() -> void:
	_column = VBoxContainer.new()
	_column.anchor_left = 1.0
	_column.anchor_right = 1.0
	_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_column.offset_right = -MARGIN_DP * DP
	_column.offset_top = 12 * DP
	_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	_column.add_theme_constant_override("separation", int((COLUMN_STEP_DP - 48) * DP))
	add_child(_column)
	_mute = _icon_button("sound_on", "Sound on. Tap to mute")
	_mute.pressed.connect(mute_pressed.emit)
	_column.add_child(_mute)
	_shop_button = UiTheme.button("SHOP", UiTheme.Kind.GHOST, "Shop")
	_shop_button.icon = UiTheme.icon("hay")
	_shop_button.expand_icon = false
	_shop_button.add_theme_constant_override("icon_max_width", int(14 * DP))
	_shop_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_shop_outline = UiTheme.flat(UiTheme.GROUND, UiTheme.TEXT, 2)
	_shop_button.pressed.connect(shop_pressed.emit)
	_column.add_child(_shop_button)
	_recenter = _icon_button("recenter", "Recenter the camera")
	_recenter.pressed.connect(recenter_pressed.emit)
	_recenter.visible = false
	_column.add_child(_recenter)


func _icon_button(icon_name: String, accessible: String) -> Button:
	var b := Button.new()
	b.icon = UiTheme.icon(icon_name)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(48, 48) * DP
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.accessibility_name = accessible
	b.add_theme_stylebox_override("normal", UiTheme.flat(Color(GROUND, 0.0), Color.TRANSPARENT, 0, 10, 10))
	b.add_theme_stylebox_override("hover", UiTheme.flat(Color(RAISED, 0.6), Color.TRANSPARENT, 0, 10, 10))
	b.add_theme_stylebox_override("pressed", UiTheme.flat(RAISED, Color.TRANSPARENT, 0, 10, 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("icon_normal_color", TEXT)
	b.add_theme_color_override("icon_hover_color", TEXT)
	b.add_theme_color_override("icon_pressed_color", TEXT)
	return b


## The tray: a five-cell title block, 76dp, full width; it never changes height.
func _build_tray() -> void:
	_tray_panel = PanelContainer.new()
	var box := UiTheme.flat(GROUND, Color.TRANSPARENT, 0, 0, 0)
	box.border_color = UiTheme.LINE
	box.border_width_top = int(DP)
	box.set_corner_radius_all(0)
	_tray_panel.add_theme_stylebox_override("panel", box)
	_anchor_bottom_bar(_tray_panel)
	add_child(_tray_panel)
	tray = HBoxContainer.new()
	tray.add_theme_constant_override("separation", 0)
	_tray_panel.add_child(tray)


## One cell per hand tool, in catalog order (prices rise left to right).
func set_tools(economy: Economy) -> void:
	for child in tray.get_children():
		child.queue_free()
	cells.clear()
	for it in economy.items:
		if it.machine != null:
			continue
		var cell := _tool_cell(it.id)
		tray.add_child(cell)
		cells[it.id] = cell


func _tool_cell(id: StringName) -> ToolCell:
	var cell := ToolCell.new()
	cell.id = id
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size = Vector2(0, TRAY_DP * DP)
	cell.add_theme_stylebox_override("normal", _cell_box(GROUND))
	cell.add_theme_stylebox_override("hover", _cell_box(GROUND))
	cell.add_theme_stylebox_override("pressed", _cell_box(RAISED))
	cell.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	cell.pressed.connect(func() -> void: tool_pressed.emit(id))
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", int(4 * DP))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(column)
	cell.icon_rect = TextureRect.new()
	cell.icon_rect.texture = UiTheme.icon(String(id))
	cell.icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cell.icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cell.icon_rect.custom_minimum_size = Vector2(28, 28) * DP
	cell.icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(cell.icon_rect)
	cell.name_label = UiTheme.label(UiTheme.Style.LABEL, String(id), TEXT_MUTED, TRAY_LABEL_MAX_SCALE)
	cell.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit(cell.name_label, (72 - 8) * DP)
	column.add_child(cell.name_label)
	cell.lock_row = HBoxContainer.new()
	cell.lock_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.lock_row.add_theme_constant_override("separation", int(2 * DP))
	cell.lock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lock := TextureRect.new()
	lock.texture = UiTheme.icon("lock")
	lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lock.custom_minimum_size = Vector2(12, 12) * DP
	lock.modulate = TEXT_MUTED
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.lock_row.add_child(lock)
	cell.price_label = UiTheme.label(UiTheme.Style.COUNT, "", TEXT_MUTED, TRAY_LABEL_MAX_SCALE)
	cell.price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.lock_row.add_child(cell.price_label)
	column.add_child(cell.lock_row)
	# Selected: a 2dp `text` outline inset 6dp.
	cell.outline = Panel.new()
	cell.outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cell.outline.offset_left = 6 * DP
	cell.outline.offset_top = 6 * DP
	cell.outline.offset_right = -6 * DP
	cell.outline.offset_bottom = -6 * DP
	cell.outline.add_theme_stylebox_override("panel", UiTheme.flat(Color.TRANSPARENT, TEXT, 2, 0, 0))
	cell.outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(cell.outline)
	return cell


func _cell_box(fill: Color) -> StyleBoxFlat:
	var box := UiTheme.flat(fill, UiTheme.HAIRLINE, 0, 0, 0)
	box.border_width_left = int(DP * 0.5)
	box.border_width_right = int(DP * 0.5)
	box.set_corner_radius_all(0)
	return box


## Shrinks a label's font until its text fits `width` (canvas units).
static func _fit(l: Label, width: float) -> void:
	var font: Font = l.get_theme_font("font")
	var font_size := l.get_theme_font_size("font_size")
	while font_size > 16 and font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 1
	l.add_theme_font_size_override("font_size", font_size)


## Placement bar (design D4): replaces the tray, same height: name | PLACE | Cancel.
func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", UiTheme.flat(GROUND, LINE, 1, 16, 14))
	_anchor_bottom_bar(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(12 * DP))
	_bar.add_child(row)
	_name = UiTheme.label(UiTheme.Style.LABEL, "", TEXT, 1.5)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.clip_text = true
	row.add_child(_name)
	_place = UiTheme.button("PLACE", UiTheme.Kind.PRIMARY, "Place the machine here")
	_place.custom_minimum_size.x = 96 * DP
	_place.pressed.connect(place_pressed.emit)
	row.add_child(_place)
	var cancel := UiTheme.button("Cancel", UiTheme.Kind.GHOST, "Cancel placing; the machine goes back on the shelf")
	cancel.pressed.connect(cancel_pressed.emit)
	row.add_child(cancel)
	add_child(_bar)
	_bar.visible = false
	_turn = _icon_button("turn", "Turn the machine 45 degrees")
	_turn.add_theme_stylebox_override("normal", UiTheme.flat(GROUND, LINE, 1, 10, 10))
	_turn.visible = false
	add_child(_turn)


func _anchor_bottom_bar(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_top = -TRAY_DP * DP


func _anchor_bottom_right(c: Control, w_dp: float, h_dp: float, above_dp: float) -> void:
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = -(MARGIN_DP + w_dp) * DP
	c.offset_right = -MARGIN_DP * DP
	c.offset_top = -(above_dp + h_dp) * DP
	c.offset_bottom = -above_dp * DP


## Notice line: one line on a `notice` plate 8dp above the tray, icon + body text, 4 s.
func _build_notice() -> void:
	_notice = PanelContainer.new()
	_notice.add_theme_stylebox_override("panel", UiTheme.flat(GROUND, LINE, 1, 12, 8))
	_notice.anchor_left = 0.5
	_notice.anchor_right = 0.5
	_notice.anchor_top = 1.0
	_notice.anchor_bottom = 1.0
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notice.offset_bottom = -(TRAY_DP + 8) * DP
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * DP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.add_child(row)
	_notice_icon = TextureRect.new()
	_notice_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_notice_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_notice_icon.custom_minimum_size = Vector2(20, 20) * DP
	_notice_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_notice_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_notice_icon)
	_notice_text = UiTheme.label(UiTheme.Style.BODY, "", TEXT, 1.5)
	_notice_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Announced to accessibility services as it appears.
	if "accessibility_live" in _notice_text:
		_notice_text.set("accessibility_live", DisplayServer.LIVE_POLITE)
	row.add_child(_notice_text)
	add_child(_notice)
	_notice.visible = false


## The label anchored over a tapped machine: name, rate in mono, Move, Shelve.
func _build_label() -> void:
	_label = PanelContainer.new()
	_label.add_theme_stylebox_override("panel", UiTheme.plate(10))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(8 * DP))
	_label.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(12 * DP))
	column.add_child(head)
	_label_name = UiTheme.label(UiTheme.Style.LABEL, "", TEXT, 1.5)
	_label_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_label_name)
	_label_rate = UiTheme.label(UiTheme.Style.MONO, "", TEXT_MUTED, 1.5)
	head.add_child(_label_rate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * DP))
	column.add_child(row)
	var move := UiTheme.button("Move", UiTheme.Kind.GHOST, "Move this machine")
	move.pressed.connect(move_pressed.emit)
	row.add_child(move)
	var shelve := UiTheme.button("Shelve", UiTheme.Kind.GHOST, "Put this machine back on the shelf")
	shelve.pressed.connect(shelve_pressed.emit)
	row.add_child(shelve)
	add_child(_label)
	_label.visible = false


# --- State from the yard ------------------------------------------------------------------

## Once a frame: the wallet, the rate (hay/s from digging machines, boost included), the
## 2× reward's time left, the pile number, the owned tools and the selected one, the shelf.
func show_state(hay: int, hay_per_s: float, boost_ms: int, pile: int, inventory: Inventory, economy: Economy, tool: StringName, shelf: int, delta: float) -> void:
	_reduce_motion = A11y.system_reduce_motion()
	_tick_counter(hay, delta)
	var rate_parts := PackedStringArray()
	if hay_per_s > 0.0:
		rate_parts.append(UiTheme.rate(hay_per_s))
	if boost_ms > 0:
		rate_parts.append("2× " + UiTheme.clock(boost_ms))
	rate_label.text = " · ".join(rate_parts)
	UiTheme.style_figure(rate_label)
	rate_label.accessibility_name = "Hay per second " + rate_label.text
	pile_label.text = "PILE %d" % pile
	for id: StringName in cells:
		var cell: ToolCell = cells[id]
		var owned := inventory.owns(id)
		var selected := owned and id == tool
		cell.name_label.visible = owned
		cell.lock_row.visible = not owned
		cell.price_label.text = UiTheme.grouped(economy.item(id).price)
		cell.icon_rect.modulate = Color(TEXT, 1.0 if selected else (0.75 if owned else 0.35))
		cell.name_label.add_theme_color_override("font_color", TEXT if selected else TEXT_MUTED)
		cell.outline.visible = selected
		cell.accessibility_name = "%s%s" % [String(id).capitalize(), ", selected" if selected else ("" if owned else ", locked, %s hay" % UiTheme.grouped(economy.item(id).price))]
	_shop_button.text = "SHOP · %d" % shelf if shelf > 0 else "SHOP"
	_shop_button.accessibility_name = "Shop, %d machines to place" % shelf if shelf > 0 else "Shop"


## The counter ticks up over 600 ms toward the wallet (it jumps under reduced motion);
## spending shows at once. Full digits to 999,999, then "1.24M".
func _tick_counter(hay: int, delta: float) -> void:
	if _shown_hay < 0.0 or _reduce_motion or hay < _shown_hay:
		_shown_hay = hay
	elif hay > _target_hay:
		_tick_from = _shown_hay  # a new gain: tick from where the counter stands
	_target_hay = hay
	if _shown_hay < hay:
		_shown_hay = minf(hay, _shown_hay + maxf(1.0, (hay - _tick_from) * delta / COUNTER_TICK_S))
	counter.text = UiTheme.abbreviated(int(_shown_hay))
	counter.accessibility_name = "%s hay" % UiTheme.grouped(hay)


func set_muted(muted: bool) -> void:
	_mute.icon = UiTheme.icon("sound_off" if muted else "sound_on")
	_mute.accessibility_name = "Sound off. Tap to unmute" if muted else "Sound on. Tap to mute"


## Design D8: the first time anything is affordable, SHOP's outline pulses twice (600 ms each;
## static under reduced motion) and stays until the first Shop visit.
func set_shop_cue(on: bool) -> void:
	if on == _cue:
		return
	_cue = on
	_pulse_t = 0.0 if on else -1.0
	_shop_button.add_theme_stylebox_override("normal", _shop_outline if on else UiTheme.flat(GROUND, LINE, 1))
	_shop_outline.border_color = TEXT


func _process(delta: float) -> void:
	_set_top_band(maxf(TOP_SOLID_DP * DP, _top.position.y + _top.size.y + 8 * DP))
	if _pulse_t >= 0.0:
		if _reduce_motion:
			_pulse_t = -1.0
			_shop_outline.border_color = TEXT
		else:
			_pulse_t += delta
			var phase := fmod(_pulse_t, PULSE_S) / PULSE_S
			_shop_outline.border_color = Color(TEXT, 0.25 + 0.75 * absf(cos(phase * PI)))
			if _pulse_t >= 2.0 * PULSE_S:
				_pulse_t = -1.0
				_shop_outline.border_color = TEXT
	if _notice.visible and not _notice_sticky:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_next_notice()


# --- Notice line --------------------------------------------------------------------------

enum NoticeKind { INFO, WARNING }

## Queues a notice. A sticky one stays until clear_sticky() (storage full: until a save works).
func notice(text: String, kind := NoticeKind.INFO, sticky := false) -> void:
	for queued in _notices:
		if queued.text == text:
			return
	if _notice.visible and _notice_text.text == text:
		return
	_notices.append({text = text, kind = kind, sticky = sticky})
	if not _notice.visible or (not _notice_sticky and sticky):
		_next_notice()


func clear_sticky() -> void:
	if _notice_sticky:
		_notice_sticky = false
		_next_notice()


func notice_text() -> String:
	return _notice_text.accessibility_name if _notice.visible else ""


func _next_notice() -> void:
	if _notices.is_empty():
		_notice.visible = false
		_notice_sticky = false
		return
	var n: Dictionary = _notices.pop_front()
	# One line where it fits; at large font it wraps inside the screen's 16dp margins.
	var room := get_viewport().get_visible_rect().size.x - (2 * MARGIN_DP + 2 * 12 + 20 + 8) * DP
	_notice_text.text = _wrapped(n.text, room)
	_notice_text.accessibility_name = n.text
	_notice_icon.texture = UiTheme.icon("warning" if n.kind == NoticeKind.WARNING else "info")
	_notice_sticky = n.sticky
	_notice_left = NOTICE_S
	_notice.visible = true
	var need := _notice.get_combined_minimum_size()
	_notice.offset_left = -need.x * 0.5
	_notice.offset_right = need.x * 0.5
	_place_notice()


## 8dp above the tray, or above PING while PING shows (the notice never covers it).
func _place_notice() -> void:
	var need := _notice.get_combined_minimum_size()
	var above := TRAY_DP + 8 + (48 + 8 if _ping != null and _ping.visible else 0)
	_notice.offset_bottom = -above * DP
	_notice.offset_top = _notice.offset_bottom - need.y


## Breaks `text` into lines no wider than `width` at the notice's font (word wrap).
func _wrapped(text: String, width: float) -> String:
	var font: Font = _notice_text.get_theme_font("font")
	var font_size := _notice_text.get_theme_font_size("font_size")
	var lines := PackedStringArray()
	var line := ""
	for word in text.split(" "):
		var candidate := word if line.is_empty() else line + " " + word
		if not line.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			lines.append(line)
			line = word
		else:
			line = candidate
	lines.append(line)
	return "\n".join(lines)


## Never over the finger: a touch on or near the notice hides it while it's there.
func _input(event: InputEvent) -> void:
	if not _notice.visible:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		var near := _notice.get_global_rect().grow(FINGER_SLOP_DP * DP).has_point(event.position)
		var down: bool = event is InputEventScreenDrag or event.pressed
		_notice.modulate.a = 0.0 if near and down else 1.0


# --- Placement ----------------------------------------------------------------------------

func show_placement(machine_name: String) -> void:
	_name.text = machine_name.to_upper()
	_bar.visible = true
	_turn.visible = true
	_tray_panel.visible = false
	hide_machine_label()


func hide_placement() -> void:
	_bar.visible = false
	_turn.visible = false
	_tray_panel.visible = true


func set_can_place(can_place: bool) -> void:
	_place.disabled = not can_place


func placement_shown() -> bool:
	return _bar.visible


## Keeps ⟳ beside the ghost (screen position of the ghost, in viewport pixels).
func set_turn_anchor(screen_pos: Vector2, viewport_size: Vector2) -> void:
	_turn.position = _canvas_anchor(screen_pos, viewport_size, _turn.custom_minimum_size, Vector2(40 * DP, -_turn.custom_minimum_size.y * 0.5))


func _canvas_anchor(screen_pos: Vector2, viewport_size: Vector2, size: Vector2, offset: Vector2) -> Vector2:
	var visible_rect := get_viewport().get_visible_rect().size
	var canvas := screen_pos * (visible_rect / viewport_size)
	var at := canvas + offset
	return at.clamp(Vector2(8 * DP, 160 * DP), visible_rect - size - Vector2(8 * DP, (TRAY_DP + 8) * DP))


# --- Machine label ------------------------------------------------------------------------

## Shows the label over a placed machine at `screen_pos` (its top, in viewport pixels).
func show_machine_label(machine_name: String, rate_text: String, screen_pos: Vector2, viewport_size: Vector2) -> void:
	_label_name.text = machine_name.to_upper()
	_label_rate.text = rate_text
	UiTheme.style_figure(_label_rate, TEXT_MUTED, 1.5)
	_label.visible = true
	_label.reset_size()
	var size := _label.get_combined_minimum_size()
	_label.position = _canvas_anchor(screen_pos, viewport_size, size, Vector2(-size.x * 0.5, -size.y - 12 * DP))


func hide_machine_label() -> void:
	_label.visible = false


func machine_label_shown() -> bool:
	return _label.visible


# --- Other --------------------------------------------------------------------------------

func set_ping_visible(on: bool) -> void:
	var show := on and not _bar.visible and not shop.visible
	if show != _ping.visible:
		_ping.visible = show
		if _notice.visible:
			_place_notice()


func set_recenter_visible(on: bool) -> void:
	_recenter.visible = on


## True if a touch at `screen_pos` lands on a visible control (the yard ignores it). The Shop
## covers the whole screen.
func blocks(screen_pos: Vector2) -> bool:
	if shop.visible:
		return true
	for control: Control in [_bar, _tray_panel, _turn, _mute, _shop_button, _recenter, _ping, _label]:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(screen_pos):
			return true
	return false
