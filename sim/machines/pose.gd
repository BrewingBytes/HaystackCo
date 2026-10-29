class_name Pose
extends RefCounted
## Where a machine stands: its centre cell and one of eight headings (45° steps). Cells may lie
## outside the pile grid, on the bare yard around it. Directions are in 1/256 units.

const DIRS: Array[Vector2i] = [
	Vector2i(256, 0), Vector2i(181, 181), Vector2i(0, 256), Vector2i(-181, 181),
	Vector2i(-256, 0), Vector2i(-181, -181), Vector2i(0, -256), Vector2i(181, -181),
]

var x: int
var y: int
var yaw: int  # 0..7


func _init(p_x: int, p_y: int, p_yaw: int) -> void:
	x = p_x
	y = p_y
	yaw = posmod(p_yaw, DIRS.size())


func dir() -> Vector2i:
	return DIRS[yaw]


func copy() -> Pose:
	return Pose.new(x, y, yaw)


func turned(steps: int) -> Pose:
	return Pose.new(x, y, yaw + steps)


## The heading (0..7) that points closest to (tx, ty) from this pose's cell.
static func yaw_toward(from_x: int, from_y: int, to_x: int, to_y: int) -> int:
	var best := 0
	var best_dot := -(1 << 62)
	for i in DIRS.size():
		var dot := DIRS[i].x * (to_x - from_x) + DIRS[i].y * (to_y - from_y)
		if dot > best_dot:
			best_dot = dot
			best = i
	return best
