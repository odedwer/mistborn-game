class_name WorldMaterials
extends RefCounted
## Shared materials for the generated city (main thread only).
##
## Walls, roofs and ground use StandardMaterial3D with world-space triplanar
## mapping so merged box geometry textures cleanly without UVs. Vertex
## colours carry per-building tint and soot. Textures are loaded from
## `res://assets/textures/<name>_{albedo,normal,roughness}.png` when present;
## otherwise a cheap procedural fallback is painted with native Image calls.

enum Mat {
	STONE, BRICK, PLASTER, TRIM, SLATE, ROOF_FLAT, WOOD, WINDOW, COBBLE,
	GROUND_DARK, ASH, WATER, IRON, KEEP_STONE, OBSIDIAN, LANTERN_GLASS, CANAL_WALL, FAR,
	ASHLAR, BANNER, BRONZE, DRESSED_STONE,
}

const TEX_DIR := "res://assets/textures/"
const SHADER_DIR := "res://assets/shaders/"

static var _cache: Dictionary = {}
static var _tex_cache: Dictionary = {}


## Returns the shared material for `id`, creating it on first use.
static func get_mat(id: int) -> Material:
	if _cache.has(id):
		return _cache[id]
	var m := _create(id)
	_cache[id] = m
	return m


## Drops all cached materials (tests / hot reload).
static func clear() -> void:
	_cache.clear()
	_tex_cache.clear()


static func _create(id: int) -> Material:
	match id:
		Mat.STONE:
			return _surface("stone_wall", 2.6, Color(1, 1, 1), 0.025, 0.0)
		Mat.BRICK:
			return _surface("brick_soot", 2.0, Color(1, 1, 1), 0.012, 0.0)
		Mat.PLASTER:
			return _surface("plaster_dirty", 3.0, Color(1, 1, 1), 0.01, 0.0)
		Mat.TRIM:
			return _surface("ashlar", 1.6, Color(0.62, 0.6, 0.58), 0.008, 0.0)
		Mat.SLATE:
			var m := _surface("slate_roof", 2.2, Color(1, 1, 1), 0.02, 0.0, true)
			if m is BaseMaterial3D:
				(m as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		Mat.ROOF_FLAT:
			return _surface("slate_roof", 3.5, Color(0.55, 0.55, 0.58), 0.015, 1.0)
		Mat.WOOD:
			return _surface("wood_planks", 1.6, Color(1, 1, 1), 0.008, 0.0)
		Mat.COBBLE:
			return _surface("cobblestone", 1.6, Color(1, 1, 1), 0.035, 1.0)
		Mat.GROUND_DARK:
			return _surface("cobblestone", 1.6, Color(0.55, 0.54, 0.55), 0.035, 1.0)
		Mat.ASH:
			return _triplanar("plaster_dirty", 6.0, 1.0, Color(0.42, 0.41, 0.40))
		Mat.IRON:
			var m := _triplanar("iron_rusty", 1.0, 0.55, Color(1, 1, 1))
			m.metallic = 0.75
			return m
		Mat.KEEP_STONE:
			return _surface("stone_wall", 3.2, Color(1.08, 1.06, 1.04), 0.03, 0.0)
		Mat.OBSIDIAN:
			var m := _triplanar("stone_wall", 4.0, 0.35, Color(0.16, 0.15, 0.17))
			m.metallic = 0.2
			return m
		Mat.CANAL_WALL:
			return _surface("stone_wall", 2.0, Color(0.6, 0.62, 0.6), 0.02, 0.0)
		Mat.LANTERN_GLASS:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(1.0, 0.75, 0.45)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.58, 0.24)
			m.emission_energy_multiplier = 5.0
			m.roughness = 0.3
			return m
		Mat.WINDOW:
			return _shader_mat("window_glow.gdshader")
		Mat.WATER:
			var m := _shader_mat("canal_water.gdshader")
			var n := NoiseTexture2D.new()
			n.seamless = true
			n.as_normal_map = true
			n.bump_strength = 3.0
			n.width = 256
			n.height = 256
			var fnl := FastNoiseLite.new()
			fnl.frequency = 0.03
			fnl.fractal_octaves = 3
			n.noise = fnl
			m.set_shader_parameter("normal_noise", n)
			return m
		Mat.FAR:
			return _shader_mat("far_silhouette.gdshader")
		Mat.BANNER:
			# Heraldic cloth: colour from the vertex colour, double-sided.
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.roughness = 0.92
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		Mat.ASHLAR:
			# Merchant/noble dressed stone: its own coursed-block texture
			# (tools/gen_textures.py `ashlar`: 12 courses per tile), so a 2.4 m
			# tile gives 0.2 m courses of 0.2-0.45 m bevelled blocks. The shared
			# stone_wall texture is a polygonal rubble that read as crazy
			# paving at any scale.
			return _surface("ashlar", 2.4, Color(1, 1, 1), 0.01, 0.0)
		Mat.DRESSED_STONE:
			# The same coursed-block texture at three times the scale (0.6 m
			# courses of 0.6-1.35 m blocks), slightly darker and weathered: big
			# dressed blocks for statue plinths and fountain pedestals, where
			# the 0.2 m facade courses read as brickwork.
			return _surface("ashlar", 7.2, Color(0.86, 0.84, 0.8), 0.03, 0.0)
		Mat.BRONZE:
			return _bronze()
	return StandardMaterial3D.new()


