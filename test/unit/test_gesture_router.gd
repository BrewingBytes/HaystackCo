extends GutTest
## G4: the yard's gesture state machine (design D4, D15).


class Recorder:
	extends RefCounted
	var top_band_below := 140.0
	var hay := true
	var ghost := false
	var calls: Array[String] = []
	var turns := 0
	var zooms: Array[float] = []

	func in_top_band(pos: Vector2) -> bool:
		return pos.y < top_band_below

	func hits_hay(_pos: Vector2) -> bool:
		return hay

	func hits_ghost(_pos: Vector2) -> bool:
		return ghost

	func orbit(_delta: Vector2) -> void:
		calls.append("orbit")

	func zoom(factor: float) -> void:
		calls.append("zoom")
		zooms.append(factor)

	func tool_start(_pos: Vector2) -> void:
		calls.append("tool_start")

	func tool_move(_pos: Vector2) -> void:
		calls.append("tool_move")

	func tool_end() -> void:
		calls.append("tool_end")

	func ghost_drag(_pos: Vector2) -> void:
		calls.append("ghost_drag")

	func ghost_turn(steps: int) -> void:
		turns += steps


var rec: Recorder
var router: GestureRouter


func before_each() -> void:
	rec = Recorder.new()
	router = GestureRouter.new(rec)


func test_one_finger_on_hay_uses_the_tool() -> void:
	router.touch_down(0, Vector2(300, 900), 0)
	router.touch_move(0, Vector2(320, 900))
	router.touch_up(0, 400)
	assert_eq(rec.calls, ["tool_start", "tool_move", "tool_end"])


func test_top_band_drag_orbits_even_over_hay() -> void:
	router.touch_down(0, Vector2(300, 100), 0)
	router.touch_move(0, Vector2(340, 100))
	router.touch_up(0, 400)
	assert_eq(rec.calls, ["orbit"])


func test_one_finger_on_ground_orbits() -> void:
	rec.hay = false
	router.touch_down(0, Vector2(300, 900), 0)
	router.touch_move(0, Vector2(340, 900))
	assert_eq(rec.calls, ["orbit"])


func test_double_tap_and_drag_zooms() -> void:
	router.touch_down(0, Vector2(300, 900), 0)
	router.touch_up(0, 100)
	router.touch_down(0, Vector2(305, 905), 250)
	router.touch_move(0, Vector2(305, 960))
	router.touch_up(0, 600)
	assert_true(rec.calls.has("zoom"))
	assert_lt(rec.zooms[-1], 1.0, "dragging down zooms in")
	assert_eq(rec.calls.count("tool_start"), 1, "only the first tap touched the pile")


func test_slow_second_tap_is_not_a_double_tap() -> void:
	router.touch_down(0, Vector2(300, 900), 0)
	router.touch_up(0, 100)
	router.touch_down(0, Vector2(305, 905), 500)
	router.touch_move(0, Vector2(305, 960))
	assert_false(rec.calls.has("zoom"))


func test_two_fingers_pinch_and_orbit_and_end_the_tool() -> void:
	router.touch_down(0, Vector2(300, 900), 0)
	router.touch_down(1, Vector2(500, 900), 50)
	router.touch_move(1, Vector2(600, 900))
	assert_eq(rec.calls.slice(0, 2), ["tool_start", "tool_end"])
	assert_true(rec.calls.has("zoom"))
	assert_true(rec.calls.has("orbit"))


func test_lifting_one_of_two_fingers_never_resumes_the_tool() -> void:
	router.touch_down(0, Vector2(300, 900), 0)
	router.touch_down(1, Vector2(500, 900), 50)
	router.touch_up(1, 100)
	router.touch_move(0, Vector2(360, 900))
	assert_eq(rec.calls.count("tool_start"), 1)
	assert_false(rec.calls.has("tool_move"))


func test_placing_turns_the_tool_off() -> void:
	router.set_placing(true)
	router.touch_down(0, Vector2(300, 900), 0)
	router.touch_move(0, Vector2(340, 900))
	assert_eq(rec.calls, ["orbit"])


func test_finger_on_the_ghost_drags_it_and_lifting_never_drops() -> void:
	router.set_placing(true)
	rec.ghost = true
	router.touch_down(0, Vector2(300, 900), 0)
	router.touch_move(0, Vector2(340, 900))
	router.touch_up(0, 500)
	assert_eq(rec.calls, ["ghost_drag"])
	assert_true(router.placing, "still placing after the lift")


func test_twist_turns_the_ghost_in_45_degree_steps() -> void:
	router.set_placing(true)
	rec.ghost = true
	router.touch_down(0, Vector2(400, 900), 0)
	router.touch_down(1, Vector2(600, 900), 10)
	# Rotate the second finger 100° around the first.
	router.touch_move(1, Vector2(400, 900) + Vector2(200, 0).rotated(deg_to_rad(50)))
	router.touch_move(1, Vector2(400, 900) + Vector2(200, 0).rotated(deg_to_rad(100)))
	assert_eq(rec.turns, 2)


func test_placement_waits_for_the_current_gesture() -> void:
	router.touch_down(0, Vector2(300, 900), 0)
	router.set_placing(true)
	assert_false(router.placing, "no RAKING → PLACING mid-gesture")
	router.touch_move(0, Vector2(320, 900))
	router.touch_up(0, 300)
	assert_true(router.placing, "applied once every finger is up")
	assert_eq(rec.calls, ["tool_start", "tool_move", "tool_end"])
