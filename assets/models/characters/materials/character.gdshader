// Shared character shader: vertex-coloured PBR with procedural surface detail.
// Vertex colours are stored as sRGB. UVs are in metres along each lofted part,
// which gives a weave/grain pattern with a uniform scale that sticks to the surface.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.4;
uniform float detail_scale = 180.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.12;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.15;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.35;
uniform float rim_tint : hint_range(0.0, 1.0) = 0.5;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

#include "res://assets/models/characters/materials/character_common.gdshaderinc"

void fragment() {
	// pow() of a negative base is undefined (NaN on most GPUs). Compressed
	// vertex colours of near-black parts (boots, hair, straps) can decode a
	// hair below zero; the NaN pixels then bloom into big white orbs.
	vec3 c = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	vec2 uv = UV * detail_scale;
	// fine weave (cloth) / grain (leather, wood): two crossing sines modulated by noise
	float weave = 0.5 + 0.25 * sin(uv.x * 3.1) * sin(uv.y * 3.1);
	float n = vnoise(uv * 0.35) * 0.6 + vnoise(uv * 0.09) * 0.4;
	float d = mix(weave, n, 0.6);
	float grime = vnoise(UV * 6.0);
	c *= 1.0 + detail_strength * (d - 0.5) * 2.0;
	c *= 1.0 - grime_strength * grime * 0.6;
	ALBEDO = c;
	ROUGHNESS = clamp(roughness + (n - 0.5) * 0.2, 0.02, 1.0);
	METALLIC = metallic;
	SPECULAR = specular;
	// A soft rim keeps silhouettes readable at night in thick mist.
	RIM = rim_strength;
	RIM_TINT = rim_tint;
	EMISSION = emission_color * emission_energy;
}
