// Fabric, leather and metal of the MakeHuman-based characters
// (tools/characters/mh_build.py): the shared neutral 0.5-grey maps tinted by
// `albedo_color`, or, for a dyeable garment (`dye_slot` 1..3), by the
// CharacterModel's per-instance dye (alpha 0 keeps the authored colour), so
// crowds vary without new materials. Double-sided: hems and open skirts.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_texture : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform float normal_scale = 0.8;
uniform float metallic = 0.0;
uniform float roughness_scale = 1.0;
uniform int dye_slot = 0;
instance uniform vec4 dye_1 : source_color = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform vec4 dye_2 : source_color = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform vec4 dye_3 : source_color = vec4(1.0, 1.0, 1.0, 0.0);

// linear value of the shared maps' sRGB 0.5 grey
const float GREY = 0.2140;

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 tex = texture(albedo_texture, uv).rgb;
	// authored colour: albedo_color holds sRGB 2c, so tex * it = c
	vec3 col = tex * albedo_color.rgb;
	vec4 dye = dye_slot == 1 ? dye_1 : (dye_slot == 2 ? dye_2 : (dye_slot == 3 ? dye_3 : vec4(0.0)));
	if (dye.a > 0.0) {
		col = mix(col, tex / GREY * dye.rgb, dye.a);
	}
	ALBEDO = col;
	ROUGHNESS = clamp(texture(roughness_texture, uv).r * roughness_scale, 0.03, 1.0);
	METALLIC = metallic;
	NORMAL_MAP = texture(normal_texture, uv).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
}
