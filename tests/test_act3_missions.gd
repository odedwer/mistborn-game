extends TestCase
## Act III ("The Final Empire" finale): chain order, JSON validation against
## the scenes/dialogues/cutscenes they reference, an automated objective run
## per mission, the Lord Ruler's phase logic, the credits -> post-game
## transition, backdrop presence on the open-air scenes, interior exits, and
## the Seeker-style Inquisitor used in the Kredik Shaw duel.

const ACT3_MISSIONS: Array[StringName] = [
	&"the_army_in_the_caves", &"fountain_square", &"the_survivors_legacy",
	&"into_kredik_shaw", &"the_pits_beneath_the_palace", &"the_lord_ruler",
]
const EARLIER: Array[StringName] = [
	&"survivors_offer", &"the_crew", &"mistwalk_to_keep_venture",
	&"lessons_in_the_mists", &"lady_valette", &"dinner_at_keep_venture",
	&"the_canton_of_resource", &"soothing_the_masses", &"house_war",
	&"the_pits_of_hathsin", &"the_inquisitors_shadow",
]
const ACT3_INTERIORS: Array[String] = [
	"res://src/mission/interiors/rebel_caves.tscn",
	"res://src/mission/interiors/battlefield.tscn",
	"res://src/mission/interiors/fountain_square.tscn",
	"res://src/mission/interiors/crew_regroup.tscn",
	"res://src/mission/interiors/keep_venture_library.tscn",
	"res://src/mission/interiors/kredik_shaw.tscn",
	"res://src/mission/interiors/palace_pits.tscn",
	"res://src/mission/interiors/throne_room.tscn",
]
## Open-air mission scenes that must show a sky + skyline, not a black void.
const BACKDROP_SCENES: Array[String] = [
	"res://src/mission/interiors/battlefield.tscn",
	"res://src/mission/interiors/fountain_square.tscn",
	"res://src/mission/interiors/kredik_shaw.tscn",
	"res://src/mission/interiors/throne_room.tscn",
	"res://src/mission/interiors/inquisitor_chase.tscn",
	"res://src/mission/interiors/keep_tekiel_rooftop.tscn",
	"res://src/mission/interiors/street_confrontation.tscn",
]
const KNOWN_OBJECTIVE_TYPES := [
	"reach_marker", "escape", "interact", "defeat", "defeat_in_duel", "use_metal",
	"flare_metal", "collect", "cutscene_hint", "dialogue", "reach_speed",
	"chain_pushes", "flag_count", "crowd_mood", "push_target", "survive", "cutscene",
]
const KNOWN_ACTIONS := [
	"spawn_enemy", "hint", "mission_complete", "set_allowed_metals", "start_dialogue",
	"start_cutscene", "enter_interior", "exit_interior", "set_flag", "switch_interior",
	"call_group", "drain_metals", "grant_metals", "roll_credits",
]


func after_each() -> void:
	CutsceneSystem.skip()
	get_tree().paused = false
	for c in get_tree().get_nodes_in_group(&"credits_screen"):
		c.queue_free()


func _director_for(mission_id: StringName) -> MissionDirector:
	GameState.reset_run()
	GameState.mission_id = mission_id
	var d := MissionDirector.new()
	add_child(d)
	return d


func _instance(path: String) -> Node:
	var inst: Node = (load(path) as PackedScene).instantiate()
	add_child(inst)
	return inst


func _find_in_group(root: Node, group: StringName) -> Node:
	if root.is_in_group(group):
		return root
	for c in root.get_children():
		var f := _find_in_group(c, group)
		if f != null:
			return f
	return null


func _collect_objective_ids(root: Node, out: Dictionary) -> void:
	if root.is_in_group(&"objective_point"):
		out[str(root.get_meta("objective_id", ""))] = true
	for c in root.get_children():
		_collect_objective_ids(c, out)


# --- Chain ------------------------------------------------------------------------

