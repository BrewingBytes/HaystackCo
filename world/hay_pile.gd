class_name HayPile
extends Node3D
## Draws a HeightGrid: the displaced pile mesh, loose straw on its surface, and the height
## texture array that both read. Only dirty 64×64 tiles are re-uploaded each frame.

const HAY_SHADER := preload("res://world/hay.gdshader")
const STRAW_SHADER := preload("res://world/straw.gdshader")
const STRAW_ALBEDO := preload("res://world/textures/straw_albedo.png")
const STRAW_NORMAL := preload("res://world/textures/straw_normal.png")
const MESH_QUADS := 256  # per side: 257² ≈ 66K vertices
const FINE_CELLS := 192  # fine patch, one vertex per cell: 193² ≈ 37K (total ≤ 128K budget)
const STRAW_SIDE := 141  # 141² ≈ 20K straw cards (budget ≤ 20K)

var grid: HeightGrid
var tiles_uploaded_last_frame := 0
var _heights: Texture2DArray
var _hay_material: ShaderMaterial
var _fine_material: ShaderMaterial
var _straw_material: ShaderMaterial
var _fine_min := Vector2i(-1, -1)


func setup(p_grid: HeightGrid) -> void:
	for child in get_children():
		child.queue_free()  # the last pile's meshes (a new pile after "Next pile")
	grid = p_grid
	_fine_min = Vector2i(-1, -1)
	_build_texture()
	_build_mesh()
	_build_fine_patch()
	_build_straw()


## Re-uploads the tiles the sim touched since the last call. Returns how many.
func upload_dirty() -> int:
	var tiles := grid.take_dirty()
	for tile in tiles:
		_heights.update_layer(_tile_image(tile), tile)
	tiles_uploaded_last_frame = tiles.size()
	return tiles.size()


## The straw lattice and the fine patch follow the camera: `focus` is what it looks at,
## `eye` where it is. The patch is centred between them, nearer the focus, snapped to the
## coarse mesh so its edges line up with coarse vertices.
func set_focus(focus: Vector3, eye: Vector3) -> void:
	_straw_material.set_shader_parameter("focus", focus)
	var centre := focus.lerp(eye, 0.3)
	var stride := grid.size / MESH_QUADS
	var cell := HeightPicker.cell_of(grid, centre) - Vector2i(FINE_CELLS / 2, FINE_CELLS / 2)
	cell = Vector2i(snappedi(cell.x, stride), snappedi(cell.y, stride))
	cell = cell.clamp(Vector2i.ZERO, Vector2i(grid.size - FINE_CELLS, grid.size - FINE_CELLS))
	if cell != _fine_min:
		_fine_min = cell
		_hay_material.set_shader_parameter("fine_min", cell)
		_fine_material.set_shader_parameter("fine_min", cell)


func _build_texture() -> void:
	var images: Array[Image] = []
	for tile in grid.tiles_per_side * grid.tiles_per_side:
		images.append(_tile_image(tile))
	grid.take_dirty()
	_heights = Texture2DArray.new()
	_heights.create_from_images(images)


func _tile_image(tile: int) -> Image:
	return Image.create_from_data(HeightGrid.TILE, HeightGrid.TILE, false, Image.FORMAT_RG8, grid.tile_bytes(tile))


func _common_params(material: ShaderMaterial) -> void:
	material.set_shader_parameter("heights", _heights)
	material.set_shader_parameter("grid_size", grid.size)
	material.set_shader_parameter("tiles_per_side", grid.tiles_per_side)
	material.set_shader_parameter("cell_m", SpikeConfig.CELL_M)
	material.set_shader_parameter("height_unit_m", SpikeConfig.HEIGHT_UNIT_M)


func _build_mesh() -> void:
	var size_m := grid.size * SpikeConfig.CELL_M
	var plane := PlaneMesh.new()
	plane.size = Vector2(size_m, size_m)
	plane.subdivide_width = MESH_QUADS - 1
	plane.subdivide_depth = MESH_QUADS - 1
	_hay_material = ShaderMaterial.new()
	_hay_material.shader = HAY_SHADER
	_common_params(_hay_material)
	_hay_material.set_shader_parameter("stride", grid.size / MESH_QUADS)
	_hay_material.set_shader_parameter("fine_cells", FINE_CELLS)
	_hay_material.set_shader_parameter("straw_albedo", STRAW_ALBEDO)
	_hay_material.set_shader_parameter("straw_normal", STRAW_NORMAL)
	var mesh := MeshInstance3D.new()
	mesh.name = "PileMesh"
	mesh.mesh = plane
	mesh.material_override = _hay_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var top := HeightGrid.MAX_HEIGHT * SpikeConfig.HEIGHT_UNIT_M
	mesh.custom_aabb = AABB(Vector3(-size_m * 0.5, 0.0, -size_m * 0.5), Vector3(size_m, top, size_m))
	add_child(mesh)


func _build_fine_patch() -> void:
	var size_m := FINE_CELLS * SpikeConfig.CELL_M
	var plane := PlaneMesh.new()
	plane.size = Vector2(size_m, size_m)
	plane.subdivide_width = FINE_CELLS - 1
	plane.subdivide_depth = FINE_CELLS - 1
	_fine_material = _hay_material.duplicate()
	_fine_material.set_shader_parameter("is_fine", true)
	var mesh := MeshInstance3D.new()
	mesh.name = "FinePatch"
	mesh.mesh = plane
	mesh.material_override = _fine_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader moves the patch, so its bounds are the whole pile.
	var pile_m := grid.size * SpikeConfig.CELL_M
	var top := HeightGrid.MAX_HEIGHT * SpikeConfig.HEIGHT_UNIT_M
	mesh.custom_aabb = AABB(Vector3(-pile_m, 0.0, -pile_m), Vector3(pile_m * 2.0, top, pile_m * 2.0))
	add_child(mesh)


func _build_straw() -> void:
	var card := QuadMesh.new()
	card.size = Vector2(0.025, 0.28)
	card.center_offset = Vector3(0.0, 0.14, 0.0)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = card
	multimesh.instance_count = STRAW_SIDE * STRAW_SIDE
	# Identity transforms: the shader places every card.
	var identity := PackedFloat32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0])
	var buffer := PackedFloat32Array()
	for i in multimesh.instance_count:
		buffer.append_array(identity)
	multimesh.buffer = buffer
	_straw_material = ShaderMaterial.new()
	_straw_material.shader = STRAW_SHADER
	_common_params(_straw_material)
	_straw_material.set_shader_parameter("side", STRAW_SIDE)
	_straw_material.set_shader_parameter("straw_albedo", STRAW_ALBEDO)
	var straw := MultiMeshInstance3D.new()
	straw.name = "Straw"
	straw.multimesh = multimesh
	straw.material_override = _straw_material
	straw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var size_m := grid.size * SpikeConfig.CELL_M
	var top := HeightGrid.MAX_HEIGHT * SpikeConfig.HEIGHT_UNIT_M
	straw.custom_aabb = AABB(Vector3(-size_m * 0.5, 0.0, -size_m * 0.5), Vector3(size_m, top, size_m))
	add_child(straw)
