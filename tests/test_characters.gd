extends TestCase
## Character models: scenes load, expose the CharacterModel API, carry the shared
## humanoid skeleton and the full animation set with correct loop flags; NPC
## variants (garments, dyes, scale) work and stay within the triangle budget.

const DIR := "res://assets/models/characters/"
const HEIGHTS := {
	"vin": [1.55, 1.75], "guard": [1.7, 1.9], "hazekiller": [1.65, 1.85],
	"thug": [2.0, 2.2], "coinshot": [1.7, 1.9], "inquisitor": [1.9, 2.1],
	# the crew
	"kelsier": [1.78, 1.95], "dockson": [1.7, 1.85], "breeze": [1.68, 1.82], "ham": [1.8, 1.96],
	"clubs": [1.58, 1.72], "spook": [1.7, 1.88], "sazed": [1.95, 2.1], "marsh": [1.78, 1.92],
	# Lady Valette, nobles (base models + presets; hats count towards the height)
	"vin_gown": [1.58, 1.74], "noble_man": [1.72, 1.9], "noble_woman": [1.58, 1.76],
	"noble_man_1": [1.75, 2.15], "noble_man_2": [1.75, 2.1], "noble_man_3": [1.68, 1.9],
	"noble_woman_1": [1.6, 1.85], "noble_woman_2": [1.6, 1.85], "noble_woman_3": [1.55, 1.85],
	# obligators and skaa
	"obligator": [1.74, 1.9], "obligator_2": [1.64, 1.8], "skaa_man": [1.66, 1.86], "skaa_woman": [1.54, 1.72],
}
const NPC_IDS: Array[String] = ["kelsier", "dockson", "breeze", "ham", "clubs", "spook", "sazed", "marsh",
	"vin_gown", "noble_man_1", "noble_woman_1", "obligator", "obligator_2", "skaa_man", "skaa_woman"]
const REQUIRED_ANIMS: Array[StringName] = [
	&"idle", &"walk", &"run", &"sprint", &"crouch_idle", &"crouch_walk", &"jump", &"fall", &"land",
	&"throw", &"melee", &"attack", &"hit", &"die", &"block", &"alert", &"push", &"pull", &"drink", &"talk"]


func _spawn(id: String) -> CharacterModel:
	var ps: PackedScene = load(DIR + id + ".tscn")
	assert_true(ps != null, "%s.tscn loads" % id)
	if ps == null:
		return null
	var m := ps.instantiate() as CharacterModel
	assert_true(m != null, "%s root is a CharacterModel" % id)
	if m != null:
		add_child(m)
	return m


func test_scenes_load_with_api() -> void:
	for id: String in HEIGHTS:
		var m := _spawn(id)
		if m == null:
			continue
		assert_true(m is Node3D, id)
		for method in ["set_locomotion", "play_action", "set_aim", "get_attachment", "set_crouching", "revive"]:
			assert_true(m.has_method(method), "%s has %s" % [id, method])
		assert_true(m.animation_tree != null and m.animation_tree.active, "%s has an active AnimationTree" % id)
		assert_true(m.skeleton != null, "%s has a skeleton" % id)
		assert_eq(m.find_children("*", "Skeleton3D", true, false).size(), 1, "%s: one skeleton" % id)


func test_animations_exist_and_loop_flags() -> void:
	for id: String in HEIGHTS:
		var m := _spawn(id)
		if m == null:
			continue
		for a in REQUIRED_ANIMS:
			assert_true(m.animation_player.has_animation(a), "%s has animation %s" % [id, a])
			if not m.animation_player.has_animation(a):
				continue
			var anim := m.animation_player.get_animation(a)
			var looping := anim.loop_mode != Animation.LOOP_NONE
			assert_eq(looping, a in CharacterModel.LOOPING_ANIMATIONS, "%s/%s loop flag" % [id, a])
			assert_gt(anim.length, 0.2, "%s/%s length" % [id, a])


func test_humanoid_bones_present() -> void:
	for id: String in HEIGHTS:
		var m := _spawn(id)
		if m == null:
			continue
		for b in CharacterModel.HUMANOID_BONES:
			assert_true(m.skeleton.find_bone(b) >= 0, "%s has bone %s" % [id, b])


func test_height_and_materials() -> void:
	for id: String in HEIGHTS:
		var m := _spawn(id)
		if m == null:
			continue
		var h := m.get_model_height()
		assert_gt(h, HEIGHTS[id][0], "%s height %.2f" % [id, h])
		assert_lt(h, HEIGHTS[id][1], "%s height %.2f" % [id, h])
		# budget: body + every optional garment together, <= 3 distinct materials
		var tris := 0
		var mats := {}
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				tris += mi.mesh.surface_get_array_index_len(s) / 3
				var mat := mi.mesh.surface_get_material(s)
				mats[mat.resource_path if mat != null else "none"] = true
		assert_true(mats.size() <= 3, "%s <= 3 materials (%s)" % [id, mats.keys()])
		assert_gt(tris, 2500, "%s tris %d" % [id, tris])
		assert_lt(tris, 8000, "%s tris %d" % [id, tris])


func test_models_face_plus_z() -> void:
	# The CharacterModel root faces +Z (player.gd / enemy_base.gd convention): toes are at +Z.
	var m := _spawn("guard")
	if m == null:
		return
	var foot := m.skeleton.global_transform * m.skeleton.get_bone_global_rest(m.skeleton.find_bone(&"RightToes")).origin
	var ankle := m.skeleton.global_transform * m.skeleton.get_bone_global_rest(m.skeleton.find_bone(&"RightFoot")).origin
	assert_gt(foot.z - ankle.z, 0.05, "toes point to +Z")


