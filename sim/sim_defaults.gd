class_name SimDefaults
extends RefCounted
## The sim's fixed units, plus shortcuts into the bundled economy catalog (sim/economy.json),
## which holds every tunable number. Integers only. Cells are 12.5 cm; heights are millimetres.

const CELL_MM := 125

static var ECONOMY := Economy.bundled()
static var PILE1_SEED := ECONOMY.pile1_seed
static var REVEAL_CELL := ECONOMY.reveal_cell  # cells per side of a needle's reveal square
static var REVEAL_THRESHOLD := ECONOMY.reveal_threshold  # mean hay left above the needle, height units
static var MAGNET_RADIUS := ECONOMY.item(&"magnet").radius  # cells
static var DETECTOR_RANGE := ECONOMY.item(&"detector").radius  # cells where the beep is at half strength

static var RAKE := ECONOMY.brush(&"rake")
static var PITCHFORK := ECONOMY.brush(&"pitchfork")
static var BLOWER := ECONOMY.brush(&"blower")
static var CONVEYOR := ECONOMY.machine(&"conveyor")


## Pile n's grid size; the last size repeats.
static func pile_size(number: int) -> int:
	return ECONOMY.pile_size(number)


## Pile top: half the pile's radius (about 45° at the foot), in height units.
static func peak_for(size: int) -> int:
	return (size * 47 / 100) * CELL_MM / 2


static func needles_for(number: int) -> int:
	return ECONOMY.needles_for(number)


static func spec_for(number: int, install_seed: int, economy := ECONOMY) -> PileSpec:
	var size := economy.pile_size(number)
	return PileSpec.new(number, size, peak_for(size), PileSpec.seed_for(number, economy.pile1_seed, install_seed), economy.needles_for(number))
