class_name Mastery
extends RefCounted
## Allomantic mastery: light progression bought with mastery points earned
## from side activities and story rewards.
##
## Every upgrade is levelled (index 0 = not bought). `levels` holds the
## resulting tuning value at each level (index 0 is always the base/default
## value); `cost` holds the mastery points needed to go from level i to i+1.
## `apply_to(player)` recomputes every exported tuning value from scratch (it
## multiplies/overwrites from a fixed base), so it is safe to call repeatedly
## (after loading a save, after buying an upgrade) without compounding.
##
## This never touches `Allomancer`'s internal simulation logic: it only sets
## the same `@export` tuning values a designer would drag in the inspector.

## Defaults matching `Allomancer`'s own script defaults (see allomancy/allomancer.gd).
const BASE_PUSH_FORCE := 3000.0
const BASE_LINE_RANGE := 40.0
## Defaults matching `Player`'s own script defaults (see player/player.gd).
const BASE_COIN_POUCH := 200
const BASE_VIAL_CAPACITY := 5

const UPGRADES := {
	&"push_force": {
		"label": "Push / Pull Force",
		"desc": "Push and Pull hit harder.",
		"levels": [1.0, 1.10, 1.20],
		"cost": [1, 2],
	},
	&"steel_range": {
		"label": "Steel Range",
		"desc": "Steel and iron reach further.",
		"levels": [1.0, 1.15],
		"cost": [2],
	},
	&"flare_efficiency": {
		"label": "Flare Efficiency",
		"desc": "Flaring burns reserves slower.",
		"levels": [1.0, 0.85],
		"cost": [2],
	},
	&"pewter_endurance": {
		"label": "Pewter Endurance",
		"desc": "Pewter reserves last longer.",
		"levels": [1.0, 0.8],
		"cost": [2],
	},
	&"tin_range": {
		"label": "Tin Range",
		"desc": "Tin cuts through more of the mist.",
		"levels": [1.0, 1.2],
		"cost": [1],
	},
	&"coin_pouch": {
		"label": "Coin Pouch",
		"desc": "Carry more coins.",
		"levels": [BASE_COIN_POUCH, 320, 500],
		"cost": [1, 2],
	},
	&"vial_capacity": {
		"label": "Vial Capacity",
		"desc": "Carry more metal vials.",
		"levels": [BASE_VIAL_CAPACITY, 8, 12],
		"cost": [1, 2],
	},
}


static func ids() -> Array:
	return UPGRADES.keys()


static func max_level(id: StringName) -> int:
	var u: Dictionary = UPGRADES.get(id, {})
	var levels: Array = u.get("levels", [1.0])
	return levels.size() - 1


## Mastery points needed to go from `level` to `level + 1`, or -1 if maxed.
static func cost_for_next(id: StringName, level: int) -> int:
	var u: Dictionary = UPGRADES.get(id, {})
	var costs: Array = u.get("cost", [])
	if level < 0 or level >= costs.size():
		return -1
	return int(costs[level])


static func value_at(id: StringName, level: int) -> float:
	var u: Dictionary = UPGRADES.get(id, {})
	var levels: Array = u.get("levels", [1.0])
	var i := clampi(level, 0, levels.size() - 1)
	return float(levels[i])


## Attempts to buy the next level of `id`. `levels` is GameState.mastery_levels
## (StringName -> int) and `points` is GameState.mastery_points, both passed
## by reference dictionaries/values the caller persists. Returns true on
## success (deducting the cost from `points_holder[0]` and bumping the level).
static func try_upgrade(levels: Dictionary, points_holder: Array, id: StringName) -> bool:
	if not UPGRADES.has(id):
		return false
	var cur: int = int(levels.get(id, 0))
	var cost := cost_for_next(id, cur)
	if cost < 0 or int(points_holder[0]) < cost:
		return false
	points_holder[0] = int(points_holder[0]) - cost
	levels[id] = cur + 1
	return true


## Recomputes every tuning value this system controls from `levels`
## (StringName -> int) and applies it to `player` (and its Allomancer).
## Safe to call any number of times.
static func apply_to(player: Node, levels: Dictionary) -> void:
	if player == null or not is_instance_valid(player):
		return
	var allomancer: Node = player.get("allomancer") if "allomancer" in player else null
	if allomancer != null and is_instance_valid(allomancer):
		allomancer.set("base_force", BASE_PUSH_FORCE * value_at(&"push_force", int(levels.get(&"push_force", 0))))
		allomancer.set("line_range", BASE_LINE_RANGE * value_at(&"steel_range", int(levels.get(&"steel_range", 0))))
		# `Allomancer` reads these two multipliers if present; defaulting to 1.0
		# when the export doesn't exist yet keeps this additive-only.
		if _has_property(allomancer, "flare_burn_efficiency"):
			allomancer.set("flare_burn_efficiency", value_at(&"flare_efficiency", int(levels.get(&"flare_efficiency", 0))))
		if _has_property(allomancer, "pewter_burn_efficiency"):
			allomancer.set("pewter_burn_efficiency", value_at(&"pewter_endurance", int(levels.get(&"pewter_endurance", 0))))
		if _has_property(allomancer, "tin_strength_mult"):
			allomancer.set("tin_strength_mult", value_at(&"tin_range", int(levels.get(&"tin_range", 0))))
	if _has_property(player, "coin_pouch_max"):
		player.set("coin_pouch_max", int(value_at(&"coin_pouch", int(levels.get(&"coin_pouch", 0)))))
	if _has_property(player, "vial_capacity_max"):
		player.set("vial_capacity_max", int(value_at(&"vial_capacity", int(levels.get(&"vial_capacity", 0)))))


static func _has_property(obj: Object, name: String) -> bool:
	for p in obj.get_property_list():
		if p["name"] == name:
			return true
	return false
