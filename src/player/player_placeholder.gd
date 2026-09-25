class_name PlayerPlaceholder
extends Node3D
## Stand-in player model (used until assets/models/characters/vin.tscn exists):
## a slim body, head, hood and a tasselled mistcloak built from primitive
## meshes. Faces +Z like imported glTF characters. Implements the character
## model API (`set_locomotion`, `play_action`) with simple procedural motion.

var _cloak: Node3D
var _body: Node3D
var _lean := 0.0
var _bob := 0.0
var _speed := 0.0
var _grounded := true
var _action_t := 0.0


## Builds the placeholder model.
static func build() -> PlayerPlaceholder:
	var root := PlayerPlaceholder.new()
	var cloth := _mat(Color(0.12, 0.12, 0.13), 0.9)
	var skin := _mat(Color(0.78, 0.62, 0.52), 0.7)
	var cloak_mat := _mat(Color(0.22, 0.23, 0.25), 1.0)
	cloak_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var accent := _mat(Color(0.55, 0.5, 0.42), 0.6)

	root._body = Node3D.new()
	root._body.name = "Body"
	root.add_child(root._body)

	var torso := CapsuleMesh.new()
	torso.radius = 0.2
	torso.height = 1.1
	_add_mesh(root._body, torso, cloth, Vector3(0, 0.95, 0))

	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.26
	_add_mesh(root._body, head, skin, Vector3(0, 1.62, 0.01))

	var hood := SphereMesh.new()
	hood.radius = 0.16
	hood.height = 0.3
	hood.is_hemisphere = true
	_add_mesh(root._body, hood, cloak_mat, Vector3(0, 1.64, -0.03))

	# Belt buckle on the front (+Z) so the facing is readable.
	var buckle := BoxMesh.new()
	buckle.size = Vector3(0.1, 0.06, 0.03)
	_add_mesh(root._body, buckle, accent, Vector3(0, 0.95, 0.2))

	for side in [-1.0, 1.0]:
		var leg := CapsuleMesh.new()
		leg.radius = 0.07
		leg.height = 0.8
		_add_mesh(root._body, leg, cloth, Vector3(0.1 * side, 0.4, 0))

	# Mistcloak: a flared open cone of tassels hanging from the shoulders.
	root._cloak = Node3D.new()
	root._cloak.name = "Cloak"
	root._cloak.position = Vector3(0, 1.45, -0.02)
	root._body.add_child(root._cloak)
	var tassels := 9
	for i in tassels:
		var a := lerpf(-PI * 0.8, PI * 0.8, float(i) / float(tassels - 1)) + PI
		var strip := BoxMesh.new()
		strip.size = Vector3(0.12, 1.25, 0.015)
		var mi := MeshInstance3D.new()
		mi.mesh = strip
		mi.material_override = cloak_mat
		var dir := Vector3(sin(a), 0, cos(a))
		mi.position = dir * 0.24 + Vector3(0, -0.6, 0)
		mi.rotation = Vector3(0, a, 0)
		mi.rotate_object_local(Vector3.RIGHT, -0.12)
		root._cloak.add_child(mi)
	return root


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Character model API.
func set_locomotion(speed: float, grounded: bool, _vertical_speed: float) -> void:
	_speed = speed
	_grounded = grounded


## Character model API: jump, land, throw, melee, hit, die, push, pull.
func play_action(action: StringName) -> void:
	_action_t = 0.25
	if action == &"die":
		_body.rotation.x = -PI * 0.5
		_body.position.y = 0.2


func _process(delta: float) -> void:
	if _body == null:
		return
	_action_t = maxf(_action_t - delta, 0.0)
	var lean_goal := clampf(_speed / 40.0, 0.0, 0.5) if not _grounded else clampf(_speed / 20.0, 0.0, 0.2)
	_lean = lerpf(_lean, lean_goal, 1.0 - exp(-6.0 * delta))
	if _body.rotation.x > -1.0:
		_body.rotation.x = _lean
	_bob += delta * _speed * 1.6
	if _grounded and _speed > 0.5:
		_body.position.y = absf(sin(_bob)) * 0.04
	# The cloak streams out behind with speed.
	_cloak.rotation.x = -clampf(_speed / 25.0, 0.0, 1.2) - _action_t
