class_name Reveal
extends RefCounted
## A needle is found when the hay left above it, averaged over its reveal square
## (cell_size × cell_size cells around it), drops to `threshold` height units or less.


## True when `needle` is uncovered on `grid`.
static func uncovered(grid: HeightGrid, needle: Needle, cell_size: int, threshold: int) -> bool:
	var half := cell_size >> 1
	var above := 0
	var cells := 0
	for y in range(needle.y - half, needle.y - half + cell_size):
		for x in range(needle.x - half, needle.x - half + cell_size):
			if not grid.in_bounds(x, y):
				continue
			above += maxi(0, grid.get_h(x, y) - needle.z)
			cells += 1
	return cells > 0 and above <= threshold * cells
