extends GutTest
## G6: saves (eng D2, D11; design D8). Round trip incl. placements and flags, size, the backup
## and quarantine paths, newer-save refusal, and that decode never crashes on a bad body.

const SIZE := 256

var _dir := ""


func before_each() -> void:
	_dir = "user://test_saves_%d" % Time.get_ticks_usec()


func after_each() -> void:
	_remove_tree(_dir)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


## A state with a bit of everything: raked hay, a found needle, a tutorial needle, a placed
## conveyor part-way through its dig, one on the shelf, hay and owned tools, and a flag set.
func _played_state(size := SIZE) -> GameState:
	var economy := Economy.bundled()
	var state := GameState.new_game(economy, 4242, PileSpec.new(2, size, SimDefaults.peak_for(size), 77, 3))
	var sim := state.sim
	for i in 30:
		sim.brush(SimDefaults.RAKE, size / 2 + (i % 10) * 4, size / 2 + i, 256, 0)
	var needle := sim.needles[0]
	sim.magnet(needle.x, needle.y, 10)
	sim.magnet(5, 5, 10, true)
	state.park.place(sim, economy.machine(&"conveyor"), Placement.nearest_edge_spot(sim.grid, [], economy.machine(&"conveyor"), Vector2i(size / 2, size)))
	sim.advance_machines(20_000)
	state.park.buy(economy.machine(&"conveyor"))
	state.wallet.credit(123_456_789)
	state.inventory.owned[&"pitchfork"] = 1
	state.inventory.owned[&"conveyor"] = 2
	state.inventory.magnet_tutorial_done = true
	state.flags[&"cueShopSeen"] = true
	return state


func _decode(bytes: PackedByteArray) -> Dictionary:
	return SaveCodec.decode(bytes, Economy.bundled())


## Same layout, new version number, hash recomputed: an intact file from a newer app.
func _with_version(bytes: PackedByteArray, version: int) -> PackedByteArray:
	var out := bytes.slice(0, bytes.size() - SaveCodec.HASH)
	out.encode_u16(4, version)
	return _rehash(out)


