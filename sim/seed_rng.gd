class_name SeedRng
extends RefCounted
## Deterministic integer RNG for the sim (xorshift32). No multiplications that could overflow
## 64-bit ints, so a C++ port gets the same sequence.

const MASK := 0xFFFFFFFF

var _state: int


func _init(seed: int) -> void:
	_state = mix(seed)
	if _state == 0:
		_state = 0x9E3779B9


func next() -> int:
	var x := _state
	x ^= (x << 13) & MASK
	x ^= x >> 17
	x ^= (x << 5) & MASK
	_state = x
	return x


## Uniform-ish integer in [lo, hi] (inclusive).
func range_int(lo: int, hi: int) -> int:
	return lo + next() % (hi - lo + 1)


## 32-bit avalanche of an integer (seed hashing). Products stay below 2^63.
static func mix(value: int) -> int:
	var h := value & MASK
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & MASK
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & MASK
	return h ^ (h >> 16)
