// Hair, brow and lash cards of the MakeHuman-based characters: alpha-hashed
// (TAA resolves it into soft strands), double-sided, with the hair dye slot
// (dye_3 by convention) recolouring the strands while keeping their
// variation.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float roughness = 0.55;
uniform float specular = 0.35;
uniform int dye_slot = 0;
instance uniform vec4 dye_3 : source_color = vec4(1.0, 1.0, 1.0, 0.0);
// mean linear luminance of the (pre-tinted) card texture: a dye keeps the
// strands' variation relative to it
uniform float mean_luma = 0.05;

void fragment() {
	vec4 t = texture(albedo_texture, UV);
	vec3 col = t.rgb;
	if (dye_slot == 3 && dye_3.a > 0.0) {
		float l = dot(t.rgb, vec3(0.2126, 0.7152, 0.0722)) / max(mean_luma, 1e-3);
		col = mix(col, dye_3.rgb * l, dye_3.a);
	}
	ALBEDO = col;
	ALPHA = t.a;
	ALPHA_HASH_SCALE = 1.0;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
