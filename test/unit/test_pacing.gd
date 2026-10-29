extends GutTest
## G5: the pacing gate (CEO D12). The full 500-seed run is tools/check_pacing.gd in CI; these
## run a few seeds so a pacing break shows up in the unit suite too.

const Gate := preload("res://tools/pacing_gate.gd")
const Bot := preload("res://tools/pacing_bot.gd")
const SEEDS := 3


func _economy_with(price_factor: int) -> Economy:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Economy.BUNDLED_PATH))
	for item: Dictionary in data.items:
		item.price = int(item.price) * price_factor
	return Economy.from_dict(data).economy


func test_bundled_economy_meets_the_targets() -> void:
	var result := Gate.run(Economy.bundled(), SEEDS, false)
	assert_true(result.ok, "\n".join(result.lines))
	assert_lte(result.first_needle_ms, Gate.FIRST_NEEDLE_MAX_MS)
	assert_lte(result.worst_machine_ms, Gate.FIRST_MACHINE_MAX_MS)


func test_over_priced_economy_fails() -> void:
	var result := Gate.run(_economy_with(3), SEEDS, false)
	assert_false(result.ok, "3× prices must miss the 10-minute machine target")
	assert_gt(result.worst_machine_ms, Gate.FIRST_MACHINE_MAX_MS)


func test_bot_buys_cheapest_first_and_places_the_machine() -> void:
	var bot := Bot.new(Economy.bundled(), 1)
	bot.play(Gate.FIRST_MACHINE_MAX_MS)
	var ids: Array = bot.buys.map(func(b: Array) -> StringName: return b[0])
	assert_eq(ids, [&"pitchfork", &"magnet", &"blower", &"detector", &"conveyor"])
	assert_eq(bot.park.placed.size(), 1, "the conveyor stands in the yard")
	assert_true(bot.sim.mass_balanced())


func test_bot_uses_the_brush_that_moves_the_most_hay() -> void:
	var economy := Economy.bundled()
	var bot := Bot.new(economy, 1)
	assert_eq(bot._brush, economy.brush(&"rake"))
	bot.inventory.owned[&"pitchfork"] = 1
	bot.inventory.owned[&"blower"] = 1
	bot._pick_brush()
	assert_eq(bot._brush, economy.brush(&"pitchfork"), "the blower pushes most of its hay instead of collecting it")
