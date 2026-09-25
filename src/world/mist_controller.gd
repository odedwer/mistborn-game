class_name MistController
extends Node3D
## THE MISTS. Owns every mist/ash effect and the knobs other systems use:
## - `set_tin_vision(v)` (0..1): thins the mist ~70 %, raises exposure and
##   pushes the volumetric fog distance out.
## - `set_quality(level)`: 0 low (depth fog only), 1 medium, 2 high, 3 ultra.
## Mist is a large swirling FogVolume that follows the focus (player/camera),
## denser FogVolumes over canals (spawned by chunks with `canal_material`),
## tendrils coiling around the player, and ash falling around the camera.

const MIST_SHADER := "res://assets/shaders/mist_volume.gdshader"
const TENDRIL_SHADER := "res://assets/shaders/mist_tendril.gdshader"

## Quality presets: [volumetric, volume width, volume depth, fog length, ash, tendrils].
const QUALITY := [
	[false, 64, 48, 48.0, 400, false],
	[true, 64, 48, 64.0, 1000, true],
	[true, 128, 96, 96.0, 2400, true],
	[true, 192, 128, 128.0, 4000, true],
]

## Base volumetric haze (whole view). The FogVolumes add the swirling mist.
@export var base_fog_density := 0.012
## Peak density of the mist volume near the ground.
@export var mist_density := 0.035
@export var canal_density := 0.06
@export var base_exposure := 1.15
@export var base_depth_fog := 0.0045
@export var low_quality_depth_fog := 0.016
## Size of the mist volume that follows the focus.
@export var mist_volume_size := Vector3(360.0, 70.0, 360.0)

var environment: Environment
var mist_material: ShaderMaterial
var canal_material: ShaderMaterial
var tendril_material: ShaderMaterial
var quality := 2
var tin := 0.0
var _mist_volume: FogVolume
var _tendrils: MistTendrils
var _ash: AshFall
var _noise: NoiseTexture3D
var _burning: Dictionary = {}
var _tendril_strength := 0.35
var _compat := false


func _init() -> void:
	add_to_group(&"mist_controller")
	name = "MistController"


## Wires the controller to the world's Environment. Call once after adding
## to the tree (LuthadelWorld does this).
func setup(env: Environment) -> void:
	environment = env
	_compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	_noise = NoiseTexture3D.new()
	_noise.width = 64
	_noise.height = 64
	_noise.depth = 64
	_noise.seamless = true
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.045
	fnl.fractal_octaves = 3
	_noise.noise = fnl

	mist_material = _fog_material(MIST_SHADER)
	mist_material.set_shader_parameter("density", mist_density)
	canal_material = _fog_material(MIST_SHADER)
	canal_material.set_shader_parameter("density", canal_density)
	canal_material.set_shader_parameter("base_height", -2.5)
	canal_material.set_shader_parameter("height_falloff", 0.25)
	canal_material.set_shader_parameter("noise_scale", 0.04)
	tendril_material = _fog_material(TENDRIL_SHADER)

	_mist_volume = FogVolume.new()
	_mist_volume.name = "MistVolume"
	_mist_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	_mist_volume.size = mist_volume_size
	_mist_volume.material = mist_material
	add_child(_mist_volume)

	_tendrils = MistTendrils.new()
	_tendrils.name = "Tendrils"
	add_child(_tendrils)
	_tendrils.setup(tendril_material)

	_ash = AshFall.new()
	_ash.name = "Ash"
	add_child(_ash)

	var ev := get_node_or_null(^"/root/Events")
	if ev != null and ev.has_signal(&"metal_burn_changed"):
		ev.connect(&"metal_burn_changed", _on_metal_burn_changed)
	set_quality(quality)


func _fog_material(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path) as Shader
	m.set_shader_parameter("noise_tex", _noise)
	return m


## Tin vision 0..1: lerps mist density down ~70 %, raises exposure and the
## volumetric fog visibility distance.
func set_tin_vision(v: float) -> void:
	tin = clampf(v, 0.0, 1.0)
	_apply()


## 0 = low (no volumetric fog, depth fog instead), 1 = medium, 2 = high, 3 = ultra.
func set_quality(level: int) -> void:
	quality = clampi(level, 0, QUALITY.size() - 1)
	var q: Array = QUALITY[quality]
	var volumetric: bool = q[0] and not _compat
	if volumetric:
		RenderingServer.environment_set_volumetric_fog_volume_size(q[1], q[2])
	if _ash != null:
		_ash.set_amount(q[4])
	if _tendrils != null:
		_tendrils.use_volume = q[5] and volumetric
	_apply()


## Effective quality after renderer limits (0 in the Compatibility renderer).
func effective_quality() -> int:
	return 0 if _compat else quality


func _apply() -> void:
	if environment == null:
		return
	var q: Array = QUALITY[quality]
	var volumetric: bool = q[0] and not _compat
	var thin := 1.0 - 0.7 * tin
	environment.volumetric_fog_enabled = volumetric
	environment.volumetric_fog_density = base_fog_density * thin
	environment.volumetric_fog_length = float(q[3]) * (1.0 + tin)
	var depth := base_depth_fog if volumetric else low_quality_depth_fog
	environment.fog_density = depth * thin
	environment.tonemap_exposure = base_exposure * (1.0 + 0.9 * tin)
	environment.ambient_light_energy = 0.32 + 0.45 * tin
	for m: ShaderMaterial in [mist_material, canal_material]:
		if m != null:
			m.set_shader_parameter("density_scale", thin)
	if _mist_volume != null:
		_mist_volume.visible = volumetric
	if is_inside_tree():
		get_tree().call_group(&"mist_volume", &"set_visible", volumetric)


func _on_metal_burn_changed(allomancer: Node, metal: int, burning: bool) -> void:
	if allomancer == null:
		return
	var is_player := allomancer.is_in_group(&"player")
	if not is_player and allomancer.get_parent() != null:
		is_player = allomancer.get_parent().is_in_group(&"player")
	if not is_player:
		return
	if burning:
		_burning[metal] = true
	else:
		_burning.erase(metal)


func _focus_node() -> Node3D:
	return get_tree().get_first_node_in_group(&"player") as Node3D


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var player := _focus_node()
	var focus: Vector3
	if player != null:
		focus = player.global_position
	elif cam != null:
		focus = cam.global_position
	if _mist_volume != null:
		# Snap so the volume edges don't visibly swim with the camera.
		var snapped := Vector3(snappedf(focus.x, 16.0), mist_volume_size.y * 0.5 - 4.0, snappedf(focus.z, 16.0))
		_mist_volume.global_position = snapped
	if _ash != null and cam != null:
		_ash.global_position = cam.global_position + Vector3(0, 6.0, 0)
	var target := 1.0 if not _burning.is_empty() else 0.35
	_tendril_strength = move_toward(_tendril_strength, target, delta * 0.6)
	if _tendrils != null:
		_tendrils.follow(player, _tendril_strength)
