class_name WorldPickup
extends Area3D
## Collectible spawned at `pickup_spawn` markers (vial, coins, atium,
## duralumin, health). Calls `add_pickup(kind, amount)` on the player body.

## Emitted when the player picks this up (before it frees itself).
signal collected(pickup: WorldPickup)

const AMOUNTS := {&"coins": 10.0, &"vial": 1.0, &"atium": 25.0, &"duralumin": 100.0, &"health": 40.0}
## Accent colour per kind: drives the liquid/metal/glow tint of the built mesh
## and the pickup's soft light, even though each kind now has its own shape.
const COLORS := {
	&"coins": Color(0.85, 0.72, 0.35), &"vial": Color(0.55, 0.7, 1.0), &"atium": Color(1.0, 0.85, 0.55),
	&"duralumin": Color(0.8, 0.85, 1.0), &"health": Color(1.0, 0.35, 0.3),
}
const COIN_ALBEDO := "res://assets/textures/coin_face_albedo.png"
const COIN_NORMAL := "res://assets/textures/coin_face_normal.png"

@export var pickup_kind: StringName = &"vial":
	set(v):
		pickup_kind = v
		_refresh()
@export var amount := -1.0

## Container that _process() spins/bobs; holds the kind-specific sub-meshes.
var _mesh: Node3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	collision_layer = 1 << 5
	collision_mask = 2
	monitorable = false
	add_to_group(&"pickup")
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.9
	cs.shape = sph
	cs.position = Vector3(0, 0.5, 0)
	add_child(cs)
	_mesh = Node3D.new()
	_mesh.position = Vector3(0, 0.5, 0)
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.omni_range = 2.0
	# Subtle: reads as a glint at pickup range without tripping bloom.
	_light.light_energy = 0.3
	_light.position = Vector3(0, 0.7, 0)
	add_child(_light)
	_refresh()
	body_entered.connect(_on_body_entered)


func _glass_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.1
	mat.roughness = 0.05
	mat.rim_enabled = true
	mat.rim = 0.6
	return mat


