class_name ActivityData
extends RefCounted
## Data-driven description of one side activity (coin race, rooftop pursuit,
## obligator ambush). Loaded from JSON under
## `res://src/mission/activities/data/*.json`, mirroring `MissionData`'s shape
## so writers can add activities without touching GDScript.
##
## `start_marker` names the "activity_start" world marker (meta
## `activity_id`) that starts this activity when the player walks/flies into
## it. `params` is free-form, interpreted by `ActivityManager` per `type`
## ("coin_race", "rooftop_pursuit", "obligator_ambush"). `rewards` may hold
## `coins`, `vials` and `mastery_points`.

var id: StringName
var type: StringName
var title: String
var start_marker: StringName
var params: Dictionary = {}
var rewards: Dictionary = {}


static func from_dict(d: Dictionary) -> ActivityData:
	var a := ActivityData.new()
	a.id = StringName(d.get("id", ""))
	a.type = StringName(d.get("type", ""))
	a.title = d.get("title", "")
	a.start_marker = StringName(d.get("start_marker", a.id))
	a.params = d.get("params", {})
	a.rewards = d.get("rewards", {})
	return a


static func load_from_file(path: String) -> ActivityData:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return from_dict(parsed)


## Loads every `*.json` activity file under `res://src/mission/activities/data/`
## except `collectibles.json` (a different, flat schema; see `CollectibleData`).
static func load_all(dir_path := "res://src/mission/activities/data") -> Array[ActivityData]:
	var out: Array[ActivityData] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for fname in dir.get_files():
		if fname.ends_with(".json") and fname != "collectibles.json":
			var a := load_from_file(dir_path + "/" + fname)
			if a != null:
				out.append(a)
	return out
