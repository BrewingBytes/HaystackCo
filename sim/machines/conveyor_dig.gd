class_name ConveyorDig
extends RefCounted
## A placed conveyor's dig pattern: a straight trench from its front edge toward the pile centre,
## cut from the top down (top-down trenches only, design D8). The floor is cleared to the ground;
## the side walls slope back at 2:1, the way loose hay settles, instead of standing as cliffs.
## Integers only; positions in cells, direction in 1/256 units.

const FIXED := 256
const WALL_RISE := 250  # height units per cell outward from the floor edge: 2:1 (about 63°)
const WALL_MARGIN := 2000  # stop walking out a wall once its profile is this far above the hay
const WALL_JITTER := 256  # ± height units per cell, so a wall reads as settled hay, not a plane

var origin_x: int
var origin_y: int
var dir_x: int
var dir_y: int
var width: int
var max_length: int
var rate: int  # height units removed per second
var front := 0
var _carry := 0  # leftover rate × ms below one height unit
var _budget := 0
var _removed := 0


func _init(p_origin_x: int, p_origin_y: int, p_dir_x: int, p_dir_y: int, p_width: int, p_max_length: int, p_rate: int) -> void:
	origin_x = p_origin_x
	origin_y = p_origin_y
	dir_x = p_dir_x
	dir_y = p_dir_y
	width = p_width
	max_length = p_max_length
	rate = p_rate


func done() -> bool:
	return front >= max_length


## Digs for `ms` milliseconds. Returns the hay removed, in height units.
func step(grid: HeightGrid, ms: int) -> int:
	var budget_ms := rate * ms + _carry
	_budget = budget_ms / 1000
	_carry = budget_ms % 1000
	_removed = 0
	var half := width >> 1
	while _budget > 0 and front < max_length:
		var left := 0  # hay still above the trench profile in this row
		for w in range(-half, width - half):
			left += _cut_at(grid, w, 0)
		left += _wall(grid, -half - 1, -1)
		left += _wall(grid, width - half, 1)
		if left == 0 and _budget > 0:
			front += 1
	if done():
		_carry = 0
	return _removed


## Walks one side wall outward from the floor edge, lowering hay to the 2:1 profile.
## Returns the hay still above the profile (when the budget ran out). Hot path in offline
## fast-forward: positions and bytes are handled inline.
func _wall(grid: HeightGrid, first_w: int, outward: int) -> int:
	var bytes := grid.bytes
	var n := grid.size
	var row_x := dir_x * front
	var row_y := dir_y * front
	var left := 0
	var cap := WALL_RISE
	var w := first_w
	while true:
		var x := origin_x + ((row_x - dir_y * w) >> 8)
		var y := origin_y + ((row_y + dir_x * w) >> 8)
		if x < 0 or y < 0 or x >= n or y >= n:
			break
		var offset := (y * n + x) << 1
		var h := bytes.decode_u16(offset)
		if h + WALL_MARGIN < cap:
			break
		var jitter := (((x * 73856093) ^ (y * 19349663)) & (2 * WALL_JITTER - 1)) - WALL_JITTER
		var cell_cap := maxi(0, cap + jitter)  # never below the ground (a u16 would wrap)
		if h > cell_cap:
			var take := mini(h - cell_cap, _budget)
			if take > 0:
				bytes.encode_u16(offset, h - take)
				grid.mark_dirty(x, y)
				_budget -= take
				_removed += take
			left += h - take - cell_cap
		w += outward
		cap += WALL_RISE
	return left


## Lowers the cell at lateral offset `w` of the current row to `cap`, within the budget.
## Returns how far it still sits above `cap`.
func _cut_at(grid: HeightGrid, w: int, cap: int) -> int:
	var x := origin_x + ((dir_x * front - dir_y * w) >> 8)
	var y := origin_y + ((dir_y * front + dir_x * w) >> 8)
	if not grid.in_bounds(x, y):
		return 0
	var h := grid.get_h(x, y)
	if h <= cap:
		return 0
	var take := mini(h - cap, _budget)
	if take > 0:
		grid.set_h(x, y, h - take)
		_budget -= take
		_removed += take
	return h - take - cap
