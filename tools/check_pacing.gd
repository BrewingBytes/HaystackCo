extends SceneTree
## Headless pacing gate (CEO D12; G5). Exits 1 when the economy misses a target or fails the
## schema, 2 on a bad command line. Run before every economy change:
##   godot --headless -s res://tools/check_pacing.gd -- [--economy=res://sim/economy.json] [--seeds=500]

const Gate := preload("res://tools/pacing_gate.gd")
const USAGE := "usage: godot --headless -s res://tools/check_pacing.gd -- [--economy=<file>] [--seeds=<n>]"


func _init() -> void:
	var args := parse_args(OS.get_cmdline_user_args())
	if args.error != "":
		printerr("check_pacing: %s\n%s" % [args.error, USAGE])
		quit(2)
		return
	var path: String = args.economy
	var loaded := Economy.load_file(path)
	if loaded.economy == null:
		for error: String in loaded.errors:
			printerr("check_pacing: %s: %s" % [path, error])
		quit(1)
		return
	if not PileGen.native_available():
		if OS.get_environment("HAYSTACK_REQUIRE_NATIVE") == "1":
			printerr("check_pacing: native module not loaded (HAYSTACK_REQUIRE_NATIVE=1)")
			quit(1)
			return
		print("check_pacing: native module not loaded; the GDScript fallback is ~40× slower")
	var started := Time.get_ticks_msec()
	var result := Gate.run(loaded.economy, args.seeds)
	for line: String in result.lines:
		print("check_pacing: ", line)
	print("check_pacing: %s in %.1f s" % ["PASS" if result.ok else "FAIL", (Time.get_ticks_msec() - started) / 1000.0])
	quit(0 if result.ok else 1)


## { economy: String, seeds: int, error: String ("" when fine) }. Anything unrecognised is an
## error: a gate must not quietly check something other than what it was asked to.
static func parse_args(argv: PackedStringArray) -> Dictionary:
	var args := {economy = Economy.BUNDLED_PATH, seeds = 500, error = ""}
	for arg in argv:
		if arg.begins_with("--economy="):
			args.economy = arg.trim_prefix("--economy=")
			if args.economy == "":
				args.error = "--economy needs a file"
		elif arg.begins_with("--seeds="):
			var value := arg.trim_prefix("--seeds=")
			if not value.is_valid_int() or value.to_int() < 1:
				args.error = "--seeds needs a positive integer, got \"%s\"" % value
			else:
				args.seeds = value.to_int()
		else:
			args.error = "unknown argument \"%s\"" % arg
		if args.error != "":
			break
	return args
