class_name PileSpec
extends RefCounted
## What a pile is made of. The economy catalog (G5) supplies these; SimDefaults has today's values.

var number: int  # pile n, from 1
var size: int  # grid cells per side (multiple of HeightGrid.TILE)
var peak: int  # dome top, height units
var seed: int
var needles: int


func _init(p_number: int, p_size: int, p_peak: int, p_seed: int, p_needles: int) -> void:
	number = p_number
	size = p_size
	peak = p_peak
	seed = p_seed
	needles = p_needles


## Pile 1 uses the catalog's fixed seed (a tuned first minute); later piles hash the install seed
## with n, so every install gets its own piles (eng D5).
static func seed_for(number: int, pile1_seed: int, install_seed: int) -> int:
	if number == 1:
		return pile1_seed
	return SeedRng.mix(SeedRng.mix(install_seed) ^ (number * 0x27D4EB2D))
