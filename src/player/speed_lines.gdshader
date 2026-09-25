// Screen-edge radial speed streaks on a quad parented to the camera.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 streak_color : source_color = vec4(0.8, 0.85, 0.95, 1.0);

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float slot = floor(a * 38.0);
	float h = hash(slot);
	float frac_a = fract(a * 38.0);
	float thin = smoothstep(0.5, 0.0, abs(frac_a - 0.5) - 0.32);
	float scroll = fract(r * 1.5 - TIME * (2.5 + h * 3.0) + h * 7.0);
	float streak = step(0.55, h) * smoothstep(0.0, 0.2, scroll) * smoothstep(1.0, 0.6, scroll);
	float edge = smoothstep(0.55, 1.05, r);
	float v = streak * thin * edge * amount * 0.35;
	ALBEDO = streak_color.rgb * v;
	ALPHA = 1.0;
}
