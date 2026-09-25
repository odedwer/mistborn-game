// Shared helpers for the character shaders.

// Per-instance dyes (CharacterModel.dye_colors). Vertex-colour alpha tags dyeable
// regions: 1.0 = none, 0.75 = slot 1, 0.5 = slot 2, 0.25 = slot 3. Colours are sRGB
// (converted here, not with source_color, so instance values are unambiguous);
// alpha 0 keeps the authored colour. Dyeable regions are authored as neutral greys
// whose luminance (relative to mid-grey) shades the dye.
instance uniform vec4 dye_1 = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform vec4 dye_2 = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform vec4 dye_3 = vec4(1.0, 1.0, 1.0, 0.0);

vec3 apply_dye(vec3 c_lin, float tag) {
	if (tag > 0.875) {
		return c_lin;
	}
	vec4 d = tag > 0.625 ? dye_1 : (tag > 0.375 ? dye_2 : dye_3);
	float l = dot(c_lin, vec3(0.2126, 0.7152, 0.0722));
	vec3 dyed = pow(d.rgb, vec3(2.2)) * (l / 0.181);
	return mix(c_lin, dyed, d.a);
}
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
