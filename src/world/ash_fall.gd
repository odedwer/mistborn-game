class_name AshFall
extends GPUParticles3D
## Constant ashfall: tiny grey flakes drifting down around the camera.
## MistController moves it with the camera and scales the particle count
## with the quality preset.


func _init() -> void:
	local_coords = false
	lifetime = 16.0
	preprocess = 16.0
	amount = 1500
	visibility_aabb = AABB(Vector3(-45, -40, -45), Vector3(90, 70, 90))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(38, 16, 38)
	pm.direction = Vector3(0.2, -1.0, 0.1)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0.18, -0.35, 0.08)
	pm.damping_min = 0.05
	pm.damping_max = 0.15
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 5.0
	pm.turbulence_noise_speed = Vector3(0.05, 0.02, 0.05)
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.04)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.albedo_color = Color(0.3, 0.29, 0.28)
	mat.roughness = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	quad.material = mat
	draw_pass_1 = quad


## Sets the particle count (restarts the emitter).
func set_amount(n: int) -> void:
	if n == amount:
		return
	amount = maxi(n, 1)
	restart()
