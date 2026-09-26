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
## - `dialogue`: complete when `Events.dialogue_finished` fires for
##   `dialogue_id` (see `DialogueSystem`, `res://src/mission/dialogues/*.json`).
##   Usually started by an NPC's own interact script, not the objective
##   itself.
## - `reach_speed`: complete once the player's `CharacterBody3D.velocity`
##   reaches `min_speed` (polled; used for pull-swing/coin-jump lessons).
## - `chain_pushes`: complete after `count` distinct Pushes/Pulls of `metal`
##   (default steel) each within `max_gap` seconds of the last.
## - `flare_metal`: complete the first time the player flares `metal`.
## - `defeat_in_duel`: identical to `defeat` (an `Events.actor_died` for
##   `target_group`); kept as its own name for clarity in a scripted duel.
## - `flag_count`: complete once `count` of the story flags in `flags` are set
##   (see `GameState.dialogue_flags`); used for "talk to 3 nobles".
## - `crowd_mood` (Act II): complete once the first node in group
##   `mood_group` (default `"crowd_mood"`, see `CrowdMoodMeter`) has its
##   `mood` property past `target`, in the direction given by `direction`
##   (`"above"` or `"below"`); used for "soothe the crowd below 30" /
##   "riot the crowd above 70".
## - `push_target` (Act II): complete the first time
##   `Events.allomantic_line_used` fires with a `target` whose meta
##   `objective_id` matches `marker_id` — any Push/Pull counts, any metal.
##   Used for the House War set piece (topple the iron gate/chandelier).
## - `survive` (Act II): complete `duration` seconds after the objective
##   activates, purely by elapsed time (used for "survive the Inquisitor's
##   first strike").
## - `cutscene` (Act III): complete when `Events.cutscene_finished` fires for
##   `cutscene_id` (see `CutsceneSystem`, `res://src/mission/cutscenes/`).
## `interact`/`reach_marker`/`escape` also accept an optional `require_metal`
## (a `Metal.Type`): the trigger only completes the objective while that
## metal is burning (tin to eavesdrop on a rumor), otherwise it shows
## `hint_locked`.
##
## `on_complete` is an array of action dictionaries applied when the
## objective completes, e.g. `{"action": "spawn_enemy", "type": "inquisitor"}`
## or `{"action": "mission_complete"}`. A stage may also carry `"on_enter"`,
## the same action list, run once when the stage activates (used to lock/
## unlock metals, start a cutscene or dialogue, or enter/exit an interior).
## Actions: `spawn_enemy`, `hint`, `mission_complete`, `set_allowed_metals`
## (`metals`: list of `Metal.Type`, empty = unlock all), `start_dialogue`
## (`dialogue_id`), `start_cutscene` (`cutscene_id`), `enter_interior`/
## `exit_interior` (`scene`, via `SceneTransition`), `set_flag` (`flag`,
## `value`).
## Act III actions: `switch_interior` (`scene`: swap one interior for another
## under a single fade), `call_group` (`group`, `method`, optional `args`:
## lets a scene stage its own scripted beats, e.g. a boss phase change),
## `drain_metals` (`metals`, empty = all: empties the player's reserves and
## vials), `grant_metals` (`metals`, empty = all ordinary metals, `amount`:
## tops reserves up) and `roll_credits` (the finale: credits, then post-game
## free roam).
##
## `journal` (Act III on, optional): a first-person summary shown in the pause
## menu's journal once the mission is complete.
##
## `fail_conditions` (Act II on): a stage may carry `"fail_conditions"`, a
## list of dictionaries checked whenever `Events.alert_level_changed` fires
## while that stage is active. Exceeding `max` fails the mission
## (`Events.mission_failed`):
## - `{"type": "alert_level", "max": <0-2>}`: the district alert level itself.
## - `{"type": "combat_count", "max": <n>}`: how many `enemy`-group actors are
##   simultaneously in `EnemyBase.State.COMBAT` — lets one guard be quietly
##   taken down without instantly failing a stealth heist, only failing once
##   the alarm has genuinely spread to several at once. Used by the Canton of
##   Resource heist.

var id: StringName
var title: String
var act: String
var chapter: String
var prerequisites: Array[StringName] = []
var stages: Array = []          # Array[Dictionary]
var fail_conditions: Array = [] # Array[Dictionary]
var rewards: Dictionary = {}
var journal: String = ""


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
	m.journal = d.get("journal", "")
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
