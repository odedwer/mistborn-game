class_name MissionData
extends RefCounted
## Data-driven description of one mission (main story or side activity).
##
## Loaded from JSON under `res://src/mission/missions/*.json` so writers can
## add missions without touching GDScript. `MissionDirector` is a generic
## runner over this data; only `mistwalk_to_keep_venture.json` (the vertical
## slice) ships today, but the format is meant to scale to the whole story and
## to side activities (coin races, rooftop pursuits, ambushes, collectibles).
##
## Objective `type`s the runner understands:
## - `reach_marker`: complete when the player enters a radius of a world
##   marker (see `marker_group`, looked up via `objective_point` group or
##   `LuthadelWorld.get_marker_data()`).
## - `interact`: complete when `Events.pickup_collected` (or a matching
##   `objective_point` proximity, as a stand-in for a real interact prompt)
##   fires with `kind == interact_kind`.
## - `defeat`: complete when `Events.actor_died` fires for an actor in
##   `target_group`.
## - `escape`: complete on reaching `marker_group` (same as reach_marker) —
##   kept distinct for clarity/UI text ("Escape to the canal").
## - `use_metal`: complete the first time `Events.metal_burn_changed` (or
##   `allomantic_line_used` for steel/iron) fires for `metal`.
## - `collect`: complete when `Events.pickup_collected` fires with a matching
##   `kind`; used for atium beads / Kelsier's notes / other collectibles.
## - `cutscene_hint`: no player action; fires `Events.hint_requested` with
##   `text` and completes immediately (used for Kelsier's tutorial lines).
##
## `on_complete` is an array of action dictionaries applied when the
## objective completes, e.g. `{"action": "spawn_enemy", "type": "inquisitor"}`
## or `{"action": "mission_complete"}`.

var id: StringName
var title: String
var act: String
var chapter: String
var prerequisites: Array[StringName] = []
var stages: Array = []          # Array[Dictionary]
var fail_conditions: Array = [] # Array[Dictionary]
var rewards: Dictionary = {}


static func from_dict(d: Dictionary) -> MissionData:
	var m := MissionData.new()
	m.id = StringName(d.get("id", ""))
	m.title = d.get("title", "")
	m.act = d.get("act", "")
	m.chapter = d.get("chapter", "")
	for p in d.get("prerequisites", []):
		m.prerequisites.append(StringName(p))
	m.stages = d.get("stages", [])
	m.fail_conditions = d.get("fail_conditions", [])
	m.rewards = d.get("rewards", {})
	return m


static func load_from_file(path: String) -> MissionData:
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


## Loads every `*.json` mission file under `res://src/mission/missions/`.
static func load_all(dir_path := "res://src/mission/missions") -> Array[MissionData]:
	var out: Array[MissionData] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for fname in dir.get_files():
		if fname.ends_with(".json"):
			var m := load_from_file(dir_path + "/" + fname)
			if m != null:
				out.append(m)
	return out
