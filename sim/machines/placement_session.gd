class_name PlacementSession
extends RefCounted
## Placement mode (design D4): a shelved machine becomes a ghost at the nearest valid spot at
## the pile's edge, facing the centre. The player drags it and turns it in 45° steps; PLACE
## stands it in the yard only while the spot is valid. Cancel, or the app going to the
## background, returns it to the shelf. Nothing here drops the machine on a finger lift.

var spec: MachineSpec
var pose: Pose
var _park: MachinePark
var _sim: PileSim
var _open := false


## Takes a `id` machine off the shelf and opens placement near cell `near`. Returns null when
## there's no such machine on the shelf.
static func begin(park: MachinePark, sim: PileSim, id: StringName, near: Vector2i) -> PlacementSession:
	var spec := park.take_from_shelf(id)
	if spec == null:
		return null
	var session := PlacementSession.new()
	session.spec = spec
	session._park = park
	session._sim = sim
	session._open = true
	var spot := Placement.nearest_edge_spot(sim.grid, park.placed, spec, near)
	# No valid spot anywhere: start at the near cell, invalid, so PLACE stays disabled.
	session.pose = spot if spot != null else Pose.new(near.x, near.y, Pose.yaw_toward(near.x, near.y, sim.grid.size / 2, sim.grid.size / 2))
	return session


func is_open() -> bool:
	return _open


func move_to(cell: Vector2i) -> void:
	pose = Pose.new(cell.x, cell.y, pose.yaw)


func turn(steps := 1) -> void:
	pose = pose.turned(steps)


func problem() -> Placement.Problem:
	return Placement.check(_sim.grid, Placement.occupied_by(_park.placed), spec, pose)


func can_place() -> bool:
	return _open and problem() == Placement.Problem.NONE


## PLACE: stands the machine in the yard. Returns null (and stays open) if the spot is invalid.
func confirm() -> MachinePark.Placed:
	if not can_place():
		return null
	_open = false
	return _park.place(_sim, spec, pose.copy())


## Cancel or app backgrounded: the machine goes back on the shelf; no hay is lost.
func cancel() -> void:
	if _open:
		_open = false
		_park.shelf.append(spec)
