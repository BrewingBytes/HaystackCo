class_name PileSim
extends RefCounted
## One pile in play: the grid, its buried needles, the placed machines and the hay ledger.
## Every way hay leaves the pile goes through here, and each returns the needles it uncovered,
## tagged with who found them (the NeedleFound source). Pure data: no Nodes, time or files.

var spec: PileSpec
var grid: HeightGrid
var needles: Array[Needle] = []
var machines: Array[ConveyorDig] = []
var initial_mass := 0
## SHA-256 of the freshly generated grid: a save regenerates the pile from its seed and checks
## it still comes out the same before laying the changed tiles back on.
var base_digest := ""
## A copy of the generated grid: saves store changed tiles as differences from it. (A copy:
## packed arrays assigned in GDScript share their data.)
var base_bytes := PackedByteArray()
## Tile → its packed bytes in the last save or load (SaveCodec reuses the ones still current).
var packed_tiles := {}
var offline_ms_used := 0  # of the last offline() call
## Hay that has left the pile; it's currency the moment it leaves (design D16).
var collected := 0
var reveal_cell := SimDefaults.REVEAL_CELL
var reveal_threshold := SimDefaults.REVEAL_THRESHOLD


## Generates the pile, buries its needles and records its mass. Slow for big piles: run it off
## the main thread.
static func create(p_spec: PileSpec) -> PileSim:
	var sim := PileSim.new()
	sim.spec = p_spec
	sim.grid = HeightGrid.new(p_spec.size)
	PileGen.generate(sim.grid, p_spec.seed, p_spec.peak)
	sim.base_digest = sim.grid.digest()
	sim.base_bytes = sim.grid.bytes.duplicate()
	sim.needles = PileGen.place_needles(sim.grid, p_spec)
	sim.initial_mass = sim.grid.mass()
	sim.grid.clear_touched()
	return sim


## A rake, pitchfork or blower stamp at cell (cx, cy); direction in 1/256 units.
func brush(tool: BrushSpec, cx: int, cy: int, dir_x: int, dir_y: int) -> Array[Needle]:
	collected += BrushTool.apply(grid, tool, cx, cy, dir_x, dir_y)
	return _reveal(Needle.Source.PLAYER)


## A whole stroke: `tool` stamped at each cell of `stamps` (x, y pairs). Needles are checked
## once, after the stroke.
func stroke(tool: BrushSpec, stamps: PackedInt32Array, dir_x: int, dir_y: int) -> Array[Needle]:
	collected += BrushTool.stroke(grid, tool, stamps, dir_x, dir_y)
	return _reveal(Needle.Source.PLAYER)


## The magnet at cell (cx, cy). With `tutorial` (the player's first magnet use) and no needle in
## reach, a tutorial needle is placed right under it, so the first drag always finds one.
func magnet(cx: int, cy: int, radius := SimDefaults.MAGNET_RADIUS, tutorial := false) -> Array[Needle]:
	var hits := MagnetTool.in_reach(needles, cx, cy, radius)
	if tutorial and hits.is_empty() and grid.in_bounds(cx, cy):
		var needle := Needle.new(cx, cy, grid.get_h(cx, cy) / 2)
		needle.tutorial = true
		needles.append(needle)
		hits.append(needle)
	for needle in hits:
		needle.found = true
		needle.source = Needle.Source.PLAYER
	return hits


## Beep strength 0..1000 at cell (cx, cy). Never finds anything.
func detector(cx: int, cy: int, range_cells := SimDefaults.DETECTOR_RANGE) -> int:
	return DetectorTool.strength(needles, cx, cy, range_cells)


## Placed machines dig for `ms` of play.
func advance_machines(ms: int) -> Array[Needle]:
	for machine in machines:
		if not machine.done():
			collected += machine.step(grid, ms)
	return _reveal(Needle.Source.MACHINE)


## Time away: machines dig in coarse steps (OfflineSim.STEP_MS) and finds are credited on
## return. Accrual stops when the pile is complete (offline never crosses into the next pile,
## CUT-OFFX) or when every machine has dug as far as it reaches; offline_ms_used says how much
## of `ms` was used.
func offline(ms: int) -> Array[Needle]:
	var found: Array[Needle] = []
	offline_ms_used = 0
	while offline_ms_used < ms and not is_complete() and machines.any(func(m: ConveyorDig) -> bool: return not m.done()):
		var step := mini(ms - offline_ms_used, OfflineSim.STEP_MS)
		collected += OfflineSim.fast_forward(grid, machines, step)
		found.append_array(_reveal(Needle.Source.OFFLINE))
		offline_ms_used += step
	return found


func is_complete() -> bool:
	for needle in needles:
		if not needle.found and not needle.tutorial:
			return false
	return true


## The ledger: pile mass + collected hay never changes (eng D4). Whole-grid pass: tests only.
func mass_balanced() -> bool:
	return grid.mass() + collected == initial_mass


func _reveal(source: Needle.Source) -> Array[Needle]:
	var found: Array[Needle] = []
	for needle in needles:
		if not needle.found and Reveal.uncovered(grid, needle, reveal_cell, reveal_threshold):
			needle.found = true
			needle.source = source
			found.append(needle)
	return found
