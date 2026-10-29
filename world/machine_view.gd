class_name MachineView
extends Node3D
## A machine in the yard: the blueprint ghost while placing (DESIGN.md "Placement ghost"), then
## the steel body that prints in from the base up when placed. Blocky until G11's conveyor model.

const HEIGHT_M := 1.1
const PRINT_S := 0.4
const GHOST_FILL := Color(0.173, 0.435, 0.718, 0.35)  # ghost-fill #2C6FB7 at 35%
const GHOST_LINE := Color("#EEF1EC")
const GHOST_INVALID := Color("#FF8A78")
const TICK_EVERY := 32  # cells (4 m) between reach ticks

var spec: MachineSpec
var _body: MeshInstance3D
var _edges: MeshInstance3D
var _reach: MeshInstance3D
var _line_material: StandardMaterial3D
var _print_material: ShaderMaterial
var _print_t := -1.0
var _ring: MeshInstance3D


func _init(p_spec: MachineSpec) -> void:
	spec = p_spec


func _ready() -> void:
	var length_m := spec.length * SpikeConfig.CELL_M
	var width_m := spec.width * SpikeConfig.CELL_M
	var box := BoxMesh.new()
	box.size = Vector3(width_m, HEIGHT_M, length_m)
	_body = MeshInstance3D.new()
	_body.mesh = box
	_body.position.y = HEIGHT_M * 0.5
	add_child(_body)
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.vertex_color_use_as_albedo = false
	_line_material.albedo_color = GHOST_LINE
	_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Blueprint lines draw over the hay: the reach channel runs into the pile.
	_line_material.no_depth_test = true
	_edges = MeshInstance3D.new()
	_edges.mesh = _box_edges(Vector3(width_m, HEIGHT_M, length_m))
	_edges.material_override = _line_material
	_edges.position.y = HEIGHT_M * 0.5
	add_child(_edges)
	_reach = MeshInstance3D.new()
	_reach.mesh = _reach_ticks(length_m * 0.5, spec.reach * SpikeConfig.CELL_M, width_m)
	_reach.material_override = _line_material
	add_child(_reach)
	show_ghost(true)


## Stands the view on its pose (cells → world).
func set_pose(pose: Pose, grid_size: int) -> void:
	var half := grid_size * 0.5
	position = Vector3((pose.x + 0.5 - half) * SpikeConfig.CELL_M, 0.0, (pose.y + 0.5 - half) * SpikeConfig.CELL_M)
	var d := pose.dir()
	rotation = Vector3(0.0, atan2(d.x, d.y), 0.0)  # local +Z faces the heading


## Blueprint: translucent wash plus edges; red edges when the spot is invalid.
func show_ghost(valid: bool) -> void:
	var fill := StandardMaterial3D.new()
	fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.albedo_color = GHOST_FILL
	_body.material_override = fill
	_line_material.albedo_color = GHOST_LINE if valid else GHOST_INVALID
	_edges.visible = true
	_reach.visible = true


## Selected (tapped): a `text` outline on the ground around the footprint, with its label.
func set_selected(on: bool) -> void:
	if _ring == null:
		var pad := 0.25
		var h := Vector2(spec.width * SpikeConfig.CELL_M * 0.5 + pad, spec.length * SpikeConfig.CELL_M * 0.5 + pad)
		var y := 0.04
		var corners := [Vector3(-h.x, y, -h.y), Vector3(h.x, y, -h.y), Vector3(h.x, y, h.y), Vector3(-h.x, y, h.y)]
		var points := PackedVector3Array()
		for i in 4:
			points.append_array([corners[i], corners[(i + 1) % 4]])
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = GHOST_LINE
		material.no_depth_test = true
		_ring = MeshInstance3D.new()
		_ring.mesh = _lines(points)
		_ring.material_override = material
		add_child(_ring)
	_ring.visible = on


## PLACE: prints into steel over 400 ms (instant under reduced motion).
func print_in(reduce_motion: bool) -> void:
	_print_material = ShaderMaterial.new()
	_print_material.shader = preload("res://world/machine_print.gdshader")
	_print_material.set_shader_parameter("height_m", HEIGHT_M)
	_body.material_override = _print_material
	_reach.visible = false
	if reduce_motion:
		_finish_print()
	else:
		_print_material.set_shader_parameter("progress", 0.0)
		_print_t = 0.0


func _process(delta: float) -> void:
	if _print_t < 0.0:
		return
	_print_t = minf(_print_t + delta / PRINT_S, 1.0)
	_print_material.set_shader_parameter("progress", _print_t)
	_line_material.albedo_color.a = 1.0 - _print_t
	if _print_t >= 1.0:
		_finish_print()


func _finish_print() -> void:
	_print_t = -1.0
	_print_material.set_shader_parameter("progress", 1.0)
	_edges.visible = false


func _box_edges(size: Vector3) -> ArrayMesh:
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for x in [-h.x, h.x]:
		for y in [-h.y, h.y]:
			for z in [-h.z, h.z]:
				corners.append(Vector3(x, y, z))
	var points := PackedVector3Array()
	for a in corners.size():
		for b in range(a + 1, corners.size()):
			var diff := corners[a] - corners[b]
			var axes := int(absf(diff.x) > 0.0) + int(absf(diff.y) > 0.0) + int(absf(diff.z) > 0.0)
			if axes == 1:
				points.append(corners[a])
				points.append(corners[b])
	return _lines(points)


## The channel the machine will dig: two rails from its front edge out to its reach, with a
## cross tick every 4 m (the blueprint's dimension ticks).
func _reach_ticks(front_m: float, reach_m: float, width_m: float) -> ArrayMesh:
	var points := PackedVector3Array()
	var y := 0.05
	var w := width_m * 0.4
	points.append_array([Vector3(-w, y, front_m), Vector3(-w, y, front_m + reach_m), Vector3(w, y, front_m), Vector3(w, y, front_m + reach_m)])
	var tick := TICK_EVERY * SpikeConfig.CELL_M
	var along := 0.0
	while along <= reach_m:
		points.append_array([Vector3(-w * 1.6, y, front_m + along), Vector3(w * 1.6, y, front_m + along)])
		along += tick
	return _lines(points)


func _lines(points: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh
