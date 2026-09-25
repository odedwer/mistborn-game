shader_type sky;
// Luthadel night sky: dark ash overcast, faint red glow on the horizon from
// the Ashmounts, a hazy moon behind the clouds (from the first directional
// light) and volcano silhouettes with glowing craters along the horizon.

uniform vec3 zenith_color : source_color = vec3(0.010, 0.012, 0.018);
uniform vec3 horizon_color : source_color = vec3(0.060, 0.050, 0.052);
uniform vec3 horizon_glow : source_color = vec3(0.32, 0.09, 0.04);
uniform float horizon_glow_strength = 0.45;
uniform vec3 moon_color : source_color = vec3(0.85, 0.88, 0.95);
uniform float moon_size = 0.03;
uniform float moon_haze = 0.35;
uniform float moon_brightness = 2.2;
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
uniform float cloud_cover = 0.75;
uniform float cloud_speed = 0.004;
uniform vec3 mountain_color : source_color = vec3(0.012, 0.010, 0.011);
uniform vec3 crater_glow : source_color = vec3(1.0, 0.28, 0.06);
uniform float crater_strength = 1.4;

float mountain_profile(float az) {
	// A few Ashmount cones around the horizon (azimuth in radians).
	float h = 0.012 + 0.006 * sin(az * 7.0) + 0.004 * sin(az * 17.0 + 1.3);
	const int N = 6;
	float peaks[N] = float[](0.6, 1.4, 2.3, 3.4, 4.5, 5.6);
	float heights[N] = float[](0.075, 0.05, 0.09, 0.06, 0.08, 0.045);
	for (int i = 0; i < N; i++) {
		float d = abs(mod(az - peaks[i] + 3.14159, 6.28318) - 3.14159);
		float cone = heights[i] - d * 0.55;
		// Flattened crater top.
		cone = min(cone, heights[i] - 0.01);
		h = max(h, cone);
	}
	return h;
}

float crater_light(float az, float y) {
	const int N = 6;
	float peaks[N] = float[](0.6, 1.4, 2.3, 3.4, 4.5, 5.6);
	float heights[N] = float[](0.075, 0.05, 0.09, 0.06, 0.08, 0.045);
	float g = 0.0;
	for (int i = 0; i < N; i++) {
		float d = abs(mod(az - peaks[i] + 3.14159, 6.28318) - 3.14159);
		float top = heights[i] - 0.01;
		float dy = max(y - top, 0.0);
		g += exp(-d * d * 900.0) * exp(-dy * 25.0) * step(top - 0.004, y);
	}
	return g;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, zenith_color, smoothstep(-0.02, 0.55, h));
	col += horizon_glow * horizon_glow_strength * exp(-max(h, 0.0) * 10.0);

	// Overcast ash clouds projected on a dome.
	float cloud = 0.0;
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 0.22 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		float n = texture(cloud_noise, uv).r * 0.65 + texture(cloud_noise, uv * 2.7 + 0.3).r * 0.35;
		cloud = smoothstep(1.0 - cloud_cover, 1.0, n) * smoothstep(0.0, 0.18, h);
		col = mix(col, col * 0.55 + horizon_glow * 0.03, cloud * 0.8);
	}

	// Hazy moon.
	if (LIGHT0_ENABLED) {
		float c = dot(d, normalize(LIGHT0_DIRECTION));
		float disc = smoothstep(cos(moon_size), cos(moon_size * 0.85), c);
		float halo = pow(max(c, 0.0), 90.0) * 0.6 + pow(max(c, 0.0), 12.0) * 0.12;
		float veil = mix(1.0, 0.35, cloud);
		col += moon_color * moon_brightness * (disc * veil + halo * moon_haze);
		// Moonlit cloud edges.
		col += moon_color * cloud * pow(max(c, 0.0), 6.0) * 0.08;
	}

	// Ashmounts on the horizon.
	float az = atan(d.x, d.z);
	float prof = mountain_profile(az);
	if (h < prof && h > -0.2) {
		col = mountain_color;
	}
	col += crater_glow * crater_strength * crater_light(az, h) * 0.25;

	if (h < 0.0) {
		col = mix(col, vec3(0.008, 0.007, 0.008), smoothstep(0.0, -0.25, h));
	}
	COLOR = col;
}
