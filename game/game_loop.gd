class_name GameLoop
extends RefCounted
## Test Lab Game Loop hooks from the HaystackHelpers Android plugin, plus a desktop fallback
## (`godot -- --scenario=N`). Off Android, results only go to user://.

const PLUGIN := "HaystackHelpers"


static func _plugin() -> Object:
	return Engine.get_singleton(PLUGIN) if Engine.has_singleton(PLUGIN) else null


## The requested autoplay scenario, or 0 for a normal launch.
static func scenario() -> int:
	var plugin := _plugin()
	if plugin:
		var from_intent: int = plugin.getLaunchScenario()
		if from_intent > 0:
			return from_intent
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			return arg.get_slice("=", 1).to_int()
	return 0


## Android thermal status (0 none … 6 shutdown); -1 when unknown.
static func thermal_status() -> int:
	var plugin := _plugin()
	return plugin.getThermalStatus() if plugin else -1


## Writes the results file Test Lab collects. False when not launched by Test Lab.
static func write_results(json: String) -> bool:
	var plugin := _plugin()
	return plugin.writeLoopResults(json) if plugin else false


## Ends the loop: Test Lab waits for the activity to finish.
static func finish(tree: SceneTree) -> void:
	var plugin := _plugin()
	if plugin:
		plugin.finishLoop()
	else:
		tree.quit()
