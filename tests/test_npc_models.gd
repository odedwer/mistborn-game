extends TestCase
## NPC visuals: NPCTalker shows real CharacterModels (with the capsule as a
## fallback), the interiors instantiate with them, Lady Valette wears Vin's
## gown in the ballroom, and the street crowd stays capped and pooled.

const INTERIORS := {
	"res://src/mission/interiors/clubs_shop_hub.tscn": 8,
	"res://src/mission/interiors/keep_venture_ballroom.tscn": 3,
	"res://src/mission/interiors/canton_office.tscn": 2,
}


func _talkers_in(root: Node) -> Array[NPCTalker]:
	var out: Array[NPCTalker] = []
	for n in root.find_children("*", "CharacterBody3D", true, false):
		if n is NPCTalker:
			out.append(n)
	return out


func test_npc_talker_resolves_models() -> void:
	assert_eq(NPCTalker.resolve_model_id(&"sazed", ""), &"sazed")
	assert_eq(NPCTalker.resolve_model_id(&"", "Ham"), &"ham", "guessed from the display name")
	assert_eq(NPCTalker.resolve_model_id(&"", "Lord Nobody"), &"", "unknown names keep the capsule")
	assert_eq(NPCTalker.resolve_model_id(&"no_such_model", "Kelsier"), &"", "a bad explicit id is not guessed over")
	var npc := NPCTalker.new()
	npc.display_name = "Breeze"
	add_child(npc)
	assert_true(npc.model is CharacterModel, "Breeze gets his model")
	assert_eq(npc.model.character_id, &"breeze")
	var label := npc.get_node_or_null("NameLabel") as Label3D
	assert_true(label != null and label.position.y > npc.model.get_model_height(), "name label above the head")
	var fallback := NPCTalker.new()
	fallback.display_name = "Lord Nobody"
	add_child(fallback)
	assert_true(fallback.model == null, "no model for unknown NPCs")
	assert_true(fallback.get_node_or_null("Model") is MeshInstance3D, "capsule fallback")


func test_interiors_instantiate_with_real_models() -> void:
	for path: String in INTERIORS:
		var scene := load(path) as PackedScene
		assert_true(scene != null, path)
		if scene == null:
			continue
		var room := scene.instantiate()
		add_child(room)
		var talkers := _talkers_in(room)
		assert_true(talkers.size() >= INTERIORS[path], "%s has %d NPCs" % [path, talkers.size()])
		for t in talkers:
			assert_true(t.model is CharacterModel, "%s: %s uses a real model" % [path, t.display_name])
			if t.model != null:
				assert_true(t.model.animation_tree != null and t.model.animation_tree.active,
					"%s: %s animates" % [path, t.display_name])
		room.queue_free()
		await get_tree().process_frame


func test_crew_hub_has_every_crew_member() -> void:
	var room := (load("res://src/mission/interiors/clubs_shop_hub.tscn") as PackedScene).instantiate()
	add_child(room)
	var ids := {}
	for t in _talkers_in(room):
		if t.model != null:
			ids[t.model.character_id] = true
	for id in [&"kelsier", &"dockson", &"breeze", &"ham", &"clubs", &"spook", &"sazed", &"marsh"]:
		assert_true(ids.has(id), "crew hub shows %s" % id)


func test_ballroom_guests_are_not_clones() -> void:
	var room := (load("res://src/mission/interiors/keep_venture_ballroom.tscn") as PackedScene).instantiate()
	add_child(room)
	var looks := {}
	var nobles := 0
	for t in _talkers_in(room):
		if t.model == null:
			continue
		assert_true(String(t.model.character_id).begins_with("noble"), "ballroom NPCs are nobles")
		nobles += 1
		looks["%s|%s|%s" % [t.model.character_id, t.model.garments, t.model.dye_colors]] = true
	assert_gt(nobles, 6, "a crowd at the ball")
	assert_eq(looks.size(), nobles, "every noble looks different")


func test_npc_talk_and_wander_animate() -> void:
	var npc := NPCTalker.new()
	npc.model_id = &"noble_woman_1"
	npc.wander_radius = 3.0
	npc.wander_speed = 1.0
	add_child(npc)
	# a floor so the wanderer can walk
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.2, 20)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.1
	add_child(floor_body)
	npc._wait = 0.0
	npc._pick_new_target()
	npc._target = npc.global_position + Vector3(2.5, 0, 0)
	await physics_frames(10)
	assert_gt(npc.get_real_velocity().length(), 0.3, "wandering NPC moves")
	var blend: float = npc.model.animation_tree.get(&"parameters/loco/ground/mix/blend_amount")
	assert_gt(blend, 0.5, "walk cycle blended in while wandering")
	var target := Node3D.new()
	add_child(target)
	target.global_position = npc.global_position + Vector3(0, 0, -3)
	var started := []
	npc.model.action_started.connect(func(a: StringName) -> void: started.append(a))
	npc.greet(target)
	assert_eq(started, [&"talk"], "talk gesture on interact")
	await physics_frames(40)
	assert_lt(absf(angle_difference(npc.model.rotation.y, PI)), 0.3, "turned to face the speaker")


