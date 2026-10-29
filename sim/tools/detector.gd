class_name DetectorTool
extends RefCounted
## The metal detector never finds a needle; it beeps louder the closer the nearest unfound
## needle is. Strength 0..1000: 1000 right above it, half at `range_cells`, falling off as
## range² / (range² + d²).

const MAX_STRENGTH := 1000


static func strength(needles: Array[Needle], cx: int, cy: int, range_cells: int) -> int:
	var nearest := -1
	for needle in needles:
		if needle.found:
			continue
		var dx := needle.x - cx
		var dy := needle.y - cy
		var d2 := dx * dx + dy * dy
		if nearest < 0 or d2 < nearest:
			nearest = d2
	if nearest < 0:
		return 0
	var r2 := range_cells * range_cells
	return (MAX_STRENGTH * r2) / (r2 + nearest)
