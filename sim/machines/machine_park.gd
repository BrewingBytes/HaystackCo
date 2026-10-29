class_name MachinePark
extends RefCounted
## The player's machines: the shelf (bought, not placed) and the ones standing in the yard.
## Machines belong to the player, not the pile (Game Rules): they carry over to every pile.

class Placed:
	extends RefCounted
	var spec: MachineSpec
	var pose: Pose
	var dig: ConveyorDig

	func _init(p_spec: MachineSpec, p_pose: Pose) -> void:
		spec = p_spec
		pose = p_pose


var shelf: Array[MachineSpec] = []
var placed: Array[Placed] = []


## Buy puts the machine on the shelf (design D4); the economy (G5) has already taken the hay.
func buy(spec: MachineSpec) -> void:
	shelf.append(spec)


func shelf_count(id := &"") -> int:
	return shelf.filter(func(s: MachineSpec) -> bool: return id == &"" or s.id == id).size()


## Takes a shelved machine of this kind off the shelf; null if there isn't one.
func take_from_shelf(id: StringName) -> MachineSpec:
	for i in shelf.size():
		if shelf[i].id == id:
			var spec := shelf[i]
			shelf.remove_at(i)
			return spec
	return null


## Stands `spec` at `pose` on `sim` and starts its dig. The caller has checked the footprint.
func place(sim: PileSim, spec: MachineSpec, pose: Pose) -> Placed:
	var machine := Placed.new(spec, pose)
	_attach(sim, machine)
	placed.append(machine)
	return machine


## Picks a placed machine back up onto the shelf (moves are free).
func pick_up(sim: PileSim, machine: Placed) -> void:
	sim.machines.erase(machine.dig)
	placed.erase(machine)
	shelf.append(machine.spec)


## A new pile: machines now standing on hay go to the shelf; the rest start digging the new
## pile from where they stand (re-review D10). Returns the machines that were shelved.
func on_new_pile(sim: PileSim) -> Array[Placed]:
	var shelved: Array[Placed] = []
	var kept: Array[Placed] = []
	for machine in placed:
		if Placement.check(sim.grid, Placement.occupied_by(kept), machine.spec, machine.pose) == Placement.Problem.NONE:
			_attach(sim, machine)
			kept.append(machine)
		else:
			shelf.append(machine.spec)
			shelved.append(machine)
	placed = kept
	return shelved


func _attach(sim: PileSim, machine: Placed) -> void:
	var start := Placement.front(machine.spec, machine.pose)
	var d := machine.pose.dir()
	machine.dig = ConveyorDig.new(start.x, start.y, d.x, d.y, machine.spec.dig_width, machine.spec.reach, machine.spec.rate)
	sim.machines.append(machine.dig)
