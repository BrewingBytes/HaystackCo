class_name PileCard
extends CanvasLayer
## G8 stand-in for the "PILE n CLEARED" card (DESIGN.md "Pile done", eng D7): hay from the pile,
## needles found, and "Next pile", which reads "Loading…" while the ad check and pile n+1
## finish. G9 restyles it; the flow stays.

signal next_pressed

var _title: Label
var _summary: Label
var _next: Button


func _ready() -> void:
	layer = 10
	var dp := YardHud.DP
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = YardHud.GROUND
	box.border_color = YardHud.LINE
	box.set_border_width_all(int(dp))
	box.set_content_margin_all(24 * dp)
	panel.add_theme_stylebox_override("panel", box)
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = 24 * dp
	panel.offset_right = -24 * dp
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(16 * dp))
	panel.add_child(column)
	_title = _label(28 * dp, YardHud.TEXT)
	column.add_child(_title)
	_summary = _label(15 * dp, YardHud.TEXT_MUTED)
	column.add_child(_summary)
	_next = Button.new()
	_next.custom_minimum_size = Vector2(0, 56 * dp)
	_next.add_theme_font_size_override("font_size", int(17 * dp))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill := StyleBoxFlat.new()
		fill.bg_color = YardHud.ACTION_PRESSED if state == "pressed" else (YardHud.RAISED if state == "disabled" else YardHud.ACTION)
		_next.add_theme_stylebox_override(state, fill)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_next.add_theme_color_override(state, YardHud.ON_ACTION)
	_next.add_theme_color_override("font_disabled_color", YardHud.TEXT_MUTED)
	_next.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_next.pressed.connect(next_pressed.emit)
	column.add_child(_next)
	visible = false


func show_for(pile: int, hay: int, needles: int) -> void:
	_title.text = "PILE %d CLEARED" % pile
	_summary.text = "+%d hay · %d %s found" % [hay, needles, "needle" if needles == 1 else "needles"]
	set_loading(false)
	visible = true


func set_loading(loading: bool) -> void:
	_next.text = "Loading…" if loading else "Next pile"
	_next.disabled = loading


func _label(size: float, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", int(size))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
