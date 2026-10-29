class_name Wallet
extends RefCounted
## The player's hay. Hay is currency the moment it leaves the pile (design D16): there is no
## Sell step. The pile counts in height units; the wallet turns them into whole hay at the
## catalog's `unitsPerHay` and keeps the remainder, so no hay is lost between strokes.

var hay := 0
var units_per_hay: int
var boost := 1  # 2 while a "2× hay" reward runs (hayBoostMinutes)
var _carry := 0  # height units below one hay


func _init(p_units_per_hay: int) -> void:
	units_per_hay = p_units_per_hay


## Adds hay that left the pile (height units). Returns the whole hay gained.
func credit(units: int) -> int:
	var total := units * boost + _carry
	var gained := total / units_per_hay
	_carry = total % units_per_hay
	hay += gained
	return gained


func can_afford(price: int) -> bool:
	return hay >= price


## Takes `price` hay. False (and nothing taken) when there isn't enough.
func spend(price: int) -> bool:
	if hay < price:
		return false
	hay -= price
	return true
