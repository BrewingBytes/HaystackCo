#include "sim_native.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <vector>

namespace godot {

namespace {

constexpr int64_t MAX_HEIGHT = 65535;

// Mirrors PileGen._lattice: deterministic value in [-amp, amp].
int64_t lattice(int64_t seed, int64_t x, int64_t y, int64_t amp) {
	int64_t h = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF;
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF;
	h = h ^ (h >> 16);
	return ((h & 0xFFFF) * 2 * amp) / 0xFFFF - amp;
}

// Mirrors PileGen._fade_table: smoothstep weights 0..2^shift.
std::vector<int64_t> fade_table(int64_t shift) {
	const int64_t cell = int64_t(1) << shift;
	std::vector<int64_t> table(cell);
	for (int64_t f = 0; f < cell; f++) {
		table[f] = (f * f * (3 * cell - 2 * f)) / (cell * cell);
	}
	return table;
}

// Mirrors PileGen._lattice_row.
void lattice_row(std::vector<int64_t> &out, int64_t seed, int64_t y, int64_t shift, int64_t amp, const std::vector<int64_t> &fade) {
	const int64_t ly = y >> shift;
	const int64_t fy = fade[y & ((int64_t(1) << shift) - 1)];
	for (int64_t lx = 0; lx < int64_t(out.size()); lx++) {
		const int64_t a = lattice(seed, lx, ly, amp);
		const int64_t b = lattice(seed, lx, ly + 1, amp);
		out[lx] = (a * ((int64_t(1) << shift) - fy) + b * fy) >> shift;
	}
}

} // namespace

PackedByteArray SimNative::generate(int64_t size, int64_t seed, int64_t peak, int64_t coarse_shift,
		int64_t fine_shift, int64_t coarse_amp_pct, int64_t fine_amp_pct) {
	PackedByteArray bytes;
	bytes.resize(size * size * 2);
	bytes.fill(0);
	uint8_t *out = bytes.ptrw();
	const int64_t n = size;
	const int64_t centre = n >> 1;
	const int64_t radius = (n * 47) / 100;
	const int64_t r2_max = radius * radius;
	const int64_t coarse_amp = (peak * coarse_amp_pct) / 100;
	const int64_t fine_amp = (peak * fine_amp_pct) / 100;
	std::vector<int64_t> coarse_row((n >> coarse_shift) + 2);
	std::vector<int64_t> fine_row((n >> fine_shift) + 2);
	const std::vector<int64_t> coarse_fade = fade_table(coarse_shift);
	const std::vector<int64_t> fine_fade = fade_table(fine_shift);
	const int64_t coarse_mask = (int64_t(1) << coarse_shift) - 1;
	const int64_t fine_mask = (int64_t(1) << fine_shift) - 1;
	for (int64_t y = 0; y < n; y++) {
		const int64_t dy = y - centre;
		const int64_t dy2 = dy * dy;
		if (dy2 >= r2_max) {
			continue;
		}
		lattice_row(coarse_row, seed, y, coarse_shift, coarse_amp, coarse_fade);
		lattice_row(fine_row, seed ^ 0x5bd1e995, y, fine_shift, fine_amp, fine_fade);
		for (int64_t x = 0; x < n; x++) {
			const int64_t dx = x - centre;
			const int64_t r2 = dx * dx + dy2;
			if (r2 >= r2_max) {
				continue;
			}
			const int64_t dome = (peak * (r2_max - r2)) / r2_max;
			const int64_t cx = x >> coarse_shift;
			const int64_t fx = coarse_fade[x & coarse_mask];
			const int64_t coarse = (coarse_row[cx] * ((coarse_mask + 1) - fx) + coarse_row[cx + 1] * fx) >> coarse_shift;
			const int64_t gx = x >> fine_shift;
			const int64_t gfx = fine_fade[x & fine_mask];
			const int64_t fine = (fine_row[gx] * ((fine_mask + 1) - gfx) + fine_row[gx + 1] * gfx) >> fine_shift;
			const int64_t h = dome + ((coarse + fine) * dome) / peak;
			if (h > 0) {
				const int64_t v = std::min(h, MAX_HEIGHT);
				const int64_t offset = (y * n + x) << 1;
				out[offset] = uint8_t(v & 0xFF);
				out[offset + 1] = uint8_t(v >> 8);
			}
		}
	}
	return bytes;
}

int64_t SimNative::sum_heights(const PackedByteArray &bytes) {
	const uint8_t *in = bytes.ptr();
	const int64_t cells = bytes.size() / 2;
	int64_t total = 0;
	for (int64_t i = 0; i < cells; i++) {
		total += int64_t(in[i * 2]) | (int64_t(in[i * 2 + 1]) << 8);
	}
	return total;
}

Array SimNative::brush_stroke(const PackedByteArray &bytes, int64_t size, const PackedInt32Array &stamps,
		int64_t dir_x, int64_t dir_y, int64_t radius, int64_t depth, int64_t tine_spacing, int64_t ridge_pct,
		int64_t push_pct, int64_t push_cells) {
	if (size <= 0 || bytes.size() != size * size * 2 || radius <= 0) {
		return Array(); // a caller bug: an empty result instead of reading past the grid
	}
	PackedByteArray grid = bytes;
	uint8_t *out = grid.ptrw();
	const int64_t n = size;
	const int64_t r = radius;
	const int64_t r2 = r * r;
	std::vector<int64_t> falloff(r2 + 1);
	for (int64_t d2 = 0; d2 <= r2; d2++) {
		falloff[d2] = ((r2 - d2) * 256) / r2;
	}
	const int64_t push_dx = (dir_x * push_cells) >> 8;
	const int64_t push_dy = (dir_y * push_cells) >> 8;
	const int64_t half_tine = tine_spacing >> 1;
	int64_t collected = 0;
	int64_t min_x = n, min_y = n, max_x = -1, max_y = -1;
	auto touch = [&](int64_t x, int64_t y) {
		min_x = std::min(min_x, x);
		min_y = std::min(min_y, y);
		max_x = std::max(max_x, x);
		max_y = std::max(max_y, y);
	};
	auto get = [&](int64_t offset) { return int64_t(out[offset]) | (int64_t(out[offset + 1]) << 8); };
	auto put = [&](int64_t offset, int64_t v) {
		out[offset] = uint8_t(v & 0xFF);
		out[offset + 1] = uint8_t(v >> 8);
	};
	for (int64_t s = 0; s + 1 < stamps.size(); s += 2) {
		const int64_t cx = stamps[s];
		const int64_t cy = stamps[s + 1];
		for (int64_t dy = -r; dy <= r; dy++) {
			const int64_t y = cy + dy;
			if (y < 0 || y >= n) {
				continue;
			}
			for (int64_t dx = -r; dx <= r; dx++) {
				const int64_t d2 = dx * dx + dy * dy;
				if (d2 > r2) {
					continue;
				}
				const int64_t x = cx + dx;
				if (x < 0 || x >= n) {
					continue;
				}
				const int64_t offset = (y * n + x) << 1;
				const int64_t h = get(offset);
				if (h == 0) {
					continue;
				}
				int64_t share = 100;
				if (tine_spacing > 0) {
					const int64_t across = (dx * -dir_y + dy * dir_x) >> 8;
					const int64_t m = ((across % tine_spacing) + tine_spacing) % tine_spacing;
					share = m < half_tine ? 100 : ridge_pct;
				}
				const int64_t take = std::min(h, (depth * falloff[d2] * share) / 25600);
				if (take <= 0) {
					continue;
				}
				put(offset, h - take);
				touch(x, y);
				const int64_t pushed = (take * push_pct) / 100;
				collected += take - pushed;
				if (pushed > 0) {
					// BrushTool._deposit: what doesn't fit (off the grid or above MAX_HEIGHT) is collected.
					const int64_t px = x + push_dx;
					const int64_t py = y + push_dy;
					if (px < 0 || py < 0 || px >= n || py >= n) {
						collected += pushed;
						continue;
					}
					const int64_t poffset = (py * n + px) << 1;
					const int64_t ph = get(poffset);
					const int64_t placed = std::min(pushed, MAX_HEIGHT - ph);
					if (placed > 0) {
						put(poffset, ph + placed);
						touch(px, py);
					}
					collected += pushed - placed;
				}
			}
		}
	}
	Array result;
	result.append(grid);
	result.append(collected);
	result.append(min_x);
	result.append(min_y);
	result.append(max_x);
	result.append(max_y);
	return result;
}

PackedByteArray SimNative::tile_delta(const PackedByteArray &base, const PackedByteArray &grid, int64_t size,
		const PackedInt32Array &tiles, bool undo) {
	constexpr int64_t TILE = 64;
	const int64_t per_side = size / TILE;
	const int64_t tile_bytes = TILE * TILE * 2;
	// A caller bug gets an empty result instead of reads past the end.
	if (size <= 0 || size % TILE != 0 || base.size() != size * size * 2 ||
			grid.size() != (undo ? tiles.size() * tile_bytes : size * size * 2)) {
		return PackedByteArray();
	}
	for (int64_t i = 0; i < tiles.size(); i++) {
		if (tiles[i] < 0 || tiles[i] >= per_side * per_side) {
			return PackedByteArray();
		}
	}
	PackedByteArray out;
	out.resize(tiles.size() * TILE * TILE * 2);
	uint8_t *dst = out.ptrw();
	const uint8_t *b = base.ptr();
	const uint8_t *g = grid.ptr();
	int64_t at = 0;
	for (int64_t i = 0; i < tiles.size(); i++) {
		const int64_t tx = (tiles[i] % per_side) * TILE;
		const int64_t ty = (tiles[i] / per_side) * TILE;
		for (int64_t row = 0; row < TILE; row++) {
			for (int64_t col = 0; col < TILE; col++) {
				const int64_t cell = ((ty + row) * size + tx + col) << 1;
				// `undo`: grid holds the deltas, laid out like the output.
				const int64_t other = undo ? at : cell;
				const int64_t bv = int64_t(b[cell]) | (int64_t(b[cell + 1]) << 8);
				const int64_t gv = int64_t(g[other]) | (int64_t(g[other + 1]) << 8);
				const int64_t v = (bv - gv) & 0xFFFF;
				dst[at] = uint8_t(v & 0xFF);
				dst[at + 1] = uint8_t(v >> 8);
				at += 2;
			}
		}
	}
	return out;
}

void SimNative::_bind_methods() {
	ClassDB::bind_static_method("SimNative",
			D_METHOD("generate", "size", "seed", "peak", "coarse_shift", "fine_shift", "coarse_amp_pct", "fine_amp_pct"),
			&SimNative::generate);
	ClassDB::bind_static_method("SimNative", D_METHOD("sum_heights", "bytes"), &SimNative::sum_heights);
	ClassDB::bind_static_method("SimNative",
			D_METHOD("brush_stroke", "bytes", "size", "stamps", "dir_x", "dir_y", "radius", "depth", "tine_spacing",
					"ridge_pct", "push_pct", "push_cells"),
			&SimNative::brush_stroke);
	ClassDB::bind_static_method("SimNative", D_METHOD("tile_delta", "base", "grid", "size", "tiles", "undo"),
			&SimNative::tile_delta);
}

} // namespace godot
