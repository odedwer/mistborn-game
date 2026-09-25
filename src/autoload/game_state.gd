extends Node
## Mission progress, checkpoints and save/load.
##
## Saves are versioned JSON files at `user://saves/slot_N.json`. Slot 0 is
## reserved for the quick save (F5/F9). `checkpoint_reached` and
## `mission_completed`/`objective_updated` from `Events` are listened to so
## the state stays current without other systems having to call in directly;
## other systems only need to keep emitting those signals.

signal save_completed(slot: int)
signal load_completed(slot: int)

const SAVE_VERSION := 1
const SAVE_DIR := "user://saves"
const QUICK_SLOT := 0
## Reserved slot for automatic saves (activity/mission completion). Distinct
## from the F5/F9 quick-save slot so autosaves never clobber a manual one.
const AUTOSAVE_SLOT := 99

## Player-visible progress.
var mission_id: StringName = &"mistwalk_to_keep_venture"
var mission_stage: int = 0
var completed_objectives: Array[StringName] = []

## Story progress, for the eventual open-world game: missions completed
## overall (across the whole story, not just the current one), and any
## side-activity/collectible state. `MissionDirector`/`StoryManager` read and
## write these; `GameState` only persists them.
var completed_missions: Array[StringName] = []
var mission_states: Dictionary = {}   # mission id (String) -> free-form state dict
var collectibles: Dictionary = {}     # collectible id (String) -> true if found
## The player's last known position in the open world, independent of mission
## checkpoints (used to resume "free roam" between missions). Captured on
## every save, so "save anywhere" restores exactly where the player was.
var open_world_position: Transform3D = Transform3D.IDENTITY
var has_open_world_position: bool = false

## Side-activity results, activity id (String) -> {completed: bool,
## best_time: float, medal: String ("bronze"/"silver"/"gold"/""), attempts: int}.
var activity_records: Dictionary = {}
## Allomantic mastery: points earned (from activities/mission rewards) and
## spent levels per upgrade id. See `Mastery` (src/mission/activities/mastery.gd).
var mastery_points: int = 0
var mastery_levels: Dictionary = {}   # upgrade id (String) -> level (int)

## Last checkpoint reached.
var last_checkpoint_id: StringName = &""
var last_checkpoint_transform: Transform3D = Transform3D.IDENTITY

## Snapshot of player reserves/coins/health taken at the last checkpoint.
var checkpoint_reserves: Dictionary = {}
var checkpoint_coins: int = 0
var checkpoint_vials: int = 0
var checkpoint_health: float = 100.0

## Run statistics.
var stat_time_seconds: float = 0.0
var stat_kills: int = 0
var stat_coins_thrown: int = 0
var stat_deaths: int = 0
var stat_detected_count: int = 0

var _has_save := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	Events.checkpoint_reached.connect(_on_checkpoint_reached)
	Events.objective_updated.connect(_on_objective_updated)
	Events.mission_completed.connect(_on_mission_completed)
	Events.alert_level_changed.connect(_on_alert_level_changed)


func _process(delta: float) -> void:
	stat_time_seconds += delta
	if Input.is_action_just_pressed("quick_save"):
		save_game(QUICK_SLOT)
	if Input.is_action_just_pressed("quick_load"):
		load_game(QUICK_SLOT)


func _on_checkpoint_reached(id: StringName) -> void:
	last_checkpoint_id = id
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if player is Node3D:
		last_checkpoint_transform = (player as Node3D).global_transform
	if "coins" in player:
		checkpoint_coins = player.coins
	if "vials" in player:
		checkpoint_vials = player.vials
	if "health" in player and player.health != null:
		checkpoint_health = player.health.current
	if "allomancer" in player and player.allomancer != null:
		checkpoint_reserves.clear()
		for metal in Metal.Type.values():
			checkpoint_reserves[metal] = player.allomancer.get_reserve(metal)


func _on_objective_updated(id: StringName, _text: String, done: bool) -> void:
	if done and not completed_objectives.has(id):
		completed_objectives.append(id)


func _on_mission_completed(id: StringName) -> void:
	record_mission_complete(id)
	autosave()


func _on_alert_level_changed(level: int) -> void:
	if level >= 1:
		stat_detected_count += 1


func record_kill() -> void:
	stat_kills += 1


func record_coin_thrown() -> void:
	stat_coins_thrown += 1


func record_death() -> void:
	stat_deaths += 1


func record_mission_complete(id: StringName) -> void:
	if not completed_missions.has(id):
		completed_missions.append(id)


