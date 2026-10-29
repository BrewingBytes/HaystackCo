extends GutTest
## check_pacing's command line: a pre-publish gate must not quietly check something other than
## what it was asked to check.
# Regression: ISSUE-004 — unknown flags and bad --seeds were ignored, so a typo passed the bundled file
# Regression: ISSUE-003 — a machine that never came was reported as "10:00 (≤ 10:00)"
# Found by /qa on 2026-10-28
# Report: .gstack/qa-reports/run-20261028T103608Z/qa-report-check-pacing-2026-10-28.md

const Cli := preload("res://tools/check_pacing.gd")
const Gate := preload("res://tools/pacing_gate.gd")


func test_defaults() -> void:
	var args := Cli.parse_args(PackedStringArray())
	assert_eq(args.error, "")
	assert_eq(args.economy, Economy.BUNDLED_PATH)
	assert_eq(args.seeds, 500)


func test_flags() -> void:
	var args := Cli.parse_args(PackedStringArray(["--economy=/tmp/e.json", "--seeds=20"]))
	assert_eq(args.error, "")
	assert_eq(args.economy, "/tmp/e.json")
	assert_eq(args.seeds, 20)


func test_unknown_flag_is_an_error() -> void:
	assert_string_contains(Cli.parse_args(PackedStringArray(["--econ=/tmp/e.json"])).error, "--econ=/tmp/e.json")


func test_seeds_must_be_a_positive_integer() -> void:
	for bad in ["--seeds=abc", "--seeds=0", "--seeds=-5", "--seeds=", "--seeds=12x"]:
		assert_ne(Cli.parse_args(PackedStringArray([bad])).error, "", bad)


func test_empty_economy_path_is_an_error() -> void:
	assert_ne(Cli.parse_args(PackedStringArray(["--economy="])).error, "")


func test_a_machine_that_never_comes_is_not_reported_at_the_limit() -> void:
	assert_eq(Gate._time(Gate.FIRST_MACHINE_MAX_MS), "10:00")
	assert_eq(Gate._time(Gate.FIRST_MACHINE_MAX_MS + 1), "not within 10:00")
	assert_eq(Gate._time(-1), "never")