func test_actions_and_locomotion() -> void:
	for id: String in HEIGHTS:
		var m := _spawn(id)
		if m == null:
			continue
		m.set_locomotion(3.0, true, 0.0)
		m.set_aim(Vector3(1, 0.3, 1))
		await physics_frames(2)
		for a in CharacterModel.ACTIONS:
			if a == &"die":
				continue
			assert_true(m.play_action(a), "%s play_action %s" % [id, a])
			await physics_frames(1)
		assert_false(m.play_action(&"no_such_action"), "%s rejects unknown action" % id)
		m.set_locomotion(0.0, false, -3.0)
		m.set_crouching(true)
		m.set_locomotion(1.0, true, -8.0)
		await physics_frames(2)
		assert_true(m.play_action(&"die"), "%s die" % id)
		assert_true(m.is_dead(), "%s dead" % id)
		assert_false(m.play_action(&"attack"), "%s no actions while dead" % id)
		m.revive()
		assert_false(m.is_dead(), "%s revived" % id)


func test_attachments() -> void:
	var m := _spawn("guard")
	if m == null:
		return
	for n in [&"hand_r", &"hand_l", &"chest", &"head", &"lantern"]:
		var a := m.get_attachment(n)
		assert_true(a != null, "guard attachment %s" % n)
	assert_true(m.get_attachment(&"hand_r") == m.get_attachment(&"hand_r"), "attachments are cached")
	assert_true(m.get_attachment(&"nonsense") == null, "unknown attachment is null")
	await physics_frames(2)
	var hand := m.get_attachment(&"hand_r").global_position
	assert_gt(hand.y, 0.4, "right hand above the ground")
	assert_lt(hand.y, 1.4, "right hand below the shoulders")


func test_cloak_springs() -> void:
	var m := _spawn("vin")
	if m == null:
		return
	assert_true(m.spring_bones != null, "vin has cloak spring bones")
	assert_gt(m.spring_bones.setting_count, 8, "tassel chains")


func test_talk_is_an_upper_body_one_shot() -> void:
	assert_true(&"talk" in CharacterModel.ACTIONS, "talk is an action")
	assert_true(&"talk" in CharacterModel.UPPER_BODY_ACTIONS, "talk layers over walking")
	for id in NPC_IDS:
		var m := _spawn(id)
		if m == null:
			continue
		m.set_locomotion(1.3, true)
		assert_true(m.play_action(&"talk"), "%s talks" % id)
		assert_true(m.is_action_playing(), "%s talk playing" % id)


func test_npc_models_face_plus_z() -> void:
	for id in NPC_IDS:
		var m := _spawn(id)
		if m == null:
			continue
		var sk := m.skeleton
		var toes := sk.global_transform * sk.get_bone_global_rest(sk.find_bone(&"LeftToes")).origin
		var ankle := sk.global_transform * sk.get_bone_global_rest(sk.find_bone(&"LeftFoot")).origin
		assert_gt(toes.z - ankle.z, 0.05, "%s toes point to +Z" % id)


func test_garments_toggle_and_presets_differ() -> void:
	var m := _spawn("noble_man")
	if m == null:
		return
	var names := m.get_garment_names()
	for g in ["hat_top", "hat_bowler", "tails", "longcoat", "cape"]:
		assert_true(names.has(g), "noble_man has garment %s" % g)
	m.apply_variant(PackedStringArray(["hat_top"]), [Color.RED, Color.GOLD, Color.BLACK], 1.05)
	var shown := []
	for mi: MeshInstance3D in m.find_children("G_*", "MeshInstance3D", true, false):
		if mi.visible:
			shown.append(String(mi.name))
	assert_eq(shown, ["G_hat_top"], "only the chosen garment is shown")
	assert_almost(m.get_node("Model").scale.x, 1.05, 0.001, "body scale applied")
	var body := m.find_children("Noble_man", "MeshInstance3D", true, false)
	assert_eq(body.size(), 1, "body mesh")
	if body.size() == 1:
		assert_eq(body[0].get_instance_shader_parameter(&"dye_1"), Color.RED, "dye 1 set per instance")
	# presets share the base mesh but not the look
	var a := _spawn("noble_woman_1")
	var b := _spawn("noble_woman_2")
	if a != null and b != null:
		assert_true(a.garments != b.garments or a.dye_colors != b.dye_colors, "presets differ")


func test_randomize_variant_is_deterministic_and_varied() -> void:
	var looks := {}
	for i in 8:
		var m := _spawn("skaa_man")
		if m == null:
			return
		assert_true(m.randomize_variant(1000 + i), "skaa_man has a variant pool")
		var key := "%s|%s|%.3f" % [m.garments, m.dye_colors, m.body_scale]
		looks[key] = true
		var again := _spawn("skaa_man")
		again.randomize_variant(1000 + i)
		assert_eq(again.garments, m.garments, "same seed, same garments")
		assert_eq(again.dye_colors, m.dye_colors, "same seed, same dyes")
		var h := m.get_model_height()
		assert_gt(h, 1.5, "variant height %.2f" % h)
		assert_lt(h, 2.0, "variant height %.2f" % h)
	assert_gt(looks.size(), 5, "8 seeds give varied skaa")
	var k := _spawn("kelsier")
	if k != null:
		assert_false(k.randomize_variant(3), "unique characters have no pool")


func test_npc_props_and_cloaks() -> void:
	var k := _spawn("kelsier")
	if k != null:
		assert_true(k.spring_bones != null and k.spring_bones.setting_count > 8, "Kelsier's mistcloak tassels")
	for id in ["sazed", "breeze", "obligator"]:
		var m := _spawn(id)
		if m == null:
			continue
		assert_true(m.get_attachment(&"hand_r") != null, "%s hand socket" % id)