func reset_run() -> void:
	mission_id = &"mistwalk_to_keep_venture"
	mission_stage = 0
	completed_objectives.clear()
	last_checkpoint_id = &""
	last_checkpoint_transform = Transform3D.IDENTITY
	checkpoint_reserves.clear()
	checkpoint_coins = 0
	checkpoint_vials = 0
	checkpoint_health = 100.0
	stat_time_seconds = 0.0
	stat_kills = 0
	stat_coins_thrown = 0
	stat_deaths = 0
	stat_detected_count = 0
	completed_missions.clear()
	mission_states.clear()
	collectibles.clear()
	open_world_position = Transform3D.IDENTITY
	has_open_world_position = false
	activity_records.clear()
	mastery_points = 0
	mastery_levels.clear()


# --- Side activities ---------------------------------------------------------

## Records the result of one attempt at side activity `id`. Keeps the best
## medal/time seen so far and grants `rewards` (coins/vials/mastery_points) to
## the player once. Autosaves afterwards (see `docs/OPEN_WORLD.md`).
func record_activity_result(id: StringName, completed: bool, elapsed: float, medal: StringName, rewards: Dictionary = {}) -> void:
	var key := String(id)
	var rec: Dictionary = activity_records.get(key, {"completed": false, "best_time": -1.0, "medal": "", "attempts": 0})
	rec["attempts"] = int(rec.get("attempts", 0)) + 1
	if completed:
		rec["completed"] = true
		var best: float = rec.get("best_time", -1.0)
		if best < 0.0 or elapsed < best:
			rec["best_time"] = elapsed
			rec["medal"] = String(medal)
		_grant_rewards(rewards)
	activity_records[key] = rec
	autosave()


func activity_record(id: StringName) -> Dictionary:
	return activity_records.get(String(id), {"completed": false, "best_time": -1.0, "medal": "", "attempts": 0})


func _grant_rewards(rewards: Dictionary) -> void:
	if rewards.is_empty():
		return
	mastery_points += int(rewards.get("mastery_points", 0))
	var player := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if player == null:
		return
	if rewards.has("coins") and player.has_method("add_pickup"):
		player.call("add_pickup", &"coins", float(rewards["coins"]))
	if rewards.has("vials") and player.has_method("add_pickup"):
		player.call("add_pickup", &"vial", float(rewards["vials"]))


## Marks `id` found (idempotent) and returns true the first time it is found.
func collect_item(id: StringName) -> bool:
	var key := String(id)
	if collectibles.get(key, false):
		return false
	collectibles[key] = true
	autosave()
	return true


func is_collected(id: StringName) -> bool:
	return bool(collectibles.get(String(id), false))


## Buys the next level of mastery upgrade `id`, applying it to the current
## player immediately. Returns true on success.
func buy_mastery(id: StringName) -> bool:
	var points_holder := [mastery_points]
	var ok := Mastery.try_upgrade(mastery_levels, points_holder, id)
	if ok:
		mastery_points = int(points_holder[0])
		var player := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
		if player != null:
			Mastery.apply_to(player, mastery_levels)
	return ok


func mastery_level(id: StringName) -> int:
	return int(mastery_levels.get(id, 0))


## Snapshots the player's live transform as the open-world resume point. Any
## save (manual or auto) calls this, so loading always resumes exactly where
## the player was, not just at the last mission checkpoint.
func capture_open_world_position() -> void:
	var player := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if player is Node3D:
		open_world_position = (player as Node3D).global_transform
		has_open_world_position = true


## Saves to the reserved autosave slot. Called after an activity or mission
## completes (see `_on_mission_completed` and `record_activity_result`).
func autosave() -> void:
	save_game(AUTOSAVE_SLOT)


# --- Save / load ---------------------------------------------------------------

func _slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"mission_id": String(mission_id),
		"mission_stage": mission_stage,
		"completed_objectives": completed_objectives.map(func(s): return String(s)),
		"last_checkpoint_id": String(last_checkpoint_id),
		"last_checkpoint_transform": _transform_to_array(last_checkpoint_transform),
		"checkpoint_reserves": _reserves_to_dict(checkpoint_reserves),
		"checkpoint_coins": checkpoint_coins,
		"checkpoint_vials": checkpoint_vials,
		"checkpoint_health": checkpoint_health,
		"stat_time_seconds": stat_time_seconds,
		"stat_kills": stat_kills,
		"stat_coins_thrown": stat_coins_thrown,
		"stat_deaths": stat_deaths,
		"stat_detected_count": stat_detected_count,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"completed_missions": completed_missions.map(func(s): return String(s)),
		"mission_states": mission_states,
		"collectibles": collectibles,
		"open_world_position": _transform_to_array(open_world_position),
		"has_open_world_position": has_open_world_position,
		"activity_records": activity_records,
		"mastery_points": mastery_points,
		"mastery_levels": _stringname_keys_to_str(mastery_levels),
	}


