shader_type spatial;
// Dark, ash-flecked canal water with slow scrolling ripples.

uniform sampler2D normal_noise : hint_normal, repeat_enable, filter_linear_mipmap;
uniform vec3 water_color : source_color = vec3(0.012, 0.016, 0.018);
uniform vec3 ash_color : source_color = vec3(0.12, 0.115, 0.11);
uniform float ripple_scale = 0.08;
uniform float flow_speed = 0.02;
uniform float normal_strength = 0.35;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * ripple_scale;
	vec2 flow = vec2(0.0, TIME * flow_speed);
	vec3 n1 = texture(normal_noise, uv + flow).rgb;
	vec3 n2 = texture(normal_noise, uv * 1.7 - flow * 1.3 + 0.5).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = normal_strength;
	// Floating ash film in the calmer patches.
	float ash = smoothstep(0.62, 0.75, texture(normal_noise, uv * 0.35 + flow * 0.3).b);
	ALBEDO = mix(water_color, ash_color, ash * 0.5);
	ROUGHNESS = mix(0.05, 0.8, ash);
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
