shader_type fog;
// Mist tendrils coiling around an allomancer. Spiral arms of density rotate
// around the volume centre; `strength` rises while the player burns metals.

uniform sampler3D noise_tex : repeat_enable;
uniform float strength = 0.4;
uniform float density = 0.12;
uniform float spin_speed = 0.8;
uniform float arms = 3.0;
uniform vec3 albedo : source_color = vec3(0.9, 0.92, 0.95);
uniform vec3 emission : source_color = vec3(0.05, 0.055, 0.06);

void fog() {
	vec3 local = WORLD_POSITION - OBJECT_POSITION;
	float r = length(local.xz);
	float ang = atan(local.z, local.x);
	float n = texture(noise_tex, WORLD_POSITION * 0.12 + vec3(0.0, TIME * 0.05, 0.0)).r;
	float spiral = sin(ang * arms + r * 1.3 - TIME * spin_speed + local.y * 0.6 + n * 3.0);
	float arm = smoothstep(0.55, 1.0, spiral);
	// Hollow near the body, fading at the rim (SDF < 0 inside the ellipsoid).
	float inner = smoothstep(0.6, 1.6, r);
	float rim = clamp(-SDF * 0.8, 0.0, 1.0);
	DENSITY = density * strength * arm * inner * rim * (0.6 + n * 0.8);
	ALBEDO = albedo;
	EMISSION = emission * strength;
}
