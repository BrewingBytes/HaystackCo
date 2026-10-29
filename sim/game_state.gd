class_name GameState
extends RefCounted
## Everything a save holds: the install seed, the current pile, the player's machines, hay and
## owned items, and the one-time cues (design D8). Pure data; SaveCodec turns it into bytes.

## One-time cues and hints (design D8); G9's HUD sets them.
const FLAGS: Array[StringName] = [&"cueShopSeen", &"cueGhostSeen", &"hintRakeDone"]

var economy: Economy
var install_seed: int
var sim: PileSim
var park := MachinePark.new()
var wallet: Wallet
var inventory: Inventory
var flags := {}  # StringName → bool, every key in FLAGS
var saved_at_unix := 0  # when this state was last saved
var clock := ClockGuard.new()
var credited := 0  # sim.collected already in the wallet (a loaded save has credited it all)
var ads := AdPolicy.new()
## Play time left on a "2× hay" reward (design D16). It counts down only while the game runs.
var boost_ms_left := 0


## A first launch: a random install seed and pile 1. `spec` overrides the catalog's pile 1
## (the frame harness uses its own grid size). Generates the pile: run it off the main thread.
static func new_game(p_economy: Economy, p_install_seed: int, spec: PileSpec = null) -> GameState:
	var state := GameState.new()
	state.economy = p_economy
	state.install_seed = p_install_seed
	state.sim = PileSim.create(spec if spec != null else SimDefaults.spec_for(1, p_install_seed, p_economy))
	state.wallet = Wallet.new(p_economy.units_per_hay)
	state.inventory = Inventory.starting(p_economy)
	for flag in FLAGS:
		state.flags[flag] = false
	return state


## Hay that left the pile since the last credit goes into the wallet (design D16). Returns
## the whole hay gained.
func credit_hay() -> int:
	var gained := wallet.credit(sim.collected - credited)
	credited = sim.collected
	return gained


## Play time passes: the 2× hay reward counts down (the wallet doubles while it runs).
func tick(ms: int) -> void:
	boost_ms_left = maxi(0, boost_ms_left - ms)
	wallet.boost = 2 if boost_ms_left > 0 else 1


## The "2× hay" reward: hay that leaves the pile counts double for hayBoostMinutes of play.
func grant_boost() -> void:
	credit_hay()  # hay from before the reward stays single
	boost_ms_left = economy.hay_boost_minutes * 60_000
	tick(0)


## Whether the player has bought a machine (placed or on the shelf): ads wait for the first.
func owns_machine() -> bool:
	return not park.placed.is_empty() or not park.shelf.is_empty()


## Pile n+1 for this install, generated. Slow: run it off the main thread.
func make_next_pile() -> PileSim:
	return PileSim.create(SimDefaults.spec_for(sim.spec.number + 1, install_seed, economy))


## Moves to `next` (from make_next_pile): leftover hay on the finished pile isn't harvested;
## machines on clear ground keep digging from where they stand, buried ones go to the shelf
## (re-review D10). Returns the shelved machines.
func enter_pile(next: PileSim) -> Array[MachinePark.Placed]:
	credit_hay()
	sim.machines.clear()
	sim = next
	credited = 0
	return park.on_new_pile(sim)


## Back from time away (a cold start or a resume): the clock guard decides how much time is
## owed, machines dig through it in coarse steps within this pile, and the hay is credited.
## Generates nothing but can take a while for long absences: run it off the main thread.
## Returns { owed_ms, used_ms, hay, found: Array[Needle], capped: bool, pile_done: bool }.
func come_back(now_unix: int, today: int) -> Dictionary:
	var away_ms := maxi(0, (now_unix - clock.last_seen_unix) * 1000)
	var owed := clock.credit(now_unix, today, economy.offline_cap_minutes, economy.daily_offline_cap_minutes)
	var found := sim.offline(owed) if owed > 0 else ([] as Array[Needle])
	wallet.boost = 1  # the 2× hay reward counts play time only; "2× offline" is its own reward
	var hay := credit_hay()
	tick(0)
	return {
		owed_ms = owed,
		used_ms = sim.offline_ms_used if owed > 0 else 0,
		hay = hay,
		found = found,
		capped = owed < away_ms,
		pile_done = sim.is_complete(),
	}


## A random install seed for a first launch (eng D5: piles 2+ hash it with n).
static func random_install_seed() -> int:
	return randi() & 0x7FFFFFFF
