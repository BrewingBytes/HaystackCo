extends GutTest
## G6: the yard's save path. Hay raked in the same frame as a save (the pile-complete save runs
## inside the stroke that found the last needle) must reach the wallet before the save.
# Found by /review on 2026-10-28: a loaded save counts all collected hay as credited, so hay not
# yet in the wallet at save time was lost.

var _dir := ""


func before_each() -> void:
	_dir = "user://test_yard_save_%d" % Time.get_ticks_usec()


func after_each() -> void:
	for file in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file))
	DirAccess.remove_absolute(_dir)


func test_hay_raked_just_before_a_save_is_not_lost() -> void:
	var yard := Yard.new()
	add_child_autofree(yard)
	yard.set_process(false)  # no frame gets to credit the stroke before the save
	await yard.generate(128, false)
	var needle := yard.sim.needles[0]
	yard.sim.brush(SimDefaults.PITCHFORK, needle.x + 20, needle.y, 0, 256)
	var expected := yard.sim.collected / yard.economy.units_per_hay
	assert_gt(expected, 0)
	assert_eq(yard.save_to(SaveStore.new(_dir)), OK)
	var loaded: GameState = SaveStore.new(_dir).load_state(yard.economy).state
	assert_eq(loaded.wallet.hay, expected)
