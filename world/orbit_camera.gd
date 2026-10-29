class_name OrbitCamera
extends Camera3D
## Orbit camera around a focus point on the pile. "fixed" is the spike's fallback: a fixed
## three-quarter view with pan and zoom only (D7/D9 ladder, second rung).

const MIN_PITCH := deg_to_rad(8.0)
const MAX_PITCH := deg_to_rad(70.0)
const FIXED_PITCH := deg_to_rad(35.0)
const RECENTER_S := 0.32  # design D15: 320 ms ease back to the default view

var focus := Vector3.ZERO
var yaw := 0.0
var pitch := deg_to_rad(22.0)
var distance := 20.0
var min_distance := 6.0
var max_distance := 200.0
var fixed := false

var _default := {}
var _from := {}
var _recenter_t := -1.0


func _ready() -> void:
	fov = 55.0
	near = 0.2
	far = 1500.0


## Default view: one flank fills the screen, the top is out of frame (the pile is a landmark).
func frame_flank(pile_radius_m: float, flank_height_m: float) -> void:
	focus = Vector3(0.0, flank_height_m, pile_radius_m * 0.55)
	yaw = 0.0
	pitch = FIXED_PITCH if fixed else deg_to_rad(18.0)
	distance = pile_radius_m * 0.45
	min_distance = 5.0
	max_distance = pile_radius_m * 3.2
	_default = _view()
	_apply()


## True when the player has moved the camera away from its default view (shows recenter).
func is_off_default() -> bool:
	if _default.is_empty() or _recenter_t >= 0.0:
		return false
	return absf(wrapf(yaw - _default.yaw, -PI, PI)) > 0.05 or absf(pitch - _default.pitch) > 0.03 \
		or absf(distance / _default.distance - 1.0) > 0.08 or focus.distance_to(_default.focus) > 0.5


## Eases back to the default view over 320 ms, or jumps there under reduced motion.
func recenter(instant: bool) -> void:
	if _default.is_empty():
		return
	if instant:
		_set_view(_default)
		_recenter_t = -1.0
	else:
		_from = _view()
		_recenter_t = 0.0


func _process(delta: float) -> void:
	if _recenter_t < 0.0:
		return
	_recenter_t = minf(_recenter_t + delta / RECENTER_S, 1.0)
	var t := ease(_recenter_t, -2.0)  # ease in-out
	focus = _from.focus.lerp(_default.focus, t)
	yaw = _from.yaw + wrapf(_default.yaw - _from.yaw, -PI, PI) * t
	pitch = lerpf(_from.pitch, _default.pitch, t)
	distance = lerpf(_from.distance, _default.distance, t)
	_apply()
	if _recenter_t >= 1.0:
		_recenter_t = -1.0


func _view() -> Dictionary:
	return {"focus": focus, "yaw": yaw, "pitch": pitch, "distance": distance}


func _set_view(view: Dictionary) -> void:
	focus = view.focus
	yaw = view.yaw
	pitch = view.pitch
	distance = view.distance
	_apply()


func orbit(d_yaw: float, d_pitch: float) -> void:
	_recenter_t = -1.0
	if fixed:
		return
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, MIN_PITCH, MAX_PITCH)
	_apply()


## Moves the focus along the ground (fixed mode's one-finger drag).
func pan(d_right: float, d_forward: float) -> void:
	_recenter_t = -1.0
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	focus += right * d_right + forward * d_forward
	_apply()


func zoom(factor: float) -> void:
	_recenter_t = -1.0
	distance = clampf(distance * factor, min_distance, max_distance)
	_apply()


func set_view(p_yaw: float, p_pitch: float, p_distance: float) -> void:
	yaw = p_yaw
	pitch = clampf(p_pitch, MIN_PITCH, MAX_PITCH)
	distance = clampf(p_distance, min_distance, max_distance)
	_apply()


func _apply() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	look_at_from_position(focus + offset, focus, Vector3.UP)
