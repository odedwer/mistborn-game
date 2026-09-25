extends TestCase
## Character models: scenes load, expose the CharacterModel API, carry the shared
## humanoid skeleton and the full animation set with correct loop flags.

const DIR := "res://assets/models/characters/"
const HEIGHTS := {
	"vin": [1.55, 1.75], "guard": [1.7, 1.9], "hazekiller": [1.65, 1.85],
	"thug": [2.0, 2.2], "coinshot": [1.7, 1.9], "inquisitor": [1.9, 2.1],
}
const REQUIRED_ANIMS: Array[StringName] = [
	&"idle", &"walk", &"run", &"sprint", &"crouch_idle", &"crouch_walk", &"jump", &"fall", &"land",
	&"throw", &"melee", &"attack", &"hit", &"die", &"block", &"alert", &"push", &"pull", &"drink"]


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
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			assert_true(mi.mesh.get_surface_count() <= 3, "%s <= 3 materials" % id)
			var tris := 0
			for s in mi.mesh.get_surface_count():
				tris += mi.mesh.surface_get_array_index_len(s) / 3
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