func test_act3_chain_follows_act2_in_order_then_story_ends() -> void:
	var story := StoryManager.new()
	story.refresh()
	var completed: Array[StringName] = EARLIER.duplicate()
	for expected in ACT3_MISSIONS:
		var next := story.next_story_mission(completed)
		assert_true(next != null, "no next mission after %s" % str(completed.back()))
		if next == null:
			return
		assert_eq(next.id, expected)
		assert_eq(next.act, "3", "%s should be act 3" % expected)
		completed.append(expected)
	assert_true(story.next_story_mission(completed) == null, "nothing should follow the_lord_ruler")


## A save made on the mission-complete screen still names the finished
## mission; the director must move on to the next one, not replay it.
func test_director_advances_past_a_completed_mission() -> void:
	GameState.reset_run()
	GameState.completed_missions.append_array(EARLIER)
	GameState.completed_missions.append(&"the_army_in_the_caves")
	GameState.mission_id = &"the_army_in_the_caves"
	GameState.mission_stage = 3
	var d := MissionDirector.new()
	add_child(d)
	assert_eq(d.mission.id, &"fountain_square")
	assert_eq(d.stage_index, 0)
	d.queue_free()


# --- JSON validation -------------------------------------------------------------------

func test_act3_json_is_valid_and_references_resolve() -> void:
	var story := StoryManager.new()
	story.refresh()
	for id in ACT3_MISSIONS:
		var m := story.get_mission(id)
		assert_true(m != null, "%s did not load" % id)
		if m == null:
			continue
		assert_true(m.journal.length() > 40, "%s needs a journal entry" % id)
		var seen_ids := {}
		for stage: Dictionary in m.stages:
			if stage.has("interior"):
				assert_true(ResourceLoader.exists(String(stage["interior"])), "%s: stage interior %s missing" % [id, stage["interior"]])
			for action: Dictionary in stage.get("on_enter", []):
				_check_action(id, action)
			for obj: Dictionary in stage.get("objectives", []):
				var oid := String(obj.get("id", ""))
				assert_false(seen_ids.has(oid), "%s: duplicate objective id %s" % [id, oid])
				seen_ids[oid] = true
				var t := String(obj.get("type", ""))
				assert_true(KNOWN_OBJECTIVE_TYPES.has(t), "%s/%s: unknown objective type '%s'" % [id, oid, t])
				if t == "dialogue":
					assert_false(DialogueSystem.load_dialogue(StringName(obj.get("dialogue_id", ""))).is_empty(), "%s/%s: missing dialogue" % [id, oid])
				if t == "cutscene":
					assert_false(CutsceneSystem.load_shots(StringName(obj.get("cutscene_id", ""))).is_empty(), "%s/%s: missing cutscene" % [id, oid])
				for action: Dictionary in obj.get("on_complete", []):
					_check_action(id, action)


func _check_action(id: StringName, action: Dictionary) -> void:
	var a := String(action.get("action", ""))
	assert_true(KNOWN_ACTIONS.has(a), "%s: unknown action '%s'" % [id, a])
	match a:
		"enter_interior", "switch_interior":
			assert_true(ResourceLoader.exists(String(action.get("scene", ""))), "%s: missing scene %s" % [id, action.get("scene")])
		"start_dialogue":
			assert_false(DialogueSystem.load_dialogue(StringName(action.get("dialogue_id", ""))).is_empty(), "%s: missing dialogue %s" % [id, action.get("dialogue_id")])
		"start_cutscene":
			assert_false(CutsceneSystem.load_shots(StringName(action.get("cutscene_id", ""))).is_empty(), "%s: missing cutscene %s" % [id, action.get("cutscene_id")])


