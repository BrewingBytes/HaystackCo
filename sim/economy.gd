class_name Economy
extends RefCounted
## The economy catalog: prices, rates, pile sizes, needles and tool numbers, from a JSON file
## (bundled: res://sim/economy.json). Every value is checked against the schema below. Unknown
## keys, unknown behaviors, wrong types and out-of-range values are errors, so a bad catalog
## fails CI instead of the game (eng: unknown behavior → schema error at load).
## Item ids are append-only (Game Rules): saves store ids, never prices or rates.

const BUNDLED_PATH := "res://sim/economy.json"
const BEHAVIORS: Array[StringName] = [&"brush", &"magnet", &"detector", &"conveyor"]
const MAX_INT := 1_000_000_000
## Ids the game refers to by name (SimDefaults, the yard), with their behavior. Ids are
## append-only (Game Rules), so a catalog without one of these is an error.
const REQUIRED := {&"rake": &"brush", &"pitchfork": &"brush", &"blower": &"brush", &"magnet": &"magnet", &"detector": &"detector", &"conveyor": &"conveyor"}

## Key → [min, max]. Every key is required; nothing else is allowed.
const TOP := {
	"economyVersion": [1, MAX_INT], "minAppVersion": [1, MAX_INT], "unitsPerHay": [1, MAX_INT],
	"hayBoostMinutes": [1, 600], "pile": null, "reveal": null, "offline": null, "items": null,
}
const PILE := {"firstSeed": [0, 0x7FFFFFFF], "sizes": null, "needles": null}
const NEEDLES := {"first": [1, 64], "everyPiles": [1, 100], "max": [1, 64]}
const REVEAL := {"cell": [1, 64], "threshold": [0, 65535]}
## pileCompletions: piles offline time may finish and carry on past. Only 0 exists until
## offline pile-crossing is built (CEO re-review D6, TODOS.md).
const OFFLINE := {"capMinutes": [0, 7 * 24 * 60], "dailyCapMinutes": [0, 24 * 60], "pileCompletions": [0, 0]}
const ITEM_BASE := {"id": null, "behavior": null, "price": [0, MAX_INT]}
const ITEM := {
	&"brush": {"radius": [1, 64], "depth": [1, 65535], "tineSpacing": [0, 64], "ridgePct": [0, 100], "pushPct": [0, 100], "pushCells": [0, 256]},
	&"magnet": {"radius": [1, 256]},
	&"detector": {"range": [1, 4096]},
	&"conveyor": {"length": [2, 256], "width": [2, 256], "digWidth": [1, 256], "reach": [1, 4096], "rate": [1, MAX_INT]},
}


## One catalog entry. Exactly one of brush/machine is set for those behaviors; magnet and
## detector use `radius` (cells).
class Item:
	extends RefCounted
	var id: StringName
	var behavior: StringName
	var price: int
	var brush: BrushSpec
	var machine: MachineSpec
	var radius := 0  # magnet reach, detector half-strength range


var economy_version: int
var min_app_version: int
var units_per_hay: int
var hay_boost_minutes: int
var pile1_seed: int
var pile_sizes: Array[int] = []
var first_needles: int
var needles_every_piles: int
var max_needles: int
var reveal_cell: int
var reveal_threshold: int
var offline_cap_minutes: int
var daily_offline_cap_minutes: int
var offline_pile_completions: int
var items: Array[Item] = []  # catalog order
var _by_id := {}

static var _bundled: Economy


## The catalog shipped with the app. A bundled file that fails the schema is a build error.
static func bundled() -> Economy:
	if _bundled == null:
		var result := load_file(BUNDLED_PATH)
		assert(result.errors.is_empty(), "bundled economy: %s" % "; ".join(result.errors))
		_bundled = result.economy
	return _bundled


## { economy: Economy or null, errors: Array[String] }. Errors don't repeat the path.
static func load_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		var error := FileAccess.get_open_error()
		return {economy = null, errors = ["can't read (%s)" % error_string(error) if error != OK else "empty file"]}
	return parse(text)


