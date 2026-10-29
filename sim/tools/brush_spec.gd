class_name BrushSpec
extends RefCounted
## One brush tool's parameters (rake, pitchfork, blower are catalog entries of the same tool).

var id: StringName
var radius: int  # cells
var depth: int  # height units taken per stamp at the centre
var tine_spacing: int  # cells between furrows; 0 = no furrows
var ridge_pct: int  # share of `depth` taken between furrows
var push_pct: int  # share of the taken hay pushed ahead instead of collected
var push_cells: int  # how far ahead it lands


func _init(p_id: StringName, p_radius: int, p_depth: int, p_tine_spacing: int, p_ridge_pct: int, p_push_pct: int, p_push_cells: int) -> void:
	id = p_id
	radius = p_radius
	depth = p_depth
	tine_spacing = p_tine_spacing
	ridge_pct = p_ridge_pct
	push_pct = p_push_pct
	push_cells = p_push_cells
