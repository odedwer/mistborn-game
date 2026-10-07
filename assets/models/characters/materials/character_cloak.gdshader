// Double-sided variant for mistcloak tassels / capes (back faces slightly darker).
// See character_surface.gdshaderinc.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#define BACK_SHADE 0.6
#include "res://assets/models/characters/materials/character_surface.gdshaderinc"
