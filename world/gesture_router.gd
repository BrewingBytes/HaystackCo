class_name GestureRouter
extends RefCounted
## The yard's gesture state machine (Eng Re-review Section 1, amended by design D4 and D15).
## Feed it touches; it calls the delegate. Pure logic: tests drive it with a fake delegate.
##
##  IDLE ─1 finger─▶ in the top band? ─▶ ORBITING          double-tap + drag ─▶ ZOOMING
##                   on hay? ─▶ TOOL (tool_start/move/end)  else ─▶ ORBITING
##  any ─2nd finger─▶ PINCH (zoom + orbit)                  (a tool stroke ends first)
##  PLACING: finger on the ghost ─▶ DRAG_GHOST (lifting never drops it);
##           2nd finger while dragging ─▶ TWIST (turns the ghost in 45° steps);
##           elsewhere ─▶ camera as above. The tool is off while placing.
##  A new gesture starts only from IDLE: placement requested mid-gesture waits for all fingers up.
##
## Delegate methods:
##   in_top_band(pos) -> bool, hits_hay(pos) -> bool, hits_ghost(pos) -> bool
##   orbit(delta: Vector2), zoom(factor: float)
##   tool_start(pos), tool_move(pos), tool_end()
##   ghost_drag(pos), ghost_turn(steps: int)
##   tap(pos) (optional): a single tap that wasn't on the hay, outside placement

enum State { IDLE, ORBITING, TOOL, ZOOMING, PINCH, DRAG_GHOST, TWIST }

const DOUBLE_TAP_MS := 300
const TAP_MAX_MS := 250
const TAP_SLOP_DP := 12.0  # a tap moves less than this
const DOUBLE_TAP_RADIUS_DP := 48.0
const ZOOM_PER_DP := 0.006  # double-tap-drag: down zooms in
const TWIST_STEP := PI / 4.0  # one 45° turn per this much finger rotation

var state := State.IDLE
var placing := false
var dp := 1.0  # pixels per dp

var _delegate: Object
var _touches := {}  # index → position
var _down_ms := 0
var _down_pos := Vector2.ZERO
var _travel := 0.0
var _last_tap_ms := -100000
var _last_tap_pos := Vector2.ZERO
var _pinch_distance := 0.0
var _pinch_mid := Vector2.ZERO
var _twist_angle := 0.0
var _twist_accum := 0.0
var _pending_placing := -1  # -1 none, 0 leave, 1 enter


func _init(delegate: Object) -> void:
	_delegate = delegate


## Enters or leaves placement mode. Mid-gesture, the change waits until every finger is up.
func set_placing(value: bool) -> void:
	if state == State.IDLE and _touches.is_empty():
		_apply_placing(value)
	else:
		_pending_placing = 1 if value else 0


func touch_down(index: int, pos: Vector2, now_ms: int) -> void:
	_touches[index] = pos
	if _touches.size() == 1:
		_begin_single(pos, now_ms)
	elif _touches.size() == 2:
		_begin_double()


func touch_move(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var previous: Vector2 = _touches[index]
	_touches[index] = pos
	if _touches.size() == 1:
		_travel += previous.distance_to(pos)
	match state:
		State.ORBITING:
			_delegate.orbit(pos - previous)
		State.TOOL:
			_delegate.tool_move(pos)
		State.ZOOMING:
			_delegate.zoom(exp(-(pos.y - previous.y) / dp * ZOOM_PER_DP))
		State.DRAG_GHOST:
			_delegate.ghost_drag(pos)
		State.PINCH:
			_update_pinch()
		State.TWIST:
			_update_twist()


func touch_up(index: int, now_ms: int) -> void:
	if not _touches.has(index):
		return
	_touches.erase(index)
	if not _touches.is_empty():
		return  # a gesture ends only when every finger is up; it never resumes as another
	if state == State.TOOL:
		_delegate.tool_end()
	var was_tap := now_ms - _down_ms <= TAP_MAX_MS and _travel <= TAP_SLOP_DP * dp and state != State.ZOOMING
	if was_tap:
		_last_tap_ms = now_ms
		_last_tap_pos = _down_pos
		# A tap off the hay (not a stroke, not placing): the yard may select what's under it.
		if state == State.ORBITING and not placing and _delegate.has_method("tap"):
			_delegate.tap(_down_pos)
	state = State.IDLE
	if _pending_placing >= 0:
		_apply_placing(_pending_placing == 1)
		_pending_placing = -1


## App backgrounded or input lost: end everything cleanly.
func reset() -> void:
	if state == State.TOOL:
		_delegate.tool_end()
	_touches.clear()
	state = State.IDLE
	if _pending_placing >= 0:
		_apply_placing(_pending_placing == 1)
		_pending_placing = -1


func _begin_single(pos: Vector2, now_ms: int) -> void:
	var double_tap := now_ms - _last_tap_ms <= DOUBLE_TAP_MS and pos.distance_to(_last_tap_pos) <= DOUBLE_TAP_RADIUS_DP * dp
	_down_ms = now_ms
	_down_pos = pos
	_travel = 0.0
	if placing and _delegate.hits_ghost(pos):
		state = State.DRAG_GHOST
	elif double_tap:
		state = State.ZOOMING
	elif placing or _delegate.in_top_band(pos) or not _delegate.hits_hay(pos):
		state = State.ORBITING
	else:
		state = State.TOOL
		_delegate.tool_start(pos)


func _begin_double() -> void:
	match state:
		State.TOOL:
			_delegate.tool_end()
			_start_pinch()
		State.DRAG_GHOST:
			state = State.TWIST
			_twist_angle = _pair_angle()
			_twist_accum = 0.0
		State.TWIST, State.PINCH:
			pass
		_:
			_start_pinch()


func _start_pinch() -> void:
	state = State.PINCH
	var pair := _pair()
	_pinch_distance = pair[0].distance_to(pair[1])
	_pinch_mid = (pair[0] + pair[1]) * 0.5


func _update_pinch() -> void:
	if _touches.size() < 2:
		return
	var pair := _pair()
	var distance: float = pair[0].distance_to(pair[1])
	var mid: Vector2 = (pair[0] + pair[1]) * 0.5
	if _pinch_distance > 0.0 and distance > 0.0:
		_delegate.zoom(_pinch_distance / distance)
	_delegate.orbit(mid - _pinch_mid)
	_pinch_distance = distance
	_pinch_mid = mid


func _update_twist() -> void:
	if _touches.size() < 2:
		return
	var angle := _pair_angle()
	_twist_accum += wrapf(angle - _twist_angle, -PI, PI)
	_twist_angle = angle
	while _twist_accum >= TWIST_STEP:
		_twist_accum -= TWIST_STEP
		_delegate.ghost_turn(1)
	while _twist_accum <= -TWIST_STEP:
		_twist_accum += TWIST_STEP
		_delegate.ghost_turn(-1)


func _pair() -> Array:
	var keys := _touches.keys()
	keys.sort()
	return [_touches[keys[0]], _touches[keys[1]]]


func _pair_angle() -> float:
	var pair := _pair()
	return (pair[1] - pair[0]).angle()


func _apply_placing(value: bool) -> void:
	placing = value
