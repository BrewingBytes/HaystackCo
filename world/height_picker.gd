class_name HeightPicker
extends RefCounted
## Finger → pile point. The pile is displaced on the GPU, so it can't be ray-cast with physics:
## march the camera ray through the grid (≤ 64 steps), then refine the crossing by bisection.
## Picking is input, not sim, so floats are fine here.

const MAX_STEPS := 64
const BISECT_STEPS := 8


## Returns {"hit": bool, "hay": bool, "point": Vector3}. "hay" is false for bare ground.
static func pick(grid: HeightGrid, origin: Vector3, dir: Vector3) -> Dictionary:
	var half := grid.size * SpikeConfig.CELL_M * 0.5
	var top := HeightGrid.MAX_HEIGHT * SpikeConfig.HEIGHT_UNIT_M
	var span := _slab(origin, dir, Vector3(-half, 0.0, -half), Vector3(half, top, half))
	if span.x <= span.y:
		var step := (span.y - span.x) / MAX_STEPS
		var t := span.x
		for i in MAX_STEPS:
			var next := t + step
			var p := origin + dir * next
			if p.y <= height_at(grid, p.x, p.z):
				var lo := t
				var hi := next
				for j in BISECT_STEPS:
					var mid := (lo + hi) * 0.5
					var q := origin + dir * mid
					if q.y <= height_at(grid, q.x, q.z):
						hi = mid
					else:
						lo = mid
				var point := origin + dir * hi
				return {"hit": true, "hay": height_at(grid, point.x, point.z) > 0.02, "point": point}
			t = next
	# No hay: fall through to the ground plane.
	if dir.y < -0.0001:
		var t_ground := -origin.y / dir.y
		if t_ground > 0.0:
			return {"hit": true, "hay": false, "point": origin + dir * t_ground}
	return {"hit": false, "hay": false, "point": Vector3.ZERO}


## Bilinear pile height in metres at world (x, z); 0 off the grid.
static func height_at(grid: HeightGrid, x: float, z: float) -> float:
	var half := grid.size * 0.5
	var gx := x / SpikeConfig.CELL_M + half - 0.5
	var gz := z / SpikeConfig.CELL_M + half - 0.5
	var x0 := floori(gx)
	var z0 := floori(gz)
	if x0 < 0 or z0 < 0 or x0 + 1 >= grid.size or z0 + 1 >= grid.size:
		return 0.0
	var fx := gx - x0
	var fz := gz - z0
	var top := lerpf(grid.get_h(x0, z0), grid.get_h(x0 + 1, z0), fx)
	var bottom := lerpf(grid.get_h(x0, z0 + 1), grid.get_h(x0 + 1, z0 + 1), fx)
	return lerpf(top, bottom, fz) * SpikeConfig.HEIGHT_UNIT_M


## World point → grid cell (may be out of bounds).
static func cell_of(grid: HeightGrid, point: Vector3) -> Vector2i:
	var half := grid.size * 0.5
	return Vector2i(floori(point.x / SpikeConfig.CELL_M + half), floori(point.z / SpikeConfig.CELL_M + half))


## Ray/box overlap as (t_enter, t_exit); enter > exit means a miss.
static func _slab(origin: Vector3, dir: Vector3, lo: Vector3, hi: Vector3) -> Vector2:
	var t_enter := 0.0
	var t_exit := INF
	for axis in 3:
		if absf(dir[axis]) < 1e-8:
			if origin[axis] < lo[axis] or origin[axis] > hi[axis]:
				return Vector2(1.0, 0.0)
			continue
		var t1 := (lo[axis] - origin[axis]) / dir[axis]
		var t2 := (hi[axis] - origin[axis]) / dir[axis]
		t_enter = maxf(t_enter, minf(t1, t2))
		t_exit = minf(t_exit, maxf(t1, t2))
	return Vector2(t_enter, t_exit)
