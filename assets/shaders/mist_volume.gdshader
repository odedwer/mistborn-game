shader_type fog;
// The mists: slowly swirling 3D-noise fog, densest near the ground and over
// water, thinning with height. `density_scale` is driven by tin vision.

uniform sampler3D noise_tex : repeat_enable;
uniform float density = 0.035;
uniform float density_scale = 1.0;
uniform float height_falloff = 0.055;
uniform float base_height = 0.0;
uniform vec3 albedo : source_color = vec3(0.84, 0.86, 0.9);
uniform vec3 emission : source_color = vec3(0.035, 0.037, 0.042);
uniform float noise_scale = 0.018;
uniform vec3 wind = vec3(0.7, 0.05, 0.3);
uniform float swirl_speed = 0.05;
uniform float edge_fade = 0.12;

void fog() {
	vec3 p = WORLD_POSITION;
	float h = max(p.y - base_height, 0.0);
	float hf = exp(-h * height_falloff);
	float t = TIME * swirl_speed;
	// Two octaves drifting in different directions give a slow curling motion.
	vec3 q = p * noise_scale + wind * TIME * noise_scale;
	float n1 = texture(noise_tex, q + vec3(sin(t), 0.0, cos(t)) * 0.15).r;
	float n2 = texture(noise_tex, q * 2.4 - vec3(t * 0.6, n1 * 0.35, -t * 0.4)).r;
	float n = smoothstep(0.2, 0.85, n1 * 0.62 + n2 * 0.38);
	vec3 e = min(UVW, vec3(1.0) - UVW);
	float edge = smoothstep(0.0, edge_fade, min(min(e.x, e.y), e.z));
	DENSITY = density * density_scale * hf * mix(0.3, 1.7, n) * edge;
	ALBEDO = albedo;
	EMISSION = emission * hf * density_scale;
}
