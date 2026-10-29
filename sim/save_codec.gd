class_name SaveCodec
extends RefCounted
## GameState ↔ bytes (eng D2; G6). The envelope never changes:
##   "HSTK" · u16 version · u32 body length · body · SHA-256 of everything before it
## so a damaged file is always caught by the hash (→ backup) before its version is trusted, and
## only an intact file from a newer app is refused (→ Update required).
##
## Body (version 1): u32 JSON length · JSON · then per changed tile (in the JSON's `touched`
## order): u8 form · u32 length · DEFLATE bytes, where form 0 is the tile's heights and form 1
## is the hay removed from it (generated − now). The grid isn't stored whole: the pile is
## regenerated from its seed, checked against the digest it had when it was made, and only the
## tiles play changed are laid back on top, each in whichever form packs smaller (a raked tile
## as removed hay, a cleared one as heights). A 1024² grid is 2 MB raw and hay heights barely
## compress, so this is what keeps a half-cleared pile under 150 KB.

const MAGIC := "HSTK"
const VERSION := 1
const HEADER := 10  # magic + version + body length
const HASH := 32
const TILE_BYTES := HeightGrid.TILE * HeightGrid.TILE * 2
enum TileForm { HEIGHTS, REMOVED }

enum Refusal { NONE, TOO_SHORT, BAD_MAGIC, BAD_HASH, NEWER_VERSION, MALFORMED }


## Also remembers each tile's packed bytes on the sim, so the next save only packs tiles that
## changed since (most of a save's cost is packing).
static func encode(state: GameState, now_unix: int) -> PackedByteArray:
	var sim := state.sim
	var touched := sim.grid.touched_tiles()
	# Packing is most of a save's cost: reuse tiles unchanged since the last save or load.
	var stale := PackedInt32Array()
	for tile in touched:
		if sim.grid.is_unsaved(tile) or not sim.packed_tiles.has(tile):
			stale.append(tile)
	var removed := HeightGrid.tile_delta(sim.base_bytes, sim.grid.bytes, sim.grid.size, stale, false)
	for i in stale.size():
		var as_heights := sim.grid.tile_bytes(stale[i]).compress(FileAccess.COMPRESSION_DEFLATE)
		var as_removed := removed.slice(i * TILE_BYTES, (i + 1) * TILE_BYTES).compress(FileAccess.COMPRESSION_DEFLATE)
		var form := TileForm.HEIGHTS if as_heights.size() <= as_removed.size() else TileForm.REMOVED
		var packed := as_heights if form == TileForm.HEIGHTS else as_removed
		var entry := PackedByteArray([form, 0, 0, 0, 0])
		entry.encode_u32(1, packed.size())
		entry.append_array(packed)
		sim.packed_tiles[stale[i]] = entry
	sim.grid.clear_unsaved()
	var tiles := PackedByteArray()
	for tile in touched:
		tiles.append_array(sim.packed_tiles[tile])
	var meta := {
		installSeed = state.install_seed,
		economyVersion = state.economy.economy_version,
		savedAt = now_unix,
		pile = [sim.spec.number, sim.spec.size, sim.spec.peak, sim.spec.seed, sim.spec.needles],
		baseDigest = sim.base_digest,
		collected = sim.collected,
		needles = sim.needles.map(func(n: Needle) -> Array: return [n.x, n.y, n.z, n.found, n.source, n.tutorial]),
		placed = state.park.placed.map(func(m: MachinePark.Placed) -> Array:
			return [String(m.spec.id), m.pose.x, m.pose.y, m.pose.yaw, m.dig.front, m.dig._carry]),
		shelf = state.park.shelf.map(func(s: MachineSpec) -> String: return String(s.id)),
		hay = [state.wallet.hay, state.wallet._carry],
		owned = state.inventory.owned,
		magnetTutorialDone = state.inventory.magnet_tutorial_done,
		flags = state.flags,
		clock = [state.clock.last_seen_unix, state.clock.day, state.clock.offline_ms_today, state.clock.interstitials_today],
		ads = [state.ads.last_pile, state.boost_ms_left],
		touched = Array(touched),
	}
	var json := JSON.stringify(meta).to_utf8_buffer()
	var body := PackedByteArray()
	body.resize(4)
	body.encode_u32(0, json.size())
	body.append_array(json)
	body.append_array(tiles)
	var out := MAGIC.to_ascii_buffer()
	var header := PackedByteArray()
	header.resize(6)
	header.encode_u16(0, VERSION)
	header.encode_u32(2, body.size())
	out.append_array(header)
	out.append_array(body)
	out.append_array(_sha256(out))
	return out