## Every marker a mission's objectives point at exists in one of the scenes
## that mission enters (a stale id would silently soft-lock the objective).
func test_act3_markers_exist_in_their_scenes() -> void:
	var story := StoryManager.new()
	story.refresh()
	for id in ACT3_MISSIONS:
		var m := story.get_mission(id)
		var scenes: Array[String] = []
		for stage: Dictionary in m.stages:
			if stage.has("interior") and not scenes.has(String(stage["interior"])):
				scenes.append(String(stage["interior"]))
			var actions: Array = stage.get("on_enter", []).duplicate()
			for obj: Dictionary in stage.get("objectives", []):
				actions.append_array(obj.get("on_complete", []))
			for action: Dictionary in actions:
				if String(action.get("action", "")) in ["enter_interior", "switch_interior"] and not scenes.has(String(action["scene"])):
					scenes.append(String(action["scene"]))
		var ids := {}
		var roots: Array[Node] = []
		for path in scenes:
			var inst := _instance(path)
			roots.append(inst)
		await get_tree().process_frame
		for r in roots:
			_collect_objective_ids(r, ids)
		for stage: Dictionary in m.stages:
			for obj: Dictionary in stage.get("objectives", []):
				if String(obj.get("type", "")) in ["reach_marker", "escape", "interact"]:
					assert_true(ids.has(String(obj.get("marker_id", ""))), "%s: marker '%s' not in %s" % [id, obj.get("marker_id"), str(scenes)])
		for r in roots:
			r.queue_free()
		await get_tree().process_frame


# --- Automated objective runs ---------------------------------------------------------

func test_each_act3_mission_completes_end_to_end() -> void:
	for mission_id in ACT3_MISSIONS:
		var d := _director_for(mission_id)
		assert_true(d.mission != null, "%s failed to load" % mission_id)
		if d.mission == null:
			continue
		var finished: Array = [false]
		var cb := func(id: StringName) -> void:
			if id == mission_id:
				finished[0] = true
		Events.mission_completed.connect(cb)
		for i in d.mission.stages.size():
			for obj: Dictionary in d.mission.stages[i].get("objectives", []):
				d.complete_objective(obj)
		# The finale hands over to the credits; skip them.
		for c in get_tree().get_nodes_in_group(&"credits_screen"):
			(c as CreditsScreen).finish()
		CutsceneSystem.skip()
		await get_tree().process_frame
		assert_true(finished[0], "%s: mission_completed never fired" % mission_id)
		assert_true(GameState.completed_missions.has(mission_id), "%s: not recorded" % mission_id)
		Events.mission_completed.disconnect(cb)
		d.queue_free()
		DialogueSystem._finish()
		get_tree().paused = false


# --- The Lord Ruler -------------------------------------------------------------------

func _lord_ruler() -> LordRuler:
	var lr := (load("res://src/enemies/lord_ruler.tscn") as PackedScene).instantiate() as LordRuler
	add_child(lr)
	return lr


func test_lord_ruler_bracers_only_come_off_when_staggered() -> void:
	GameState.reset_run()
	var lr := _lord_ruler()
	assert_eq(lr.bracers_remaining(), 2)
	lr.set_phase(LordRuler.Phase.SURVIVE)
	assert_false(lr.try_pull_bracer(LordRuler.BRACER_LEFT), "not in the bracers phase yet")
	lr.set_phase(LordRuler.Phase.BRACERS)
	assert_false(lr.staggered)
	assert_true(lr.bracer_metals[0].shielded, "bracers are shielded while he stands firm")
	assert_false(lr.try_pull_bracer(LordRuler.BRACER_LEFT), "an Iron Pull can't take them unless he's staggered")
	lr.stagger()
	assert_true(lr.staggered)
	assert_false(lr.bracer_metals[0].shielded, "staggering exposes the bracers")
	assert_true(lr.try_pull_bracer(LordRuler.BRACER_LEFT))
	assert_true(GameState.has_dialogue_flag(&"lr_bracer_left"))
	assert_eq(lr.bracers_remaining(), 1)
	assert_false(lr.try_pull_bracer(LordRuler.BRACER_LEFT), "already gone")
	assert_eq(lr.phase, LordRuler.Phase.BRACERS)
	lr.stagger()
	assert_true(lr.try_pull_bracer(LordRuler.BRACER_RIGHT))
	assert_eq(lr.phase, LordRuler.Phase.MORTAL, "both bracers gone -> mortal")


