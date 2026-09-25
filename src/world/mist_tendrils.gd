class_name MistTendrils
extends Node3D
## Mist coiling around the player: a spiral-density FogVolume (volumetric
## qualities) plus a few soft billboard wisps that also work on the
## Compatibility renderer. Strength (0..1) rises while the player burns metals.

var use_volume := true:
	set(v):
		use_volume = v
		if _volume != null:
			_volume.visible = v
var _volume: FogVolume
var _wisps: GPUParticles3D
var _wisp_mat: StandardMaterial3D
var _material: ShaderMaterial


func setup(material: ShaderMaterial) -> void:
	_material = material
	_volume = FogVolume.new()
	_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	_volume.size = Vector3(9.0, 5.0, 9.0)
	_volume.material = material
	_volume.visible = use_volume
	add_child(_volume)

	_wisps = GPUParticles3D.new()
	_wisps.amount = 28
	_wisps.lifetime = 5.0
	_wisps.preprocess = 5.0
	_wisps.local_coords = false
	_wisps.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 10, 16))
	_wisps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 2.2
	pm.emission_ring_inner_radius = 1.2
	pm.emission_ring_height = 2.0
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0, 0.05, 0)
	pm.tangential_accel_min = 0.8
	pm.tangential_accel_max = 1.6
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.35, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	_wisps.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.0)
	_wisp_mat = StandardMaterial3D.new()
	_wisp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_wisp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wisp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wisp_mat.vertex_color_use_as_albedo = true
	_wisp_mat.albedo_color = Color(0.75, 0.77, 0.82, 0.08)
	_wisp_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	_wisp_mat.albedo_texture = tex
	quad.material = _wisp_mat
	_wisps.draw_pass_1 = quad
	add_child(_wisps)
	visible = false


## Follows `target` (hidden when null) with the given strength 0..1.
func follow(target: Node3D, strength: float) -> void:
	if target == null or not target.is_inside_tree():
		visible = false
		return
	visible = true
	global_position = target.global_position + Vector3(0, 1.0, 0)
	if _material != null:
		_material.set_shader_parameter("strength", strength)
	if _wisp_mat != null:
		_wisp_mat.albedo_color.a = 0.05 + 0.1 * strength
