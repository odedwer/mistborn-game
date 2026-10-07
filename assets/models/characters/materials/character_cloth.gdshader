// Cloth, skin and leather: double-sided, so the inside of a robe or gown shows,
// in shadow, through its open hem (lying down, crouching) instead of the floor
// and the legs showing through missing faces. Elsewhere the body is closed and
// its back faces fail the depth test. See character_surface.gdshaderinc.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#define BACK_SHADE 0.22
#define BACK_INTERIOR
#include "res://assets/models/characters/materials/character_surface.gdshaderinc"