## An Iron Pull reported on a bracer's Metallic (the real input path) rips it
## off only while staggered.
func test_lord_ruler_iron_pull_event_path() -> void:
	GameState.reset_run()
	var lr := _lord_ruler()
	lr.set_phase(LordRuler.Phase.BRACERS)
	var m := lr.bracer_metals[1]
	Events.allomantic_line_used.emit(Node.new(), m, Metal.Type.IRON, 1.0)
	assert_eq(lr.bracers_remaining(), 2, "no pull while he stands firm")
	lr.stagger()
	Events.allomantic_line_used.emit(Node.new(), m, Metal.Type.STEEL, 1.0)
	assert_eq(lr.bracers_remaining(), 2, "a steel Push doesn't tear a bracer off")
	Events.allomantic_line_used.emit(Node.new(), m, Metal.Type.IRON, 1.0)
	assert_eq(lr.bracers_remaining(), 1)


func test_lord_ruler_cannot_die_until_mortal_and_resists_coins() -> void:
	var lr := _lord_ruler()
	lr.set_phase(LordRuler.Phase.SURVIVE)
	var h := lr.health
	var dealt := h.take_damage(100.0, null, &"coin")
	assert_almost(dealt, 100.0 * lr.coin_resist, 0.01, "coins barely scratch him")
	h.take_damage(999999.0, null, &"blade")
	assert_false(h.dead, "he can't die while he still has his bracers")
	assert_true(h.current >= 1.0)
	assert_gt(h.regen_per_second, 0.0, "he regenerates before he's mortal")
	lr.set_phase(LordRuler.Phase.MORTAL)
	assert_eq(h.regen_per_second, 0.0)
	h.take_damage(999999.0, null, &"blade")
	assert_true(h.dead, "mortal at last")


func test_lord_ruler_dormant_is_untouchable() -> void:
	var lr := _lord_ruler()
	assert_eq(lr.phase, LordRuler.Phase.DORMANT)
	assert_eq(lr.health.take_damage(50.0, null, &"blade"), 0.0)


func test_metal_exposure_scales_with_reserves_and_coins() -> void:
	var full := {}
	for m in Metal.Type.values():
		full[m] = Metal.MAX_RESERVE
	assert_almost(LordRuler.metal_exposure(full, 200), 1.0, 0.001)
	assert_almost(LordRuler.metal_exposure({}, 0), 0.0, 0.001)
	var half := {}
	for m in Metal.Type.values():
		half[m] = Metal.MAX_RESERVE * 0.5
	var e_half := LordRuler.metal_exposure(half, 0)
	assert_gt(e_half, 0.2)
	assert_lt(e_half, LordRuler.metal_exposure(full, 0))


func test_lord_ruler_learning_phase_logic() -> void:
	var lr := _lord_ruler()
	assert_false(lr.has_learned(0.7, 0.75, 1.0), "still full of metal")
	assert_true(lr.has_learned(0.2, 0.75, 1.0), "drained well below the first push")
	assert_true(lr.has_learned(0.02, -1.0, 1.0), "empty from the start")
	assert_true(lr.has_learned(0.7, 0.75, lr.learn_timeout + 1.0), "outlasted him")


func test_lord_ruler_burst_damage_staggers_in_bracers_phase() -> void:
	var lr := _lord_ruler()
	lr.set_phase(LordRuler.Phase.BRACERS)
	lr.health.take_damage(lr.stagger_burst * 1.2, null, &"blade")
	assert_true(lr.staggered, "a heavy burst of blows staggers him")


# --- Credits / post-game ------------------------------------------------------------------

