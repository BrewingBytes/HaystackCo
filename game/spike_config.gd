class_name SpikeConfig
extends RefCounted
## World scale and the G2 spike scenarios. The spike's job is to pick the largest grid that
## passes on the emulator (DEVICE-1); that grid becomes the biggest pile in the catalog (DESIGN.md Scale).

const CELL_M := 0.125  # one grid cell, in metres
const HEIGHT_UNIT_M := 0.001  # one height unit (1 mm)
const PEAK_PCT_OF_RADIUS := 50  # pile top = half its radius: about 45° at the foot
const PILE_SEED := 1
const DEFAULT_GRID := 1024

## Game Loop scenarios (`adb shell am start -a com.google.intent.action.TEST_LOOP ... --ei scenario N`
## or `godot -- --scenario=N`). Gate runs: 5-minute warm-up, then 60 s per phase.
const SCENARIOS := {
	1: {"name": "gate-orbit-1024", "grid": 1024, "camera": "orbit", "warmup_s": 300, "phase_s": 60},
	2: {"name": "gate-fixed-1024", "grid": 1024, "camera": "fixed", "warmup_s": 300, "phase_s": 60},
	3: {"name": "gate-orbit-768", "grid": 768, "camera": "orbit", "warmup_s": 300, "phase_s": 60},
	4: {"name": "gate-orbit-512", "grid": 512, "camera": "orbit", "warmup_s": 300, "phase_s": 60},
	9: {"name": "smoke-orbit-1024", "grid": 1024, "camera": "orbit", "warmup_s": 10, "phase_s": 10},
}


## Pile top for a grid, in height units.
static func peak_for(grid_size: int) -> int:
	return SimDefaults.peak_for(grid_size)