func _liquid_material(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 0.55
	# "Metal-flake" liquid: high metallic with a fine flake-like specular pop.
	mat.metallic = 0.75
	mat.metallic_specular = 0.9
	mat.roughness = 0.22
	mat.anisotropy_enabled = true
	mat.anisotropy = 0.4
	return mat


## Small glass vial with a metal-flake liquid inside — used for vial and
## duralumin (tinted by `c`).
func _build_vial(c: Color) -> void:
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.055
	body_mesh.bottom_radius = 0.065
	body_mesh.height = 0.24
	body.mesh = body_mesh
	body.material_override = _glass_material(Color(0.75, 0.82, 0.85))
	body.position = Vector3(0, 0.12, 0)
	_mesh.add_child(body)

	var neck := MeshInstance3D.new()
	var neck_mesh := CylinderMesh.new()
	neck_mesh.top_radius = 0.022
	neck_mesh.bottom_radius = 0.03
	neck_mesh.height = 0.08
	neck.mesh = neck_mesh
	neck.material_override = body.material_override
	neck.position = Vector3(0, 0.28, 0)
	_mesh.add_child(neck)

	var cork := MeshInstance3D.new()
	var cork_mesh := CylinderMesh.new()
	cork_mesh.top_radius = 0.024
	cork_mesh.bottom_radius = 0.024
	cork_mesh.height = 0.035
	cork.mesh = cork_mesh
	var cork_mat := StandardMaterial3D.new()
	cork_mat.albedo_color = Color(0.35, 0.25, 0.15)
	cork_mat.roughness = 0.9
	cork.material_override = cork_mat
	cork.position = Vector3(0, 0.34, 0)
	_mesh.add_child(cork)

	var liquid := MeshInstance3D.new()
	var liquid_mesh := CylinderMesh.new()
	liquid_mesh.top_radius = 0.045
	liquid_mesh.bottom_radius = 0.055
	liquid_mesh.height = 0.16
	liquid.mesh = liquid_mesh
	liquid.material_override = _liquid_material(c)
	liquid.position = Vector3(0, 0.09, 0)
	_mesh.add_child(liquid)


## A small drawstring coin pouch with a loose stack of coins beside it.
func _build_coins() -> void:
	var pouch := MeshInstance3D.new()
	var pouch_mesh := SphereMesh.new()
	pouch_mesh.radius = 0.11
	pouch_mesh.height = 0.18
	pouch_mesh.radial_segments = 12
	pouch_mesh.rings = 8
	pouch.mesh = pouch_mesh
	pouch.scale = Vector3(1.0, 0.85, 1.0)
	var pouch_mat := StandardMaterial3D.new()
	pouch_mat.albedo_color = Color(0.32, 0.22, 0.12)
	pouch_mat.roughness = 0.85
	pouch.material_override = pouch_mat
	pouch.position = Vector3(-0.05, 0.08, 0)
	_mesh.add_child(pouch)

	var tie := MeshInstance3D.new()
	var tie_mesh := TorusMesh.new()
	tie_mesh.inner_radius = 0.02
	tie_mesh.outer_radius = 0.06
	tie.mesh = tie_mesh
	tie.rotation_degrees = Vector3(90, 0, 0)
	tie.material_override = pouch_mat
	tie.position = Vector3(-0.05, 0.16, 0)
	_mesh.add_child(tie)

	var coin_albedo := load(COIN_ALBEDO) if ResourceLoader.exists(COIN_ALBEDO) else null
	var coin_normal := load(COIN_NORMAL) if ResourceLoader.exists(COIN_NORMAL) else null
	var coin_mat := StandardMaterial3D.new()
	coin_mat.albedo_color = Color(0.9, 0.78, 0.4)
	if coin_albedo != null:
		coin_mat.albedo_texture = coin_albedo
	if coin_normal != null:
		coin_mat.normal_enabled = true
		coin_mat.normal_texture = coin_normal
	coin_mat.metallic = 0.95
	coin_mat.roughness = 0.3
	for i in 5:
		var coin := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.075
		cm.bottom_radius = 0.075
		cm.height = 0.018
		coin.mesh = cm
		coin.material_override = coin_mat
		coin.rotation_degrees = Vector3(90.0, 0.0, sin(float(i) * 1.7) * 12.0)
		coin.position = Vector3(0.06 + sin(float(i) * 2.1) * 0.015, 0.02 + float(i) * 0.02, cos(float(i) * 2.1) * 0.015)
		_mesh.add_child(coin)


## A small dense atium bead — a heavy, near-liquid-metal drop.
func _build_atium(c: Color) -> void:
	var bead := MeshInstance3D.new()
	var bead_mesh := SphereMesh.new()
	bead_mesh.radius = 0.075
	bead_mesh.height = 0.15
	bead_mesh.radial_segments = 16
	bead_mesh.rings = 10
	bead.mesh = bead_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.metallic = 1.0
	mat.roughness = 0.08
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 0.35
	bead.material_override = mat
	bead.position = Vector3(0, 0.1, 0)
	_mesh.add_child(bead)


## A small bandage/salve jar: a squat lidded pot with a cloth wrap.
func _build_health() -> void:
	var jar := MeshInstance3D.new()
	var jar_mesh := CylinderMesh.new()
	jar_mesh.top_radius = 0.09
	jar_mesh.bottom_radius = 0.095
	jar_mesh.height = 0.16
	jar.mesh = jar_mesh
	var jar_mat := StandardMaterial3D.new()
	jar_mat.albedo_color = Color(0.78, 0.74, 0.64)
	jar_mat.roughness = 0.6
	jar.material_override = jar_mat
	jar.position = Vector3(0, 0.08, 0)
	_mesh.add_child(jar)

	var lid := MeshInstance3D.new()
	var lid_mesh := CylinderMesh.new()
	lid_mesh.top_radius = 0.095
	lid_mesh.bottom_radius = 0.095
	lid_mesh.height = 0.03
	lid.mesh = lid_mesh
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.5, 0.42, 0.3)
	lid_mat.roughness = 0.7
	lid.material_override = lid_mat
	lid.position = Vector3(0, 0.175, 0)
	_mesh.add_child(lid)

	# A red cross on a strip of bandage cloth wrapped around the jar.
	var cross_mat := StandardMaterial3D.new()
	cross_mat.albedo_color = Color(0.8, 0.15, 0.12)
	cross_mat.emission_enabled = true
	cross_mat.emission = Color(0.8, 0.15, 0.12)
	cross_mat.emission_energy_multiplier = 0.3
	cross_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bar_v := MeshInstance3D.new()
	var bv_mesh := BoxMesh.new()
	bv_mesh.size = Vector3(0.03, 0.09, 0.01)
	bar_v.mesh = bv_mesh
	bar_v.material_override = cross_mat
	bar_v.position = Vector3(0, 0.09, 0.096)
	_mesh.add_child(bar_v)
	var bar_h := MeshInstance3D.new()
	var bh_mesh := BoxMesh.new()
	bh_mesh.size = Vector3(0.09, 0.03, 0.01)
	bar_h.mesh = bh_mesh
	bar_h.material_override = cross_mat
	bar_h.position = Vector3(0, 0.09, 0.096)
	_mesh.add_child(bar_h)


func _refresh() -> void:
	if _mesh == null:
		return
	for c in _mesh.get_children():
		c.queue_free()
	var c: Color = COLORS.get(pickup_kind, Color.WHITE)
	match pickup_kind:
		&"coins":
			_build_coins()
		&"atium":
			_build_atium(c)
		&"health":
			_build_health()
		&"vial", &"duralumin", _:
			_build_vial(c)
	_light.light_color = c


func _process(delta: float) -> void:
	_t += delta
	if _mesh != null:
		_mesh.rotation.y = _t * 1.5
		_mesh.position.y = 0.5 + sin(_t * 2.0) * 0.08


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player") or not body.has_method(&"add_pickup"):
		return
	var amt := amount if amount > 0.0 else float(AMOUNTS.get(pickup_kind, 1.0))
	body.call(&"add_pickup", pickup_kind, amt)
	collected.emit(self)
	queue_free()