## True when `bytes` is a whole, undamaged save file (any version): cheap, no decoding. The
## store only lets an intact primary become the backup.
static func intact(bytes: PackedByteArray) -> bool:
	if bytes.size() < HEADER + HASH or bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return false
	var end := HEADER + bytes.decode_u32(6)
	return bytes.size() == end + HASH and _sha256(bytes.slice(0, end)) == bytes.slice(end)


## { refusal: Refusal, state: GameState (when NONE), detail: String }. Regenerates the pile,
## so it's slow for big piles without the native module: run it off the main thread.
static func decode(bytes: PackedByteArray, economy: Economy) -> Dictionary:
	if bytes.size() < HEADER + HASH:
		return _refuse(Refusal.TOO_SHORT, "%d bytes" % bytes.size())
	if bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return _refuse(Refusal.BAD_MAGIC, "")
	var body_size := bytes.decode_u32(6)
	if bytes.size() != HEADER + body_size + HASH:
		return _refuse(Refusal.TOO_SHORT if bytes.size() < HEADER + body_size + HASH else Refusal.MALFORMED, "length")
	var end := HEADER + body_size
	if _sha256(bytes.slice(0, end)) != bytes.slice(end):
		return _refuse(Refusal.BAD_HASH, "")
	var version := bytes.decode_u16(4)
	if version > VERSION:
		return _refuse(Refusal.NEWER_VERSION, "save version %d, app reads %d" % [version, VERSION])
	return _decode_body(bytes.slice(HEADER, end), economy)


