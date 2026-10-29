class_name Placement
extends RefCounted
## Footprint rules for placing a machine (re-review D10): inside the yard (the pile grid plus a
## strip of bare ground around it), not on hay, and not overlapping another machine.

const YARD_MARGIN := 96  # cells of bare yard beyond each side of the pile grid (12 m)
const ON_HAY_MAX := 150  # a footprint cell under more hay than this (15 cm) is "on hay"

enum Problem { NONE, OUT_OF_BOUNDS, ON_HAY, OVERLAP }


## `occupied` is occupied_by(placed machines): built once, reused across many checks.
static func check(grid: HeightGrid, occupied: Dictionary, spec: MachineSpec, pose: Pose) -> Problem:
	var cells := footprint(spec, pose)
	for cell in cells:
		if cell.x < -YARD_MARGIN or cell.y < -YARD_MARGIN or cell.x >= grid.size + YARD_MARGIN or cell.y >= grid.size + YARD_MARGIN:
			return Problem.OUT_OF_BOUNDS
	for cell in cells:
		if grid.in_bounds(cell.x, cell.y) and grid.get_h(cell.x, cell.y) > ON_HAY_MAX:
			return Problem.ON_HAY
	for cell in cells:
		if occupied.has(cell):
			return Problem.OVERLAP
	return Problem.NONE


## Every cell under a placed machine, as a set (exactly the cells `footprint` returns).
static func occupied_by(placed: Array) -> Dictionary:
	var cells := {}
	for machine in placed:
		for cell in footprint(machine.spec, machine.pose):
			cells[cell] = true
	return cells


## The cells a machine covers: its length × width rectangle, turned to its heading. Sampled at
## half-cell steps so diagonal headings have no gaps; each cell appears once.
static func footprint(spec: MachineSpec, pose: Pose) -> Array[Vector2i]:
	var d := pose.dir()
	var seen := {}
	for u in range(-spec.length, spec.length):
		for v in range(-spec.width, spec.width):
			seen[Vector2i(pose.x + ((d.x * u - d.y * v) >> 9), pose.y + ((d.y * u + d.x * v) >> 9))] = true
	var cells: Array[Vector2i] = []
	cells.assign(seen.keys())
	return cells


## The front edge's centre cell: where the dig channel starts.
static func front(spec: MachineSpec, pose: Pose) -> Vector2i:
	var d := pose.dir()
	var half := spec.length / 2 + 1
	return Vector2i(pose.x + ((d.x * half) >> 8), pose.y + ((d.y * half) >> 8))


## The valid spot at the pile's edge closest to `near` (a cell), facing the pile's centre:
## tries the eight headings and a few side offsets, walking outward from the pile's foot.
## Returns null when the whole yard is full.
static func nearest_edge_spot(grid: HeightGrid, placed: Array, spec: MachineSpec, near: Vector2i) -> Pose:
	var occupied := occupied_by(placed)
	var centre := grid.size / 2
	var foot := (grid.size * 40) / 100
	var limit := grid.size / 2 + YARD_MARGIN
	var best: Pose = null
	var best_d2 := -1
	for yaw in Pose.DIRS.size():
		var d := Pose.DIRS[yaw]
		for side in [0, -24, 24, -48, 48]:
			var r := foot
			while r <= limit:
				# Stand on the far side of the centre from the heading, so it faces inward.
				var x: int = centre - ((d.x * r) >> 8) + ((-d.y * side) >> 8)
				var y: int = centre - ((d.y * r) >> 8) + ((d.x * side) >> 8)
				var pose := Pose.new(x, y, yaw)
				var problem := check(grid, occupied, spec, pose)
				if problem == Problem.NONE:
					var d2 := (x - near.x) * (x - near.x) + (y - near.y) * (y - near.y)
					if best == null or d2 < best_d2:
						best = pose
						best_d2 = d2
					break
				if problem == Problem.OVERLAP:
					break
				r += 8
	return best