func _rehash(without_hash: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(without_hash)
	var out := without_hash.duplicate()
	out.append_array(ctx.finish())
	return out


func _write(name: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	var file := FileAccess.open(_dir.path_join(name), FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


# --- Codec ---------------------------------------------------------------------------------

func test_round_trip_keeps_everything_and_plays_on_identically() -> void:
	var state := _played_state()
	var result := _decode(SaveCodec.encode(state, 1_800_000_000))
	assert_eq(result.refusal, SaveCodec.Refusal.NONE, result.detail)
	var back: GameState = result.state
	assert_eq(back.sim.grid.digest(), state.sim.grid.digest())
	assert_eq(back.sim.collected, state.sim.collected)
	assert_true(back.sim.mass_balanced())
	assert_eq(back.install_seed, 4242)
	assert_eq(back.saved_at_unix, 1_800_000_000)
	assert_eq(back.sim.needles.size(), state.sim.needles.size())
	for i in state.sim.needles.size():
		var a := state.sim.needles[i]
		var b := back.sim.needles[i]
		assert_eq([b.x, b.y, b.z, b.found, b.source, b.tutorial], [a.x, a.y, a.z, a.found, a.source, a.tutorial])
	assert_eq(back.park.placed.size(), 1)
	var m := back.park.placed[0]
	var original := state.park.placed[0]
	assert_eq([m.pose.x, m.pose.y, m.pose.yaw, m.dig.front], [original.pose.x, original.pose.y, original.pose.yaw, original.dig.front])
	assert_gt(m.dig.front, 0, "the conveyor had dug in before the save")
	assert_eq(back.park.shelf_count(&"conveyor"), 1)
	assert_eq(back.wallet.hay, state.wallet.hay)
	assert_eq(back.wallet._carry, state.wallet._carry)
	assert_eq(back.inventory.owned, state.inventory.owned)
	assert_true(back.inventory.magnet_tutorial_done)
	assert_eq(back.flags, {&"cueShopSeen": true, &"cueGhostSeen": false, &"hintRakeDone": false})
	# Determinism: both copies keep digging and raking to the same bytes.
	for s: GameState in [state, back]:
		s.sim.advance_machines(30_000)
		s.sim.brush(SimDefaults.PITCHFORK, SIZE / 2, SIZE / 2, 0, 256)
	assert_eq(back.sim.grid.digest(), state.sim.grid.digest())
	assert_eq(back.sim.collected, state.sim.collected)


func test_fresh_pile_saves_no_tiles() -> void:
	var state := GameState.new_game(Economy.bundled(), 1, PileSpec.new(1, SIZE, 8000, 1, 1))
	assert_eq(state.sim.grid.touched_tiles().size(), 0)
	var bytes := SaveCodec.encode(state, 0)
	assert_lt(bytes.size(), 2048)
	assert_eq(_decode(bytes).state.sim.grid.digest(), state.sim.grid.digest())


func test_half_cleared_big_pile_is_at_most_150_kb() -> void:
	var size := 1024
	var state := GameState.new_game(Economy.bundled(), 9, PileSpec.new(5, size, SimDefaults.peak_for(size), 31, 4))
	var sim := state.sim
	var cleared := {}
	var empty := PackedByteArray()
	empty.resize(HeightGrid.TILE * HeightGrid.TILE * 2)
	var tiles := sim.grid.tiles_per_side
	for tile in tiles * tiles / 2:
		cleared[tile] = empty
	var before := sim.grid.mass()
	sim.grid.set_tiles(cleared)
	sim.collected += before - sim.grid.mass()
	# Rake furrows across the other half: changed but not empty tiles.
	for row in 40:
		var stamps := PackedInt32Array()
		for x in range(100, size - 100, 6):
			stamps.append_array([x, size / 2 + 20 + row * 10])
		sim.stroke(SimDefaults.RAKE, stamps, 256, 0)
	var bytes := SaveCodec.encode(state, 0)
	gut.p("half-cleared 1024 pile: %d bytes, %d tiles stored" % [bytes.size(), sim.grid.touched_tiles().size()])
	assert_lte(bytes.size(), 150 * 1024)
	var back: GameState = _decode(bytes).state
	assert_eq(back.sim.grid.digest(), sim.grid.digest())


func test_newer_version_is_refused() -> void:
	var bytes := _with_version(SaveCodec.encode(_played_state(), 0), SaveCodec.VERSION + 1)
	assert_true(SaveCodec.intact(bytes))
	assert_eq(_decode(bytes).refusal, SaveCodec.Refusal.NEWER_VERSION)


func test_damage_is_caught_before_the_version_is_trusted() -> void:
	var bytes := SaveCodec.encode(_played_state(), 0)
	var flipped := bytes.duplicate()
	flipped[5] ^= 0x01  # the version's high byte: reads as a far newer version, hash now wrong
	assert_eq(_decode(flipped).refusal, SaveCodec.Refusal.BAD_HASH)
	assert_eq(_decode(bytes.slice(0, bytes.size() / 2)).refusal, SaveCodec.Refusal.TOO_SHORT)
	assert_eq(_decode(PackedByteArray()).refusal, SaveCodec.Refusal.TOO_SHORT)
	var other := "JUNK".to_ascii_buffer()
	other.append_array(bytes.slice(4))
	assert_eq(_decode(other).refusal, SaveCodec.Refusal.BAD_MAGIC)


func test_a_changed_pile_generator_is_refused_not_misread() -> void:
	var state := _played_state()
	state.sim.base_digest = "0".repeat(64)  # what an old save looks like after the generator changed
	var result := _decode(SaveCodec.encode(state, 0))
	assert_eq(result.refusal, SaveCodec.Refusal.MALFORMED)
	assert_string_contains(result.detail, "generator")


## The hash stops damage, so a bad body behind a good hash means a bug wrote it: the JSON is
## where that would show. (Flipping bytes inside DEFLATE data makes the engine log errors.)
func test_decode_never_crashes_on_a_rehashed_bad_body() -> void:
	var good := SaveCodec.encode(_played_state(), 0)
	var rng := SeedRng.new(99)
	var body_end := good.size() - SaveCodec.HASH
	var json_start := SaveCodec.HEADER + 4
	var json_end := json_start + good.decode_u32(SaveCodec.HEADER)
	for i in 60:
		var bad := good.slice(0, body_end)
		for flip in 1 + i % 4:
			var at := rng.range_int(json_start, json_end - 1)
			bad[at] = rng.range_int(32, 126)
		var result := _decode(_rehash(bad))
		assert_true(result.refusal in [SaveCodec.Refusal.NONE, SaveCodec.Refusal.MALFORMED], "mutation %d: %s" % [i, result.detail])
		if result.refusal == SaveCodec.Refusal.NONE:
			assert_true(result.state.sim.mass_balanced())


# Regression: ISSUE-001 — every save recompressed every changed tile (37–79 ms on the main thread)
# Found by /qa on 2026-10-28
# Report: .gstack/qa-reports/run-20261028T115139Z/qa-report-saves-2026-10-28.md
# Saves now reuse the packed tiles that haven't changed since the last save or load; these
# check that reuse never writes a stale tile.
func test_tiles_changed_after_a_save_are_saved_again() -> void:
	var state := _played_state()
	SaveCodec.encode(state, 0)
	state.sim.brush(SimDefaults.PITCHFORK, 30, 30, 0, 256)  # a tile the first save had
	state.sim.brush(SimDefaults.PITCHFORK, SIZE - 30, 30, 0, 256)  # a tile it didn't
	var back: GameState = _decode(SaveCodec.encode(state, 0)).state
	assert_eq(back.sim.grid.digest(), state.sim.grid.digest())


func test_a_loaded_save_saves_its_later_changes() -> void:
	var loaded: GameState = _decode(SaveCodec.encode(_played_state(), 0)).state
	loaded.sim.advance_machines(30_000)
	loaded.sim.brush(SimDefaults.RAKE, SIZE / 2, SIZE / 2 + 5, 256, 0)
	var again: GameState = _decode(SaveCodec.encode(loaded, 0)).state
	assert_eq(again.sim.grid.digest(), loaded.sim.grid.digest())
	assert_eq(again.sim.collected, loaded.sim.collected)


func test_cut_tile_data_is_malformed() -> void:
	var good := SaveCodec.encode(_played_state(), 0)
	var body := good.slice(0, good.size() - SaveCodec.HASH - 40)
	body.encode_u32(6, body.size() - SaveCodec.HEADER)
	assert_eq(_decode(_rehash(body)).refusal, SaveCodec.Refusal.MALFORMED)


# --- Store ---------------------------------------------------------------------------------

func test_store_round_trip_and_backup_is_the_previous_good_file() -> void:
	var store := SaveStore.new(_dir)
	var state := _played_state()
	assert_eq(store.save(state, 100), OK)
	var first := FileAccess.get_file_as_bytes(_dir.path_join(SaveStore.PRIMARY))
	assert_false(FileAccess.file_exists(_dir.path_join(SaveStore.BACKUP)), "nothing to back up on the first save")
	state.wallet.hay += 5
	assert_eq(store.save(state, 200), OK)
	assert_eq(FileAccess.get_file_as_bytes(_dir.path_join(SaveStore.BACKUP)), first)
	var loaded := SaveStore.new(_dir).load_state(Economy.bundled())
	assert_eq(loaded.notice, SaveStore.Notice.NONE)
	assert_eq(loaded.state.wallet.hay, state.wallet.hay)
	assert_eq(loaded.state.saved_at_unix, 200)
	assert_eq(Array(DirAccess.get_files_at(_dir)).filter(func(f: String) -> bool: return f.ends_with(".tmp")), [])


func test_bad_hash_loads_the_backup_and_quarantines_the_primary() -> void:
	var store := SaveStore.new(_dir)
	var state := _played_state()
	store.save(state, 100)
	var good_hay := state.wallet.hay
	state.wallet.hay += 1000
	store.save(state, 200)
	var primary := FileAccess.get_file_as_bytes(_dir.path_join(SaveStore.PRIMARY))
	primary[primary.size() / 2] ^= 0xFF
	_write(SaveStore.PRIMARY, primary)
	var loaded := SaveStore.new(_dir).load_state(Economy.bundled())
	assert_eq(loaded.notice, SaveStore.Notice.RESTORED)
	assert_eq(loaded.state.wallet.hay, good_hay)
	assert_false(FileAccess.file_exists(_dir.path_join(SaveStore.PRIMARY)))
	assert_eq(DirAccess.get_files_at(_dir.path_join(SaveStore.QUARANTINE)).size(), 1)


func test_truncated_primary_loads_the_backup() -> void:
	# Power loss without fsync can leave a zero-length or short file.
	var store := SaveStore.new(_dir)
	store.save(_played_state(), 100)
	store.save(_played_state(), 200)
	_write(SaveStore.PRIMARY, PackedByteArray())
	var loaded := SaveStore.new(_dir).load_state(Economy.bundled())
	assert_eq(loaded.notice, SaveStore.Notice.RESTORED)
	assert_not_null(loaded.state)


func test_both_bad_starts_fresh_and_says_so() -> void:
	_write(SaveStore.PRIMARY, "garbage".to_ascii_buffer())
	_write(SaveStore.BACKUP, PackedByteArray([1, 2, 3]))
	var loaded := SaveStore.new(_dir).load_state(Economy.bundled())
	assert_null(loaded.state)
	assert_eq(loaded.notice, SaveStore.Notice.FRESH)
	assert_eq(DirAccess.get_files_at(_dir.path_join(SaveStore.QUARANTINE)).size(), 2)


func test_no_save_is_a_quiet_first_launch() -> void:
	var loaded := SaveStore.new(_dir).load_state(Economy.bundled())
	assert_null(loaded.state)
	assert_eq(loaded.notice, SaveStore.Notice.NONE)


func test_newer_save_is_never_overwritten() -> void:
	var newer := _with_version(SaveCodec.encode(_played_state(), 0), SaveCodec.VERSION + 1)
	_write(SaveStore.PRIMARY, newer)
	var store := SaveStore.new(_dir)
	var loaded := store.load_state(Economy.bundled())
	assert_eq(loaded.notice, SaveStore.Notice.UPDATE_REQUIRED)
	assert_null(loaded.state)
	assert_eq(store.save(_played_state(), 1), ERR_UNAVAILABLE)
	assert_eq(FileAccess.get_file_as_bytes(_dir.path_join(SaveStore.PRIMARY)), newer)


func test_a_damaged_primary_never_becomes_the_backup() -> void:
	var store := SaveStore.new(_dir)
	store.save(_played_state(), 100)
	store.save(_played_state(), 200)
	var backup := FileAccess.get_file_as_bytes(_dir.path_join(SaveStore.BACKUP))
	_write(SaveStore.PRIMARY, PackedByteArray([0, 0, 0]))
	assert_eq(store.save(_played_state(), 300), OK)
	assert_eq(FileAccess.get_file_as_bytes(_dir.path_join(SaveStore.BACKUP)), backup)


func test_quarantine_keeps_only_the_newest_few() -> void:
	var into := _dir.path_join(SaveStore.QUARANTINE)
	DirAccess.make_dir_recursive_absolute(into)
	for t in 6:
		var f := FileAccess.open(into.path_join("game.sav.%d" % (1000 + t)), FileAccess.WRITE)
		f.close()
	_write(SaveStore.PRIMARY, PackedByteArray([9]))
	SaveStore.new(_dir).load_state(Economy.bundled())
	var kept := Array(DirAccess.get_files_at(into))
	assert_eq(kept.size(), SaveStore.QUARANTINE_KEEP)
	assert_false("game.sav.1000" in kept, "the oldest goes first")
