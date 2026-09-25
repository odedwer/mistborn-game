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
			return _triplanar("stone_wall", 2.6, 0.92, Color(1, 1, 1))
		Mat.BRICK:
			return _triplanar("brick_soot", 2.0, 0.9, Color(1, 1, 1))
		Mat.PLASTER:
			return _triplanar("plaster_dirty", 3.0, 0.95, Color(1, 1, 1))
		Mat.TRIM:
			return _triplanar("stone_wall", 1.6, 0.9, Color(0.55, 0.53, 0.52))
		Mat.SLATE:
			var m := _triplanar("slate_roof", 2.2, 0.62, Color(1, 1, 1))
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		Mat.ROOF_FLAT:
			return _triplanar("slate_roof", 3.5, 0.85, Color(0.55, 0.55, 0.58))
		Mat.WOOD:
			return _triplanar("wood_planks", 1.6, 0.9, Color(1, 1, 1))
		Mat.COBBLE:
			return _triplanar("cobblestone", 2.4, 0.8, Color(1, 1, 1))
		Mat.GROUND_DARK:
			return _triplanar("cobblestone", 3.0, 0.9, Color(0.35, 0.34, 0.35))
		Mat.ASH:
			return _triplanar("plaster_dirty", 6.0, 1.0, Color(0.42, 0.41, 0.40))
		Mat.IRON:
			var m := _triplanar("iron_rusty", 1.0, 0.55, Color(1, 1, 1))
			m.metallic = 0.75
			return m
		Mat.KEEP_STONE:
			return _triplanar("stone_wall", 3.2, 0.88, Color(1.08, 1.06, 1.04))
		Mat.OBSIDIAN:
			var m := _triplanar("stone_wall", 4.0, 0.35, Color(0.16, 0.15, 0.17))
			m.metallic = 0.2
			return m
		Mat.CANAL_WALL:
			return _triplanar("stone_wall", 2.0, 0.85, Color(0.6, 0.62, 0.6))
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
	return StandardMaterial3D.new()


static func _shader_mat(file: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_DIR + file) as Shader
	return m


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
	return m


## [albedo, normal, roughness] for a texture set name (file or procedural).
static func _textures(set_name: String) -> Array:
	if _tex_cache.has(set_name):
		return _tex_cache[set_name]
	var out: Array = [null, null, null]
	var base := TEX_DIR + set_name
	if ResourceLoader.exists(base + "_albedo.png"):
		out[0] = load(base + "_albedo.png")
		if ResourceLoader.exists(base + "_normal.png"):
			out[1] = load(base + "_normal.png")
		if ResourceLoader.exists(base + "_roughness.png"):
			out[2] = load(base + "_roughness.png")
	else:
		var imgs := ProceduralTextures.generate(set_name)
		out[0] = ImageTexture.create_from_image(imgs[0])
		out[1] = ImageTexture.create_from_image(imgs[1])
	_tex_cache[set_name] = out
	return out