func test_valette_wears_the_gown_in_the_ballroom() -> void:
	var player := (load("res://src/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await get_tree().process_frame
	assert_eq(player.model.scene_file_path, "res://assets/models/characters/vin.tscn", "Vin's usual clothes")
	var room := (load("res://src/mission/interiors/keep_venture_ballroom.tscn") as PackedScene).instantiate()
	add_child(room)
	remove_child(player)
	room.add_child(player)
	assert_eq(player.model.scene_file_path, "res://assets/models/characters/vin_gown.tscn", "gown inside the keep")
	assert_true(player.model.has_method(&"set_locomotion"), "gown model drives locomotion")
	room.remove_child(player)
	add_child(player)
	await get_tree().process_frame
	assert_eq(player.model.scene_file_path, "res://assets/models/characters/vin.tscn", "back in her mistcloak")
	room.queue_free()
	player.queue_free()


func test_crowd_populates_chunks_and_caps_visible_models() -> void:
	var crowd := CrowdSystem.new()
	crowd.plan = CityPlan.load_from_file()
	crowd.max_new_per_pass = 100
	add_child(crowd)
	var chunks := Node3D.new()
	add_child(chunks)
	var roots: Array[Node3D] = []
	var first := Vector2i(-9999, -9999)
	# populate chunks spiralling out from the middle of the city until there are plenty of agents
	var centre := crowd.plan.chunk_range().get_center()
	for d in 10:
		for dx in range(-d, d + 1):
			for dz in range(-d, d + 1):
				if maxi(absi(dx), absi(dz)) != d or crowd.agent_count() > 60:
					continue
				var root := Node3D.new()
				chunks.add_child(root)
				if crowd.populate_unit(root, centre + Vector2i(dx, dz)) > 0:
					roots.append(root)
					if first.x == -9999:
						first = centre + Vector2i(dx, dz)
	assert_gt(crowd.agent_count(), 30, "enough pedestrians to hit the cap (%d)" % crowd.agent_count())
	for ag in roots[0].get_children():
		assert_true(ag is CrowdSystem.CrowdAgent, "agents are parented to their chunk")
		var kind: StringName = ag.kind
		assert_true(kind in CrowdSystem.SKAA_KINDS or kind in CrowdSystem.OBLIGATOR_KINDS, "skaa or obligator")
	var rect := crowd.plan.chunk_rect(first)
	crowd.focus_override = Vector3(rect.get_center().x, 1.7, rect.get_center().y)
	crowd.view_radius = 400.0
	crowd.update_crowd(0.016)
	assert_eq(crowd.visible_count(), mini(crowd.max_visible, crowd.agent_count()), "nearest agents get models")
	assert_true(crowd.visible_count() <= 30, "capped at ~30 visible")
	assert_true(crowd.model_count() <= crowd.max_visible + 8, "models are pooled, not one per agent")
	# agents walk
	var ag0: CrowdSystem.CrowdAgent = roots[0].get_child(0)
	ag0.pause = 0.0
	var p0 := ag0.global_position
	for i in 30:
		crowd.update_crowd(0.05)
	assert_gt(ag0.global_position.distance_to(p0), 0.2, "pedestrians walk their lane")
	# unloading chunks frees agents and returns their models to the pool
	var created := crowd.model_count()
	chunks.queue_free()
	await get_tree().process_frame
	crowd._assign_t = 0.0
	crowd.update_crowd(0.016)
	assert_eq(crowd.agent_count(), 0, "agents stream out with their chunk")
	assert_eq(crowd.visible_count(), 0, "no models shown without agents")
	var shown := 0
	for c in crowd.get_children():
		if c is CharacterModel and c.visible:
			shown += 1
	assert_eq(shown, 0, "orphaned models are parked")
	assert_eq(crowd.model_count(), created, "and kept for reuse")


func test_crowd_lod_far_models_animate_manually() -> void:
	var crowd := CrowdSystem.new()
	crowd.plan = CityPlan.load_from_file()
	add_child(crowd)
	var root := Node3D.new()
	add_child(root)
	var near := crowd.spawn_agent(root, Vector3(0, 0, 0), Vector3(10, 0, 0), &"skaa_woman", 4)
	var far := crowd.spawn_agent(root, Vector3(0, 0, 50), Vector3(10, 0, 50), &"obligator", 6)
	crowd.focus_override = Vector3(5, 1.7, 0)
	crowd.update_crowd(0.016)
	crowd.update_crowd(0.016)
	assert_true(near.model != null and far.model != null, "both in view")
	if near.model == null or far.model == null:
		return
	assert_eq(near.model.animation_tree.callback_mode_process, AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE,
		"near: full-rate animation")
	assert_eq(far.model.animation_tree.callback_mode_process, AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,
		"far: throttled animation")
	var mi := far.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "far: no shadows")
