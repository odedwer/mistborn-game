shader_type spatial;
// Cheap facade windows. Vertex colour: r = lit amount, g = per-window random,
// b = closed shutters. UV spans the window 0..1. Draws frame, mullions,
// glass or wooden shutters, and warm interior light with a faint flicker.

uniform vec3 lit_color : source_color = vec3(1.0, 0.56, 0.24);
uniform float lit_energy = 2.6;
uniform vec3 glass_color : source_color = vec3(0.025, 0.03, 0.04);
uniform vec3 frame_color : source_color = vec3(0.09, 0.07, 0.055);
uniform vec3 shutter_color : source_color = vec3(0.16, 0.11, 0.08);

void fragment() {
	vec2 uv = UV;
	float lit = COLOR.r;
	float rnd = COLOR.g;
	float shutter = COLOR.b;
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float frame = 1.0 - step(0.075, edge);
	float mull = max(1.0 - step(0.028, abs(uv.x - 0.5)), 1.0 - step(0.022, abs(uv.y - 0.42)));
	float f = max(frame, mull);
	float flicker = 0.88 + 0.12 * sin(TIME * (1.3 + rnd * 2.0) + rnd * 40.0) * sin(TIME * 3.1 + rnd * 11.0);
	if (shutter > 0.5) {
		float plank = fract(uv.x * 4.0);
		float slat = step(0.07, plank);
		ALBEDO = shutter_color * mix(0.55, 1.0, slat) * (0.8 + rnd * 0.4);
		ROUGHNESS = 0.9;
		EMISSION = lit_color * lit * lit_energy * 0.5 * (1.0 - slat) * flicker;
	} else {
		// Interior: warm gradient, darker at the top, curtain silhouettes.
		float curtain = smoothstep(0.15, 0.2, abs(uv.x - 0.5 + (rnd - 0.5) * 0.3));
		float grad = mix(1.1, 0.6, uv.y) * mix(0.45, 1.0, curtain);
		vec3 glow = lit_color * mix(0.75, 1.15, rnd) * grad;
		ALBEDO = mix(glass_color, frame_color, f);
		ROUGHNESS = mix(0.12, 0.85, f);
		SPECULAR = 0.6;
		EMISSION = (1.0 - f) * glow * lit * lit_energy * flicker;
	}
}