func from_dict(data: Dictionary) -> void:
	var version: int = data.get("version", 1)
	# `version` is kept for future migrations; only version 1 exists today.
	mission_id = StringName(data.get("mission_id", "mistwalk_to_keep_venture"))
	mission_stage = data.get("mission_stage", 0)
	completed_objectives.clear()
	for s in data.get("completed_objectives", []):
		completed_objectives.append(StringName(s))
	last_checkpoint_id = StringName(data.get("last_checkpoint_id", ""))
	last_checkpoint_transform = _array_to_transform(data.get("last_checkpoint_transform", []))
	checkpoint_reserves = _dict_to_reserves(data.get("checkpoint_reserves", {}))
	checkpoint_coins = data.get("checkpoint_coins", 0)
	checkpoint_vials = data.get("checkpoint_vials", 0)
	checkpoint_health = data.get("checkpoint_health", 100.0)
	stat_time_seconds = data.get("stat_time_seconds", 0.0)
	stat_kills = data.get("stat_kills", 0)
	stat_coins_thrown = data.get("stat_coins_thrown", 0)
	stat_deaths = data.get("stat_deaths", 0)
	stat_detected_count = data.get("stat_detected_count", 0)
	completed_missions.clear()
	for s in data.get("completed_missions", []):
		completed_missions.append(StringName(s))
	mission_states = data.get("mission_states", {})
	collectibles = data.get("collectibles", {})
	open_world_position = _array_to_transform(data.get("open_world_position", []))
	has_open_world_position = data.get("has_open_world_position", false)
	activity_records = data.get("activity_records", {})
	mastery_points = data.get("mastery_points", 0)
	mastery_levels = _str_keys_to_stringname(data.get("mastery_levels", {}))
	if version != SAVE_VERSION:
		push_warning("GameState: loaded save version %d, current is %d" % [version, SAVE_VERSION])


func save_game(slot: int) -> bool:
	capture_open_world_position()
	var f := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("GameState: could not open save slot %d for writing" % slot)
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	_has_save = true
	save_completed.emit(slot)
	return true


func load_game(slot: int) -> bool:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	from_dict(parsed)
	var player := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if player != null:
		Mastery.apply_to(player, mastery_levels)
	load_completed.emit(slot)
	return true


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


## Slot number of the most recently written save, or -1 if there is none.
func latest_slot() -> int:
	var best := -1
	var best_time := -1
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return -1
	for fname in DirAccess.get_files_at(SAVE_DIR):
		if not (fname.begins_with("slot_") and fname.ends_with(".json")):
			continue
		var slot := int(fname.trim_prefix("slot_").trim_suffix(".json"))
		var f := FileAccess.open(SAVE_DIR + "/" + fname, FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		var t: int = 0
		if typeof(parsed) == TYPE_DICTIONARY:
			t = parsed.get("saved_at_unix", 0)
		if t >= best_time:
			best_time = t
			best = slot
	return best


func continue_from_latest() -> bool:
	var slot := latest_slot()
	if slot == -1:
		return false
	return load_game(slot)


static func _transform_to_array(t: Transform3D) -> Array:
	return [
		t.basis.x.x, t.basis.x.y, t.basis.x.z,
		t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z,
		t.origin.x, t.origin.y, t.origin.z,
	]


static func _array_to_transform(a: Array) -> Transform3D:
	if a.size() < 12:
		return Transform3D.IDENTITY
	var basis := Basis(
		Vector3(a[0], a[1], a[2]),
		Vector3(a[3], a[4], a[5]),
		Vector3(a[6], a[7], a[8]),
	)
	return Transform3D(basis, Vector3(a[9], a[10], a[11]))


static func _stringname_keys_to_str(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = d[k]
	return out


static func _str_keys_to_stringname(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[StringName(k)] = d[k]
	return out


static func _reserves_to_dict(reserves: Dictionary) -> Dictionary:
	var out := {}
	for k in reserves:
		out[str(int(k))] = reserves[k]
	return out


static func _dict_to_reserves(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[int(k)] = d[k]
	return out
