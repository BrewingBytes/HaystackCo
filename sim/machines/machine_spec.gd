class_name MachineSpec
extends RefCounted
## A machine kind from the catalog. Sizes in cells (12.5 cm), rate in height units per second.

var id: StringName
var length: int  # footprint along its facing
var width: int  # footprint across
var dig_width: int  # channel width
var reach: int  # how far the channel can advance from the front edge
var rate: int


func _init(p_id: StringName, p_length: int, p_width: int, p_dig_width: int, p_reach: int, p_rate: int) -> void:
	id = p_id
	length = p_length
	width = p_width
	dig_width = p_dig_width
	reach = p_reach
	rate = p_rate
