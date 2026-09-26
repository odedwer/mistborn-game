extends TestCase
## Structural sanity for every new Act II interior scene: it loads, has an
## `"interior_spawn"` marker, and — the Act I lesson learned the hard way
## (docs/OPEN_WORLD.md's "a wall with no doorway") — an exit door
## (`res://src/world/interior_door.gd` with `is_exit = true`) actually exists
## somewhere in the tree, so the player is never sealed in. Full geometry
## checks are done visually (screenshots); this just catches "forgot the
## door" regressions cheaply and on every test run.

const INTERIORS: Array[String] = [
	"res://src/mission/interiors/keep_venture_dinner.tscn",
	"res://src/mission/interiors/canton_resource.tscn",
	"res://src/mission/interiors/street_confrontation.tscn",
	"res://src/mission/interiors/keep_tekiel_rooftop.tscn",
	"res://src/mission/interiors/pits_of_hathsin.tscn",
	"res://src/mission/interiors/inquisitor_chase.tscn",
]


func _find_exit_door(root: Node) -> Node:
	if root.get_script() != null and root.get_script().resource_path == "res://src/world/interior_door.gd" and bool(root.get("is_exit")):
		return root
	for c in root.get_children():
		var found := _find_exit_door(c)
		if found != null:
			return found
	return null


func _find_in_group(root: Node, group: StringName) -> Node:
	if root.is_in_group(group):
		return root
	for c in root.get_children():
		var found := _find_in_group(c, group)
		if found != null:
			return found
	return null


func test_every_act2_interior_loads_with_spawn_and_exit() -> void:
	for path in INTERIORS:
		assert_true(ResourceLoader.exists(path), "%s missing" % path)
		var scene: PackedScene = load(path)
		var inst := scene.instantiate()
		add_child(inst)
		assert_true(_find_in_group(inst, &"interior_spawn") != null, "%s: no interior_spawn marker" % path)
		assert_true(_find_exit_door(inst) != null, "%s: no exit door — the player would be sealed in" % path)
		inst.queue_free()


## The Canton of Resource and the Pits both connect two room shapes; every
## `objective_point` marker referenced by their missions must actually exist
## in the scene (a stale marker id would silently soft-lock the objective).
func test_canton_and_pits_markers_match_their_missions() -> void:
	var expectations := {
		"res://src/mission/interiors/canton_resource.tscn": ["canton_ledger", "canton_exit"],
		"res://src/mission/interiors/pits_of_hathsin.tscn": ["pits_ledge_1", "pits_ledge_2", "pits_ledge_3", "pits_geode", "pits_escape"],
		"res://src/mission/interiors/keep_tekiel_rooftop.tscn": ["tekiel_gate", "tekiel_exit"],
		"res://src/mission/interiors/inquisitor_chase.tscn": ["chase_checkpoint_1", "chase_checkpoint_2", "chase_checkpoint_3", "chase_arena", "chase_exit"],
		"res://src/mission/interiors/keep_venture_dinner.tscn": ["dinner_eavesdrop", "dinner_pickpocket"],
		"res://src/mission/interiors/street_confrontation.tscn": ["street_recruit"],
	}
	for path: String in expectations.keys():
		var scene: PackedScene = load(path)
		var inst := scene.instantiate()
		add_child(inst)
		var ids := {}
		_collect_objective_ids(inst, ids)
		for expected: String in expectations[path]:
			assert_true(ids.has(expected), "%s: missing objective_point '%s'" % [path, expected])
		inst.queue_free()


func _collect_objective_ids(root: Node, out: Dictionary) -> void:
	if root.is_in_group(&"objective_point"):
		out[str(root.get_meta("objective_id", ""))] = true
	for c in root.get_children():
		_collect_objective_ids(c, out)
