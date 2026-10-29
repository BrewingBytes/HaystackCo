class_name MagnetTool
extends RefCounted
## The magnet pulls a needle out from under any amount of hay, if the needle's centre is within
## its radius (cells, measured flat across the pile) during a drag. It moves no hay.


## Needles within `radius` of (cx, cy) that aren't found yet.
static func in_reach(needles: Array[Needle], cx: int, cy: int, radius: int) -> Array[Needle]:
	var hits: Array[Needle] = []
	for needle in needles:
		var dx := needle.x - cx
		var dy := needle.y - cy
		if not needle.found and dx * dx + dy * dy <= radius * radius:
			hits.append(needle)
	return hits
