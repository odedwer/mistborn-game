class_name EnvironmentBuilder
extends RefCounted
## Night-time environment: procedural ash-overcast sky with a hazy moon and
## Ashmounts on the horizon, cool moonlight with 4 shadow cascades, ACES
## tonemapping, SSAO, glow for lanterns, depth fog and volumetric fog (the
## mists; densities are then driven by MistController).

const SKY_SHADER := "res://assets/shaders/night_sky.gdshader"

## Moon azimuth/elevation (degrees). Azimuth 0 = north (-Z), 90 = east (+X).
const MOON_AZIMUTH := -35.0
const MOON_ELEVATION := 30.0


## Creates WorldEnvironment + moon under `parent`. Returns
## {"world_env": WorldEnvironment, "environment": Environment, "moon": DirectionalLight3D}.
static func build(parent: Node3D) -> Dictionary:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load(SKY_SHADER) as Shader
	var clouds := NoiseTexture2D.new()
	clouds.width = 512
	clouds.height = 512
	clouds.seamless = true
	var cn := FastNoiseLite.new()
	cn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cn.frequency = 0.006
	cn.fractal_octaves = 5
	clouds.noise = cn
	sm.set_shader_parameter("cloud_noise", clouds)
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.39, 0.5)
	# A touch brighter than before: the old value let unlit foreground
	# geometry (a wall or the player's own shadow side) read as near-black.
	# This keeps the cold-moonlight cast but lifts the floor enough that nothing
	# goes fully dark up close.
	env.ambient_light_energy = 1.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.3
	env.tonemap_white = 6.0

	env.ssao_enabled = true
	env.ssao_radius = 1.6
	# Slightly lighter contact shadowing than before -- 2.2 was crushing
	# corners and doorways to near-black at close range.
	env.ssao_intensity = 1.7
	env.ssao_power = 1.5
	env.ssil_enabled = false
	env.sdfgi_enabled = false

	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	# Depth fog: distance haze (and the only mist on the Low preset). Ash
	# from the constant fall gives the haze a warm-grey cast rather than a
	# cold blue one -- it reads as airborne ash, not just atmospheric blue.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.24, 0.225, 0.205)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.35
	env.fog_height = 14.0
	env.fog_height_density = 0.03
	env.fog_aerial_perspective = 0.2

	# Volumetric fog: base haze. Local swirling mist comes from FogVolumes.
	# Off-white ash mist (per the design doc) rather than a blue-tinted one,
	# with a faint warm emission so lantern light glows visibly as it
	# scatters through it (the "warm lantern pools" half of the look).
	env.volumetric_fog_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.85, 0.83, 0.78)
	env.volumetric_fog_emission = Color(0.05, 0.044, 0.034)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_ambient_inject = 0.35
	env.volumetric_fog_sky_affect = 0.3
	env.volumetric_fog_gi_inject = 0.0

	env.adjustment_enabled = true
	env.adjustment_saturation = 0.82
	env.adjustment_contrast = 1.06

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	var az := deg_to_rad(MOON_AZIMUTH)
	var el := deg_to_rad(MOON_ELEVATION)
	var to_moon := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	moon.basis = Basis.looking_at(-to_moon, Vector3.UP)
	moon.light_color = Color(0.62, 0.7, 0.92)
	moon.light_energy = 0.9
	moon.light_indirect_energy = 0.5
	moon.light_volumetric_fog_energy = 0.7
	moon.shadow_enabled = true
	moon.shadow_blur = 1.5
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon.directional_shadow_max_distance = 250.0
	moon.directional_shadow_blend_splits = true
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	parent.add_child(moon)
	return {"world_env": we, "environment": env, "moon": moon}