static func _decode_body(body: PackedByteArray, economy: Economy) -> Dictionary:
	var reader := _Reader.new(body)
	var json := JSON.new()  # an instance: parse_string() logs an engine error on bad text
	if json.parse(reader.take(reader.u32()).get_string_from_utf8()) != OK or reader.failed or not json.data is Dictionary:
		return _refuse(Refusal.MALFORMED, "body layout")
	var m := _Meta.new(json.data)
	var pile := m.ints("pile", 5)
	if m.failed:
		return _refuse(Refusal.MALFORMED, m.why)
	var spec := PileSpec.new(pile[0], pile[1], pile[2], pile[3], pile[4])
	if spec.size <= 0 or spec.size % HeightGrid.TILE != 0 or spec.size > 4096:
		return _refuse(Refusal.MALFORMED, "pile size %d" % spec.size)
	var sim := PileSim.new()
	sim.spec = spec
	sim.grid = HeightGrid.new(spec.size)
	PileGen.generate(sim.grid, spec.seed, spec.peak)
	sim.base_digest = sim.grid.digest()
	sim.base_bytes = sim.grid.bytes.duplicate()
	if sim.base_digest != m.text("baseDigest"):
		return _refuse(Refusal.MALFORMED, "the pile generator no longer makes this pile")
	sim.initial_mass = sim.grid.mass()
	sim.grid.clear_touched()
	sim.reveal_cell = economy.reveal_cell
	sim.reveal_threshold = economy.reveal_threshold
	var touched := m.int_list("touched")
	if m.failed:
		return _refuse(Refusal.MALFORMED, m.why)
	var tile_count := sim.grid.tiles_per_side * sim.grid.tiles_per_side
	var tiles := {}
	var removed_tiles := PackedInt32Array()
	var removed := PackedByteArray()
	for tile in touched:
		var entry_at := reader.at
		var form := reader.take(1)
		var packed := reader.take(reader.u32())
		if reader.failed or packed.is_empty():
			return _refuse(Refusal.MALFORMED, "tile %d cut short" % tile)
		var unpacked := packed.decompress(TILE_BYTES, FileAccess.COMPRESSION_DEFLATE)
		if tile < 0 or tile >= tile_count or tiles.has(tile) or unpacked.size() != TILE_BYTES or form[0] > TileForm.REMOVED:
			return _refuse(Refusal.MALFORMED, "tile %d" % tile)
		if form[0] == TileForm.REMOVED:
			removed_tiles.append(tile)
			removed.append_array(unpacked)
		tiles[tile] = unpacked
		sim.packed_tiles[tile] = body.slice(entry_at, reader.at)
	if reader.at != body.size():
		return _refuse(Refusal.MALFORMED, "trailing bytes")
	var restored := HeightGrid.tile_delta(sim.base_bytes, removed, sim.grid.size, removed_tiles, true)
	for i in removed_tiles.size():
		tiles[removed_tiles[i]] = restored.slice(i * TILE_BYTES, (i + 1) * TILE_BYTES)
	if not tiles.is_empty():
		sim.grid.set_tiles(tiles)
	sim.grid.clear_unsaved()  # the packed tiles above are the current ones
	sim.collected = m.integer("collected")
	for entry in m.list("needles"):
		var n := _Meta.row(entry, 6)
		if n.is_empty():
			return _refuse(Refusal.MALFORMED, "needle")
		var needle := Needle.new(n[0], n[1], n[2])
		needle.found = n[3] != 0
		needle.source = clampi(n[4], 0, Needle.Source.size() - 1) as Needle.Source
		needle.tutorial = n[5] != 0
		sim.needles.append(needle)
	if m.failed or not sim.mass_balanced():
		return _refuse(Refusal.MALFORMED, m.why if m.failed else "pile + collected hay doesn't add up")

	var state := GameState.new()
	state.economy = economy
	state.sim = sim
	state.install_seed = m.integer("installSeed")
	state.saved_at_unix = m.integer("savedAt")
	state.credited = sim.collected  # the yard credits pending hay before every save
	# Saves from before G7 have no clock: time away counts from when they were saved.
	var clock: Array[int] = [state.saved_at_unix, 0, 0, 0]
	if m.data.has("clock"):
		clock = _Meta.row(m.data.clock, 4)
	if clock.is_empty():
		return _refuse(Refusal.MALFORMED, "clock")
	state.clock.last_seen_unix = clock[0]
	state.clock.day = clock[1]
	state.clock.offline_ms_today = clock[2]
	state.clock.interstitials_today = clock[3]
	# Saves from before G8 have no ad state: no interstitial yet, no boost running.
	var ads: Array[int] = [0, 0]
	if m.data.has("ads"):
		ads = _Meta.row(m.data.ads, 2)
	if ads.is_empty():
		return _refuse(Refusal.MALFORMED, "ads")
	state.ads.first_session = false  # a loaded save is a later cold start
	state.ads.last_pile = ads[0]
	state.boost_ms_left = clampi(ads[1], 0, economy.hay_boost_minutes * 60_000)
	for entry in m.list("placed"):
		var row: Variant = entry
		if not row is Array or row.size() != 6 or not row[0] is String:
			return _refuse(Refusal.MALFORMED, "placed machine")
		var it := economy.item(StringName(row[0]))
		var p := _Meta.row(row.slice(1), 5)
		if it == null or it.machine == null or p.is_empty():
			return _refuse(Refusal.MALFORMED, "placed machine %s" % row[0])
		var machine := state.park.place(sim, it.machine, Pose.new(p[0], p[1], p[2]))
		machine.dig.front = p[3]
		machine.dig._carry = p[4]
	for id in m.list("shelf"):
		var it := economy.item(StringName(str(id)))
		if it == null or it.machine == null:
			return _refuse(Refusal.MALFORMED, "shelved machine %s" % id)
		state.park.shelf.append(it.machine)
	var hay := m.ints("hay", 2)
	state.wallet = Wallet.new(economy.units_per_hay)
	state.inventory = Inventory.new()
	var owned := m.dict("owned")
	if m.failed:
		return _refuse(Refusal.MALFORMED, m.why)
	state.wallet.hay = hay[0]
	state.wallet._carry = hay[1]
	state.tick(0)  # a running 2× hay reward doubles again
	for id: String in owned:
		if not _Meta.is_whole(owned[id]):
			return _refuse(Refusal.MALFORMED, "owned %s" % id)
		state.inventory.owned[StringName(id)] = int(owned[id])
	state.inventory.magnet_tutorial_done = m.boolean("magnetTutorialDone")
	var flags := m.dict("flags")
	for flag in GameState.FLAGS:
		state.flags[flag] = flags.get(String(flag), false) == true
	if m.failed:
		return _refuse(Refusal.MALFORMED, m.why)
	return {refusal = Refusal.NONE, state = state, detail = ""}