## Weathered statuary bronze (`bronze.gdshader`): dark brown-bronze with
## verdigris that gathers in the recesses the mesh's vertex colour marks, on
## the ledges, and in runs down from the shoulders and the belt, rather than
## a random mottle. The shader places the runs itself, each with its own
## width, length and spacing. Both textures are built here, synchronously,
## from fixed noise seeds: vertical streak noise (a 128x16 seamless noise
## stretched to 128x128, so the features are eight times taller than wide),
## which breaks the runs up along their length, and a fine grain.
static func _bronze() -> ShaderMaterial:
	var fnl := FastNoiseLite.new()
	fnl.seed = 0xB21
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.09
	fnl.fractal_octaves = 2
	var runs_src := fnl.get_seamless_image(128, 16)
	var runs := Image.create(128, 128, false, Image.FORMAT_L8)
	for y in 128:
		var fy := float(y) / 8.0
		var y0 := int(fy) % 16
		var y1 := (y0 + 1) % 16
		var t := fy - floorf(fy)
		for x in 128:
			var v := lerpf(runs_src.get_pixel(x, y0).r, runs_src.get_pixel(x, y1).r, t)
			runs.set_pixel(x, y, Color(v, v, v))
	runs.generate_mipmaps()
	fnl.seed = 0xB20
	fnl.frequency = 0.035
	fnl.fractal_octaves = 4
	var grain := fnl.get_seamless_image(128, 128)
	grain.convert(Image.FORMAT_L8)
	grain.generate_mipmaps()
	var m := _shader_mat("bronze.gdshader")
	m.set_shader_parameter("streaks", ImageTexture.create_from_image(runs))
	m.set_shader_parameter("mottle", ImageTexture.create_from_image(grain))
	return m


## A copy of material `id` that dithers out between `fade_from` and `fade_to`
## metres from the camera, per pixel (StandardMaterial3D distance fade,
## pixel dither). It stays in the opaque pass and looks the same in Forward+
## and Compatibility, unlike `visibility_range_fade_mode`, which alpha-blends
## in Forward+ and is ignored by Compatibility.
static func faded(id: int, fade_from: float, fade_to: float) -> Material:
	var key := "faded_%d_%.1f_%.1f" % [id, fade_from, fade_to]
	if _cache.has(key):
		return _cache[key]
	var src := get_mat(id)
	if src is ShaderMaterial:
		var sm := src.duplicate() as ShaderMaterial
		sm.set_shader_parameter("fade_from", fade_from)
		sm.set_shader_parameter("fade_to", fade_to)
		_cache[key] = sm
		return sm
	var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	# Max < min reverses the fade: opaque up to `fade_from`, gone at `fade_to`.
	m.distance_fade_max_distance = fade_from
	m.distance_fade_min_distance = fade_to
	_cache[key] = m
	return m


