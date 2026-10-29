#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

// C++ ports of sim hot paths (G2b). Same integer math as the GDScript references:
// test/unit/test_native_parity.gd compares them.
class SimNative : public RefCounted {
	GDCLASS(SimNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// PileGen.generate_gdscript: returns the size × size grid as little-endian u16 heights. Tuning comes from pile_gen.gd.
	static PackedByteArray generate(int64_t size, int64_t seed, int64_t peak, int64_t coarse_shift,
			int64_t fine_shift, int64_t coarse_amp_pct, int64_t fine_amp_pct);

	// BrushTool.apply_gdscript for every stamp in `stamps` (x, y pairs), in order. Returns
	// [bytes, collected, min_x, min_y, max_x, max_y] (the box of changed cells; min > max when none).
	static Array brush_stroke(const PackedByteArray &bytes, int64_t size, const PackedInt32Array &stamps,
			int64_t dir_x, int64_t dir_y, int64_t radius, int64_t depth, int64_t tine_spacing, int64_t ridge_pct,
			int64_t push_pct, int64_t push_cells);

	// HeightGrid.tile_delta_gdscript: for each tile in `tiles`, (base - grid) mod 2^16 per cell, in
	// tile_bytes() layout, concatenated. With `undo`, `grid` is that output and the result is the
	// tiles' heights again: base - delta.
	static PackedByteArray tile_delta(const PackedByteArray &base, const PackedByteArray &grid, int64_t size,
			const PackedInt32Array &tiles, bool undo);

	// Sum of the grid's u16 heights (HeightGrid.mass_gdscript).
	static int64_t sum_heights(const PackedByteArray &bytes);
};

} // namespace godot