static func _refuse(refusal: Refusal, detail: String) -> Dictionary:
	return {refusal = refusal, state = null, detail = detail}


static func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()


## Reads length-prefixed parts of the body; past the end, `failed` is set instead of crashing.
class _Reader:
	extends RefCounted
	var data: PackedByteArray
	var at := 0
	var failed := false

	func _init(p_data: PackedByteArray) -> void:
		data = p_data

	func u32() -> int:
		if at + 4 > data.size():
			failed = true
			return 0
		at += 4
		return data.decode_u32(at - 4)

	func take(count: int) -> PackedByteArray:
		if failed or count < 0 or at + count > data.size():
			failed = true
			return PackedByteArray()
		at += count
		return data.slice(at - count, at)


## Typed reads from the JSON part. JSON numbers arrive as floats; a wrong type or a missing key
## sets `failed` (with `why`) and returns a harmless default, so decode never crashes on a save.
class _Meta:
	extends RefCounted
	var data: Dictionary
	var failed := false
	var why := ""

	func _init(p_data: Dictionary) -> void:
		data = p_data

	static func is_whole(v: Variant) -> bool:
		return (v is float or v is int) and float(v) == floorf(float(v))

	## An array of `count` whole numbers (booleans count as 0/1), or [] if it isn't one.
	static func row(v: Variant, count: int) -> Array[int]:
		var out: Array[int] = []
		if not v is Array or v.size() != count:
			return out
		for x: Variant in v:
			if x is bool:
				out.append(1 if x else 0)
			elif is_whole(x):
				out.append(int(x))
			else:
				return [] as Array[int]
		return out

	func integer(key: String) -> int:
		var v: Variant = data.get(key)
		if not is_whole(v):
			_fail(key)
			return 0
		return int(v)

	func boolean(key: String) -> bool:
		var v: Variant = data.get(key)
		if not v is bool:
			_fail(key)
			return false
		return v

	func text(key: String) -> String:
		var v: Variant = data.get(key)
		if not v is String:
			_fail(key)
			return ""
		return v

	func list(key: String) -> Array:
		var v: Variant = data.get(key)
		if not v is Array:
			_fail(key)
			return []
		return v

	func dict(key: String) -> Dictionary:
		var v: Variant = data.get(key)
		if not v is Dictionary:
			_fail(key)
			return {}
		return v

	func ints(key: String, count: int) -> Array[int]:
		var out := row(data.get(key), count)
		if out.is_empty():
			_fail(key)
			out.resize(count)
		return out

	func int_list(key: String) -> Array[int]:
		var v := list(key)
		var out := row(v, v.size())
		if out.size() != v.size():
			_fail(key)
		return out

	func _fail(key: String) -> void:
		if not failed:
			failed = true
			why = key