static func _shader_mat(file: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_DIR + file) as Shader
	return m


## World-space triplanar PBR surface (world_surface.gdshader): parallax on
## the ground projection, macro variation and wetness/puddles. Falls back to
## the plain triplanar StandardMaterial3D when the set has no height map
## (the gen_textures.py sets) or under the Compatibility renderer.
static func _surface(tex: String, world_size: float, tint: Color, depth: float, puddles: float,
		two_sided := false) -> Material:
	var base := TEX_DIR + tex
	if not ResourceLoader.exists(base + "_height.png") \
			or RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return _triplanar(tex, world_size, 0.85, tint)
	var m := _shader_mat("world_surface_2s.gdshader" if two_sided else "world_surface.gdshader")
	var t := _textures(tex)
	m.set_shader_parameter("albedo_tex", t[0])
	m.set_shader_parameter("normal_tex", t[1])
	m.set_shader_parameter("rough_tex", t[2])
	m.set_shader_parameter("ao_tex", t[3])
	m.set_shader_parameter("height_tex", load(base + "_height.png"))
	m.set_shader_parameter("macro_noise", _macro_noise())
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("world_size", world_size)
	m.set_shader_parameter("height_depth", depth)
	m.set_shader_parameter("puddle_amount", puddles)
	return m


## Shared large-scale seamless noise for the surfaces' macro variation and
## puddle placement.
static func _macro_noise() -> Texture2D:
	if _tex_cache.has("_macro"):
		return _tex_cache["_macro"]
	var n := NoiseTexture2D.new()
	n.seamless = true
	n.width = 512
	n.height = 512
	n.generate_mipmaps = true
	var f := FastNoiseLite.new()
	f.seed = 0x5EA
	f.frequency = 0.012
	f.fractal_octaves = 4
	n.noise = f
	_tex_cache["_macro"] = n
	return n


## Triplanar world-space material. `world_size` is metres per texture tile.
static func _triplanar(tex: String, world_size: float, roughness: float, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / world_size
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.roughness = roughness
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var tex_set := _textures(tex)
	m.albedo_texture = tex_set[0]
	if tex_set[1] != null:
		m.normal_enabled = true
		m.normal_texture = tex_set[1]
		m.normal_scale = 1.0
	if tex_set[2] != null:
		m.roughness_texture = tex_set[2]
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		# The texture carries the detail; keep the scalar as a soft multiplier.
		m.roughness = clampf(roughness + 0.15, 0.0, 1.0)
	if tex_set[3] != null:
		m.ao_enabled = true
		m.ao_texture = tex_set[3]
		m.ao_light_affect = 0.4
	return m


## [albedo, normal, roughness, ao] for a texture set name (file or procedural).
static func _textures(set_name: String) -> Array:
	if _tex_cache.has(set_name):
		return _tex_cache[set_name]
	var out: Array = [null, null, null, null]
	var base := TEX_DIR + set_name
	if ResourceLoader.exists(base + "_albedo.png"):
		out[0] = load(base + "_albedo.png")
		if ResourceLoader.exists(base + "_normal.png"):
			out[1] = load(base + "_normal.png")
		if ResourceLoader.exists(base + "_roughness.png"):
			out[2] = load(base + "_roughness.png")
		if ResourceLoader.exists(base + "_ao.png"):
			out[3] = load(base + "_ao.png")
	else:
		var imgs := ProceduralTextures.generate(set_name)
		out[0] = ImageTexture.create_from_image(imgs[0])
		out[1] = ImageTexture.create_from_image(imgs[1])
	_tex_cache[set_name] = out
	return out
