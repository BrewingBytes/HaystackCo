extends GutTest
## G5: the economy catalog's schema, the wallet (hay is currency once it leaves the pile, design
## D16), buying, and the magnet tutorial needle.


func _bundled_dict() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Economy.BUNDLED_PATH))


func _errors_for(data: Dictionary) -> Array[String]:
	var result := Economy.from_dict(data)
	assert_null(result.economy, "a catalog with errors is rejected")
	return result.errors


func _assert_rejected(data: Dictionary, expected: String) -> void:
	var errors := _errors_for(data)
	assert_true(errors.any(func(e: String) -> bool: return expected in e), "expected \"%s\" in %s" % [expected, errors])


# --- Schema --------------------------------------------------------------------------------

func test_bundled_catalog_is_valid() -> void:
	var result := Economy.load_file(Economy.BUNDLED_PATH)
	assert_eq(result.errors, [] as Array[String])
	var economy: Economy = result.economy
	assert_eq(economy.item(&"rake").price, 0, "the rake is free")
	assert_not_null(economy.machine(&"conveyor"))
	assert_eq(economy.needles_for(1), 1, "pile 1 holds one needle")


func test_sim_defaults_read_the_bundled_catalog() -> void:
	var economy := Economy.bundled()
	assert_eq(SimDefaults.RAKE, economy.brush(&"rake"))
	assert_eq(SimDefaults.CONVEYOR, economy.machine(&"conveyor"))
	assert_eq(SimDefaults.PILE1_SEED, economy.pile1_seed)
	assert_eq(SimDefaults.MAGNET_RADIUS, economy.item(&"magnet").radius)


func test_unknown_behavior_is_a_schema_error() -> void:
	var data := _bundled_dict()
	data.items.append({"id": "sifter", "behavior": "sifter", "price": 10})
	_assert_rejected(data, "items[6].behavior: unknown \"sifter\"")


func test_unknown_and_missing_keys_are_errors() -> void:
	var data := _bundled_dict()
	data["sellBoostMinutes"] = 10  # renamed to hayBoostMinutes (design D16)
	_assert_rejected(data, "sellBoostMinutes: unknown key")
	data = _bundled_dict()
	data.items[5].erase("rate")
	_assert_rejected(data, "items[5].rate: missing")
	data = _bundled_dict()
	data.reveal["radius"] = 3
	_assert_rejected(data, "reveal.radius: unknown key")


func test_numbers_must_be_whole_and_in_range() -> void:
	var data := _bundled_dict()
	data.items[1].price = 2.5
	_assert_rejected(data, "items[1].price: expected an integer")
	data = _bundled_dict()
	data.items[1].price = -1
	_assert_rejected(data, "items[1].price: expected an integer")
	data = _bundled_dict()
	data.unitsPerHay = 0
	_assert_rejected(data, "unitsPerHay: expected an integer")
	data = _bundled_dict()
	data.items[0].radius = "12"
	_assert_rejected(data, "items[0].radius: expected an integer")


func test_catalog_rules() -> void:
	var data := _bundled_dict()
	data.items[1].id = "rake"
	_assert_rejected(data, "duplicate \"rake\"")
	data = _bundled_dict()
	data.items[0].price = 100
	_assert_rejected(data, "no free brush")
	data = _bundled_dict()
	data.items.remove_at(5)
	_assert_rejected(data, "no machine")
	data = _bundled_dict()
	data.pile.sizes = [640, 512]
	_assert_rejected(data, "piles never shrink")
	data = _bundled_dict()
	data.pile.sizes = [500]
	_assert_rejected(data, "pile.sizes[0]")
	data = _bundled_dict()
	data.items.remove_at(2)  # the magnet: the yard and SimDefaults use it by id
	_assert_rejected(data, "\"magnet\" missing")
	data = _bundled_dict()
	data.items[2].id = "magnet2"
	data.items[4].id = "magnet"  # the detector entry under the magnet's id
	_assert_rejected(data, "\"magnet\" must be a magnet")


# Regression: ISSUE-001 — Godot's JSON error line is 0-based; the message pointed one line too high
# Regression: ISSUE-002 — a missing file printed its path twice (the CLI adds it)
# Found by /qa on 2026-10-28
# Report: .gstack/qa-reports/run-20261028T103608Z/qa-report-check-pacing-2026-10-28.md
func test_broken_json_reports_the_line() -> void:
	var result := Economy.parse("{\n  \"economyVersion\": 1,\n  oops\n}")
	assert_null(result.economy)
	assert_string_starts_with(result.errors[0], "line 3:")