func test_credits_then_post_game_free_roam() -> void:
	var d := _director_for(&"the_lord_ruler")
	GameState.completed_missions.append_array(EARLIER)
	var post: Array = [&""]
	var cb := func(id: StringName) -> void: post[0] = id
	Events.post_game_started.connect(cb)
	d._roll_credits()
	var credits := get_tree().get_first_node_in_group(&"credits_screen") as CreditsScreen
	assert_true(credits != null, "credits should be showing")
	assert_true(get_tree().paused, "credits pause the game")
	assert_true(GameState.post_game)
	credits.finish()
	await get_tree().process_frame
	assert_false(get_tree().paused, "free roam resumes after the credits")
	assert_eq(post[0], &"the_lord_ruler")
	assert_true(GameState.completed_missions.has(&"the_lord_ruler"))
	assert_true(d.mission == null, "no story mission runs in post-game")
	Events.post_game_started.disconnect(cb)
	d.queue_free()
	# A fresh session (e.g. loading the post-game save) stays in free roam.
	var d2 := MissionDirector.new()
	add_child(d2)
	assert_true(d2.mission == null)
	assert_false(d2.start_next_mission())
	d2.queue_free()
	# The save round-trips the flag.
	var saved := GameState.to_dict()
	GameState.post_game = false
	GameState.from_dict(saved)
	assert_true(GameState.post_game)
	GameState.reset_run()
	assert_false(GameState.post_game)


func test_credits_carry_disclaimer_tools_and_licenses() -> void:
	var text := " ".join(CreditsScreen.all_text())
	for needle: String in ["fan", "non-commercial", "Brandon Sanderson", "Dragonsteel", "not affiliated", "Godot", "Jolt", "Blender", "CC0", "Open Font License"]:
		assert_true(text.contains(needle), "credits should mention '%s'" % needle)


# --- Scenes -----------------------------------------------------------------------------

func test_open_air_scenes_have_a_backdrop() -> void:
	for path in BACKDROP_SCENES:
		var inst := _instance(path)
		await get_tree().process_frame
		var bd := _find_in_group(inst, &"mission_backdrop") as MissionBackdrop
		assert_true(bd != null, "%s: no MissionBackdrop" % path)
		if bd != null:
			assert_eq(bd.environment.background_mode, Environment.BG_SKY, "%s: should render the night sky" % path)
			assert_gt(float(bd.skyline_job_count()), 1.0, "%s: no skyline silhouette" % path)
		# Exactly one WorldEnvironment (the old flat-black one is gone).
		var envs := inst.find_children("*", "WorldEnvironment", true, false)
		assert_eq(envs.size(), 1, "%s: expected one WorldEnvironment" % path)
		inst.queue_free()
		await get_tree().process_frame


func test_every_act3_interior_has_spawn_and_exit() -> void:
	for path in ACT3_INTERIORS:
		var inst := _instance(path)
		await get_tree().process_frame
		assert_true(_find_in_group(inst, &"interior_spawn") != null, "%s: no interior_spawn" % path)
		var door: Node = null
		for n in inst.find_children("*", "StaticBody3D", true, false):
			if n.get_script() != null and n.get_script().resource_path == "res://src/world/interior_door.gd" and bool(n.get("is_exit")):
				door = n
		assert_true(door != null, "%s: no exit door" % path)
		inst.queue_free()
		await get_tree().process_frame


## The chase tuning: the Inquisitor now starts well out of sight behind the
## player and holds still for a beat.
func test_inquisitor_chase_starts_far_behind() -> void:
	var inst := _instance("res://src/mission/interiors/inquisitor_chase.tscn")
	await get_tree().process_frame
	var inq := inst.get_node("Inquisitor") as Node3D
	var spawn := _find_in_group(inst, &"interior_spawn") as Node3D
	assert_gt(spawn.global_position.distance_to(inq.global_position), 30.0)
	assert_eq(inq.process_mode, Node.PROCESS_MODE_DISABLED, "it waits before giving chase")
	inst.queue_free()


