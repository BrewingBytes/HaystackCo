class_name Needle
extends RefCounted
## A needle buried in the pile: a grid cell and the height it lies at (height units).

enum Source { NONE, PLAYER, MACHINE, OFFLINE }

var x: int
var y: int
var z: int
var found := false
var source := Source.NONE
## The magnet tutorial's needle: placed in reach on the first magnet use, never counts toward
## the pile, and never makes an ad moment (Game Rules).
var tutorial := false


func _init(p_x: int, p_y: int, p_z: int) -> void:
	x = p_x
	y = p_y
	z = p_z