func test_missing_file_error_leaves_the_path_to_the_caller() -> void:
	var errors: Array = Economy.load_file("res://no/such/economy.json").errors
	assert_eq(errors.size(), 1)
	assert_false("no/such" in errors[0], errors[0])


# --- Wallet and buying ---------------------------------------------------------------------

func test_wallet_keeps_the_remainder_between_strokes() -> void:
	var wallet := Wallet.new(1000)
	for i in 10:
		wallet.credit(350)
	assert_eq(wallet.hay, 3, "3500 units → 3 hay, 500 carried")
	wallet.credit(500)
	assert_eq(wallet.hay, 4)


func test_hay_boost_doubles_what_leaves_the_pile() -> void:
	var wallet := Wallet.new(100)
	wallet.boost = 2
	assert_eq(wallet.credit(1000), 20)


func test_spend_takes_nothing_when_short() -> void:
	var wallet := Wallet.new(1)
	wallet.credit(99)
	assert_false(wallet.spend(100))
	assert_eq(wallet.hay, 99)
	assert_true(wallet.spend(99))
	assert_eq(wallet.hay, 0)


func test_buy_tool_once_and_machine_to_the_shelf() -> void:
	var economy := Economy.bundled()
	var inventory := Inventory.starting(economy)
	var park := MachinePark.new()
	var wallet := Wallet.new(1)
	assert_true(inventory.owns(&"rake"), "a new player owns the rake")
	assert_false(inventory.buy(economy, &"rake", wallet, park), "owned tools can't be bought again")
	var pitchfork := economy.item(&"pitchfork").price
	var conveyor := economy.item(&"conveyor").price
	wallet.credit(pitchfork + 2 * conveyor)
	assert_true(inventory.buy(economy, &"pitchfork", wallet, park))
	assert_false(inventory.buy(economy, &"pitchfork", wallet, park))
	assert_true(inventory.buy(economy, &"conveyor", wallet, park))
	assert_true(inventory.buy(economy, &"conveyor", wallet, park), "machines can be bought again")
	assert_eq(wallet.hay, 0, "Buy spends the hay up front (design D4)")
	assert_eq(park.shelf_count(&"conveyor"), 2, "bought machines wait on the shelf")
	assert_false(inventory.buy(economy, &"magnet", wallet, park), "short of hay")
	assert_false(inventory.owns(&"magnet"))
	assert_false(inventory.buy(economy, &"nope", wallet, park), "unknown id")


func test_cheapest_unowned_follows_price() -> void:
	var economy := Economy.bundled()
	var inventory := Inventory.starting(economy)
	var previous := -1
	while true:
		var it := inventory.cheapest_unowned(economy)
		if it == null:
			break
		assert_true(it.price >= previous)
		previous = it.price
		inventory.owned[it.id] = 1
	assert_eq(inventory.owned.size(), economy.items.size())


# --- Magnet tutorial -----------------------------------------------------------------------

func test_first_magnet_use_finds_a_tutorial_needle() -> void:
	var sim := PileSim.create(PileSpec.new(2, 128, 8000, 5, 1))
	var real := sim.needles[0]
	var far := Vector2i(real.x + 40 if real.x < 64 else real.x - 40, real.y)
	assert_eq(sim.magnet(far.x, far.y, 10).size(), 0, "nothing in reach without the tutorial")
	var found := sim.magnet(far.x, far.y, 10, true)
	assert_eq(found.size(), 1)
	assert_true(found[0].tutorial)
	assert_true(found[0].found)
	assert_eq(found[0].source, Needle.Source.PLAYER)
	assert_false(sim.is_complete(), "the tutorial needle doesn't count toward the pile")
	sim.magnet(real.x, real.y, 10)
	assert_true(sim.is_complete())


func test_tutorial_uses_a_real_needle_when_one_is_in_reach() -> void:
	var sim := PileSim.create(PileSpec.new(2, 128, 8000, 5, 1))
	var real := sim.needles[0]
	var found := sim.magnet(real.x, real.y, 10, true)
	assert_eq(found, [real] as Array[Needle])
	assert_false(real.tutorial)
	assert_eq(sim.needles.size(), 1)
