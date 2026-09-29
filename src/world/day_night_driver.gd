class_name DayNightDriver
extends Node
## Applies the `TimeOfDay` clock to the open world (a child of LuthadelWorld):
## the celestial light (moon by night, a dull ash-veiled sun by day: angle and
## colour), the sky shader's `day_amount`, ambient/fog colour, the mists (via
## `MistController.set_daylight`: thick only at night) and the emissive
## windows, lanterns, far-skyline windows and street lights.
##
## Night values are captured from what `EnvironmentBuilder` authored, so a
## full night (`night_factor() == 1`) reproduces the original night lighting
## exactly; missions and interiors that force night stay deterministic.

## Day: the sun through the ash is a muted, warm grey-orange.
const DAY_LIGHT_COLOR := Color(0.95, 0.8, 0.68)
const DAY_LIGHT_ENERGY := 1.55
const DAY_AMBIENT_COLOR := Color(0.5, 0.49, 0.48)
const DAY_FOG_COLOR := Color(0.5, 0.47, 0.43)
## Peak sun elevation at noon (degrees): the sun stays low and hazy.
const SUN_MAX_ELEVATION := 52.0
const NIGHT_WINDOW_ENERGY := 2.6
const DAY_WINDOW_ENERGY := 0.15
const NIGHT_LANTERN_ENERGY := 5.0
const DAY_LANTERN_ENERGY := 0.7
const NIGHT_FAR_WINDOW_ENERGY := 2.0
const DAY_FAR_WINDOW_ENERGY := 0.05
## far_silhouette.gdshader's authored base colour, and its day counterpart.
const NIGHT_FAR_BASE := Color(0.09, 0.088, 0.086)
const DAY_FAR_BASE := Color(0.3, 0.29, 0.28)

var environment: Environment
var light: DirectionalLight3D
var mist: MistController
var far_lod: FarLod
var sky_material: ShaderMaterial

var _night_basis := Basis.IDENTITY
var _night_color := Color.WHITE
var _night_energy := 1.0
var _night_ambient := Color.WHITE
var _night_fog_color := Color.WHITE
var _night_shadow_blur := 1.5
var _last_n := -1.0
var _last_hour := -100.0


func _init() -> void:
	name = "DayNight"


func setup(p_env: Environment, p_light: DirectionalLight3D, p_mist: MistController, p_far: FarLod) -> void:
	environment = p_env
	light = p_light
	mist = p_mist
	far_lod = p_far
	if environment != null:
		_night_ambient = environment.ambient_light_color
		_night_fog_color = environment.fog_light_color
		if environment.sky != null:
			sky_material = environment.sky.sky_material as ShaderMaterial
	if light != null:
		_night_basis = light.basis
		_night_color = light.light_color
		_night_energy = light.light_energy
		_night_shadow_blur = light.shadow_blur
	if not TimeOfDay.time_changed.is_connected(_on_time_changed):
		TimeOfDay.time_changed.connect(_on_time_changed)
		TimeOfDay.phase_changed.connect(func(_p: int) -> void: apply(true))
	apply(true)


func _exit_tree() -> void:
	if TimeOfDay.time_changed.is_connected(_on_time_changed):
		TimeOfDay.time_changed.disconnect(_on_time_changed)


func _on_time_changed(_h: float) -> void:
	apply(false)


## Pushes the current time into every driven piece. Cheap no-op unless the
## night factor or the sun position moved noticeably (or `force`).
func apply(force: bool) -> void:
	var n := TimeOfDay.night_factor()
	var h := TimeOfDay.effective_hour()
	if not force and absf(n - _last_n) < 0.004 and absf(h - _last_hour) < 0.05:
		return
	var lights_changed := force or absf(n - _last_n) >= 0.004
	_last_n = n
	_last_hour = h
	var d := 1.0 - n
	if light != null:
		# The light swaps sun <-> moon mid-dusk, where it is dimmest.
		light.basis = _night_basis if n >= 0.5 else sun_basis(h)
		light.light_color = DAY_LIGHT_COLOR.lerp(_night_color, n)
		var k := clampf(absf(n - 0.5) * 2.0, 0.0, 1.0)
		light.light_energy = lerpf(DAY_LIGHT_ENERGY, _night_energy, n) * lerpf(0.3, 1.0, k)
		light.shadow_blur = lerpf(2.2, _night_shadow_blur, n)
	if environment != null:
		environment.ambient_light_color = DAY_AMBIENT_COLOR.lerp(_night_ambient, n)
		environment.fog_light_color = DAY_FOG_COLOR.lerp(_night_fog_color, n)
	if sky_material != null:
		sky_material.set_shader_parameter("day_amount", d)
	if mist != null:
		mist.set_daylight(d)
	(WorldMaterials.get_mat(WorldMaterials.Mat.WINDOW) as ShaderMaterial).set_shader_parameter(
		"lit_energy", lerpf(DAY_WINDOW_ENERGY, NIGHT_WINDOW_ENERGY, n))
	(WorldMaterials.get_mat(WorldMaterials.Mat.LANTERN_GLASS) as StandardMaterial3D).emission_energy_multiplier = \
		lerpf(DAY_LANTERN_ENERGY, NIGHT_LANTERN_ENERGY, n)
	if far_lod != null and is_instance_valid(far_lod):
		far_lod.set_lighting(lerpf(DAY_FAR_WINDOW_ENERGY, NIGHT_FAR_WINDOW_ENERGY, n), DAY_FAR_BASE.lerp(NIGHT_FAR_BASE, n))
	if lights_changed and is_inside_tree():
		for l in get_tree().get_nodes_in_group(&"street_light"):
			if l is Light3D:
				apply_to_light(l, n)


## Street/lantern light at night factor `n`: full at night, off by day.
static func apply_to_light(l: Light3D, n: float) -> void:
	var base: float = l.get_meta(&"base_energy", l.light_energy)
	var f := smoothstep(0.1, 0.9, n)
	l.light_energy = base * f
	l.visible = f > 0.01


## Sun orientation at hour `h`: rises in the east, arcs low through the south
## and sets in the west (azimuth 0 = north/-Z, 90 = east/+X).
static func sun_basis(h: float) -> Basis:
	var t := clampf((h - 6.0) / 12.0, 0.0, 1.0)
	var az := deg_to_rad(lerpf(90.0, 270.0, t))
	var el := deg_to_rad(maxf(6.0, sin(t * PI) * SUN_MAX_ELEVATION))
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	return Basis.looking_at(-to_sun, Vector3.UP)
