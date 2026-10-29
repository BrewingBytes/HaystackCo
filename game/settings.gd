class_name Settings
extends RefCounted
## Device preferences, kept apart from the game save (a restored or fresh save never changes
## them): sound for now; G9b adds haptics and reduce motion. Sound is on by default (DESIGN.md
## "Mute": sound on is the wind-down default).

static var path := "user://settings.cfg"


static func muted() -> bool:
	var config := ConfigFile.new()
	return config.load(path) == OK and config.get_value("sound", "muted", false) == true


static func set_muted(on: bool) -> void:
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("sound", "muted", on)
	config.save(path)
	apply()


static func apply() -> void:
	AudioServer.set_bus_mute(0, muted())