## { economy: Economy or null, errors: Array[String] }.
static func parse(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		# get_error_line() counts from 0.
		return {economy = null, errors = ["line %d: %s" % [json.get_error_line() + 1, json.get_error_message()]]}
	return from_dict(json.data)


## { economy: Economy or null, errors: Array[String] }.
static func from_dict(data: Variant) -> Dictionary:
	var errors: Array[String] = []
	var economy := Economy.new()
	if _check_object(data, TOP, "", errors):
		economy._read(data, errors)
	return {economy = economy if errors.is_empty() else null, errors = errors}


func item(id: StringName) -> Item:
	return _by_id.get(id)


func brush(id: StringName) -> BrushSpec:
	return item(id).brush


func machine(id: StringName) -> MachineSpec:
	return item(id).machine


## Pile n's grid size; the last size repeats.
func pile_size(number: int) -> int:
	return pile_sizes[mini(number, pile_sizes.size()) - 1]


func needles_for(number: int) -> int:
	return mini(max_needles, first_needles + (number - 1) / needles_every_piles)


func _read(data: Dictionary, errors: Array[String]) -> void:
	economy_version = int(data.economyVersion)
	min_app_version = int(data.minAppVersion)
	units_per_hay = int(data.unitsPerHay)
	hay_boost_minutes = int(data.hayBoostMinutes)
	var pile: Variant = data.pile
	if _check_object(pile, PILE, "pile.", errors):
		pile1_seed = int(pile.firstSeed)
		var sizes: Variant = pile.sizes
		if not sizes is Array or sizes.is_empty():
			errors.append("pile.sizes: expected a non-empty array")
		else:
			for i in sizes.size():
				var size: Variant = sizes[i]
				if not _is_int(size) or int(size) < HeightGrid.TILE or int(size) > 2048 or int(size) % HeightGrid.TILE != 0:
					errors.append("pile.sizes[%d]: expected a multiple of %d in %d..2048" % [i, HeightGrid.TILE, HeightGrid.TILE])
				elif i > 0 and int(size) < pile_sizes[-1]:
					errors.append("pile.sizes[%d]: piles never shrink" % i)
				else:
					pile_sizes.append(int(size))
		if _check_object(pile.needles, NEEDLES, "pile.needles.", errors):
			first_needles = int(pile.needles.first)
			needles_every_piles = int(pile.needles.everyPiles)
			max_needles = int(pile.needles.max)
			if max_needles < first_needles:
				errors.append("pile.needles.max: below pile.needles.first")
	if _check_object(data.reveal, REVEAL, "reveal.", errors):
		reveal_cell = int(data.reveal.cell)
		reveal_threshold = int(data.reveal.threshold)
	if _check_object(data.offline, OFFLINE, "offline.", errors):
		offline_cap_minutes = int(data.offline.capMinutes)
		daily_offline_cap_minutes = int(data.offline.dailyCapMinutes)
		offline_pile_completions = int(data.offline.pileCompletions)
	if not data.items is Array or data.items.is_empty():
		errors.append("items: expected a non-empty array")
		return
	for i in data.items.size():
		_read_item(data.items[i], "items[%d]." % i, errors)
	var free_brush := items.any(func(it: Item) -> bool: return it.behavior == &"brush" and it.price == 0)
	if not free_brush:
		errors.append("items: no free brush to start with")
	if not items.any(func(it: Item) -> bool: return it.behavior == &"conveyor"):
		errors.append("items: no machine")
	for id: StringName in REQUIRED:
		if not _by_id.has(id):
			errors.append("items: \"%s\" missing (ids are append-only)" % id)
		elif _by_id[id].behavior != REQUIRED[id]:
			errors.append("items: \"%s\" must be a %s" % [id, REQUIRED[id]])


func _read_item(entry: Variant, at: String, errors: Array[String]) -> void:
	if not entry is Dictionary:
		errors.append("%s: expected an object" % at.trim_suffix("."))
		return
	var behavior := StringName(str(entry.get("behavior", "")))
	if not behavior in BEHAVIORS:
		errors.append("%sbehavior: unknown \"%s\"" % [at, behavior])
		return
	var schema: Dictionary = ITEM_BASE.merged(ITEM[behavior])
	if not _check_object(entry, schema, at, errors):
		return
	var id := StringName(str(entry.id))
	if not entry.id is String or not String(id).is_valid_ascii_identifier() or String(id) != String(id).to_lower():
		errors.append("%sid: expected a lower_case identifier" % at)
		return
	if _by_id.has(id):
		errors.append("%sid: duplicate \"%s\"" % [at, id])
		return
	var it := Item.new()
	it.id = id
	it.behavior = behavior
	it.price = int(entry.price)
	match behavior:
		&"brush":
			it.brush = BrushSpec.new(id, int(entry.radius), int(entry.depth), int(entry.tineSpacing), int(entry.ridgePct), int(entry.pushPct), int(entry.pushCells))
		&"magnet":
			it.radius = int(entry.radius)
		&"detector":
			it.radius = int(entry.range)
		&"conveyor":
			it.machine = MachineSpec.new(id, int(entry.length), int(entry.width), int(entry.digWidth), int(entry.reach), int(entry.rate))
	items.append(it)
	_by_id[id] = it


## Checks that `value` is an object with exactly `schema`'s keys and that every ranged key is an
## integer within its range. Nested objects (range null) are checked by the caller.
static func _check_object(value: Variant, schema: Dictionary, at: String, errors: Array[String]) -> bool:
	if not value is Dictionary:
		errors.append("%s: expected an object" % (at.trim_suffix(".") if at != "" else "economy"))
		return false
	var ok := true
	for key in value:
		if not schema.has(key):
			errors.append("%s%s: unknown key" % [at, key])
			ok = false
	for key in schema:
		if not value.has(key):
			errors.append("%s%s: missing" % [at, key])
			ok = false
			continue
		var range_: Variant = schema[key]
		if range_ == null:
			continue
		var v: Variant = value[key]
		if not _is_int(v) or int(v) < range_[0] or int(v) > range_[1]:
			errors.append("%s%s: expected an integer in %d..%d" % [at, key, range_[0], range_[1]])
			ok = false
	return ok


## JSON numbers arrive as floats: whole numbers only.
static func _is_int(v: Variant) -> bool:
	return (v is float or v is int) and float(v) == floorf(float(v)) and absf(float(v)) <= MAX_INT