func test_duel_inquisitor_hunts_by_bronze() -> void:
	var inq := (load("res://src/enemies/inquisitor.tscn") as PackedScene).instantiate()
	inq.set("senses_pulses", true)
	add_child(inq)
	var ally := Node3D.new()
	ally.add_to_group(&"enemy")
	add_child(ally)
	Events.allomantic_pulse.emit(ally, Metal.Type.STEEL, inq.global_position + Vector3(3, 0, 0))
	assert_true(inq.target != ally, "ignores its own kind's pulses")
	var prey := Node3D.new()
	add_child(prey)
	prey.global_position = inq.global_position + Vector3(20, 0, 0)
	Events.allomantic_pulse.emit(prey, Metal.Type.STEEL, prey.global_position)
	assert_true(inq.target == prey, "a pulse gives away the burner")
	assert_eq(inq.state, EnemyBase.State.COMBAT)
	assert_almost(inq.time_since_pulse(), 0.0)


# --- Director plumbing -----------------------------------------------------------------

## Markers that only appear once an interior finishes loading are retried
## instead of silently never getting a trigger.
func test_objective_trigger_waits_for_its_marker() -> void:
	var d := _director_for(&"the_army_in_the_caves")
	var obj := {"id": "late_marker_obj", "type": "reach_marker", "marker_group": "objective_point", "marker_id": "late_marker"}
	d._active_objectives[&"late_marker_obj"] = obj
	var before := d._triggers.size()
	d._spawn_trigger_for(obj)
	assert_eq(d._triggers.size(), before, "no marker yet, no trigger")
	var m := Marker3D.new()
	m.add_to_group(&"objective_point")
	m.set_meta("objective_id", "late_marker")
	add_child(m)
	d._retry_unresolved_triggers()
	assert_eq(d._triggers.size(), before + 1, "trigger appears once the marker exists")
	d.queue_free()


func test_cutscene_pan_interpolates_between_ends() -> void:
	var shot := {"pos": [0, 0, 0], "look_at": [0, 0, -10], "to_pos": [10, 0, 0], "to_look_at": [10, 0, -10]}
	var start: Array = CutsceneSystem.pan_sample(shot, 0.0)
	var mid: Array = CutsceneSystem.pan_sample(shot, 0.5)
	var end: Array = CutsceneSystem.pan_sample(shot, 1.0)
	assert_eq(start[0], Vector3.ZERO)
	assert_almost((mid[0] as Vector3).x, 5.0, 0.01)
	assert_eq(end[0], Vector3(10, 0, 0))
	assert_eq(end[1], Vector3(10, 0, -10))
	# Every Act III cutscene actually pans somewhere.
	for id: StringName in [&"kelsier_last_stand", &"vin_captured", &"lord_ruler_falls"]:
		var pans := 0
		for s: Dictionary in CutsceneSystem.load_shots(id):
			if s.has("to_pos") or s.has("to_look_at"):
				pans += 1
		assert_gt(float(pans), 1.0, "%s should use camera pans" % id)


# --- Journal ---------------------------------------------------------------------------

func test_journal_shows_act3_entries() -> void:
	var script: GDScript = load("res://src/ui/pause_menu.gd")
	var story := StoryManager.new()
	story.refresh()
	var done: Array[StringName] = []
	done.append_array(EARLIER)
	done.append_array(ACT3_MISSIONS)
	var entries: Array = script.call("journal_entries", story, done)
	assert_eq(entries.size(), done.size())
	var act3 := 0
	for e: Dictionary in entries:
		if e["act"] == "3":
			act3 += 1
			assert_true(String(e["text"]).length() > 40, "%s: Act III journal entry missing" % e["id"])
			assert_true(String(e["title"]).begins_with("Act 3"), "journal titles name the act")
	assert_eq(act3, ACT3_MISSIONS.size())
