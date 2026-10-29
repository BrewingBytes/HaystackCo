class_name A11y
extends RefCounted
## System accessibility settings from the HaystackHelpers Android plugin (design D14).
## Off Android (editor, desktop, headless tests) every value is the neutral default.

const PLUGIN := "HaystackHelpers"


static func _plugin() -> Object:
	return Engine.get_singleton(PLUGIN) if Engine.has_singleton(PLUGIN) else null


## 1.0 = default; 2.0 = 200% system font.
static func font_scale() -> float:
	var plugin := _plugin()
	return plugin.getFontScale() if plugin else 1.0


## True when "Remove animations" is on (animator duration scale 0).
static func system_reduce_motion() -> bool:
	var plugin := _plugin()
	return plugin.getAnimatorDurationScale() == 0.0 if plugin else false


static func screen_reader_on() -> bool:
	var plugin := _plugin()
	return plugin.isScreenReaderOn() if plugin else false
