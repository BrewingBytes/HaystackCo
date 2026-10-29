class_name OfflineSim
extends RefCounted
## Time away: steps every placed machine in coarse fixed steps (CEO D8 budget: 8 h < 500 ms on the emulator).

const STEP_MS := 60_000


## Advances `conveyors` by `ms` of time away. Returns the hay dug, in height units.
static func fast_forward(grid: HeightGrid, conveyors: Array[ConveyorDig], ms: int) -> int:
	var dug := 0
	var left := ms
	while left > 0:
		var step := mini(left, STEP_MS)
		for conveyor in conveyors:
			if not conveyor.done():
				dug += conveyor.step(grid, step)
		left -= step
	return dug
