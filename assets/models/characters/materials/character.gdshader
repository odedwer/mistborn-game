// Shared character shader (metal, obsidian, glow): single-sided.
// See character_surface.gdshaderinc.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://assets/models/characters/materials/character_surface.gdshaderinc"
