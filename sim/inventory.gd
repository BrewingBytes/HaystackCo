class_name Inventory
extends RefCounted
## What the player owns, by catalog item id (the save stores ids and counts, never prices), and
## the one-time magnet tutorial flag. Buy spends the hay up front; a machine then waits on the
## shelf until it's placed (design D4).

var owned := {}  # StringName → count
var magnet_tutorial_done := false


## A new player: owns every free item (the rake).
static func starting(economy: Economy) -> Inventory:
	var inventory := Inventory.new()
	for it in economy.items:
		if it.price == 0:
			inventory.owned[it.id] = 1
	return inventory


func owns(id: StringName) -> bool:
	return owned.get(id, 0) > 0


## Tools are bought once; machines any number of times. False when the item is unknown,
## already owned (tools) or the wallet is short; nothing changes then.
func buy(economy: Economy, id: StringName, wallet: Wallet, park: MachinePark) -> bool:
	var it := economy.item(id)
	if it == null or (it.machine == null and owns(id)) or not wallet.spend(it.price):
		return false
	owned[id] = owned.get(id, 0) + 1
	if it.machine != null:
		park.buy(it.machine)
	return true


## The cheapest catalog item not owned yet (catalog order breaks ties), or null.
func cheapest_unowned(economy: Economy) -> Economy.Item:
	var best: Economy.Item = null
	for it in economy.items:
		if not owns(it.id) and (best == null or it.price < best.price):
			best = it
	return best
