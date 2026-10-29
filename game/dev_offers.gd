class_name DevOffers
extends CanvasLayer
## G8 stand-ins for the rewarded offers and Privacy options that live on G9's screens (design
## D17): "Double hay · 10 min" (the Shop plate), 2× away hay (the away sheet's ghost button) and
## Privacy options (Settings). Each shows only when its offer is live; G9 moves them.

signal double_hay_pressed
signal double_away_pressed
signal privacy_pressed

var _double_hay: Button
var _double_away: Button
var _privacy: Button


func _ready() -> void:
	var dp := YardHud.DP
	var column := VBoxContainer.new()
	column.anchor_left = 1.0
	column.anchor_right = 1.0
	column.offset_left = -(16 + 200) * dp
	column.offset_right = -16 * dp
	column.offset_top = 200 * dp
	column.add_theme_constant_override("separation", int(8 * dp))
	add_child(column)
	_double_hay = _button("DEV · DOUBLE HAY · 10 MIN", "Watch a video: double hay for 10 minutes", double_hay_pressed)
	_double_away = _button("", "Watch a video: double the hay from your time away", double_away_pressed)
	_privacy = _button("DEV · PRIVACY OPTIONS", "Privacy options", privacy_pressed)
	for button in [_double_hay, _double_away, _privacy]:
		column.add_child(button)


func refresh(double_hay: bool, away_hay: int, privacy: bool) -> void:
	_double_hay.visible = double_hay
	_double_away.visible = away_hay > 0
	_double_away.text = "DEV · 2× AWAY HAY (+%d)" % away_hay
	_privacy.visible = privacy


func _button(text: String, accessible: String, pressed: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.accessibility_name = accessible
	button.custom_minimum_size = Vector2(0, 48 * YardHud.DP)
	button.add_theme_font_size_override("font_size", int(13 * YardHud.DP))
	button.pressed.connect(pressed.emit)
	button.visible = false
	return button
