shader_type spatial;
render_mode unshaded, cull_back;
// Procedural leaded stained glass: an irregular (Voronoi, not grid-square)
// leaded lattice arranged as a Gothic window -- a rose of concentric rings
// and radial spokes in the upper arch, tapering into narrow vertical lancet
// panes below -- tinted from a small, deliberately desaturated palette and
// blended along a top-to-bottom colour gradient, with a warm emissive core
// so the panel reads as backlit glass rather than a flat coloured checker.

uniform vec4 color_a : source_color = vec4(0.55, 0.12, 0.14, 1.0);
uniform vec4 color_b : source_color = vec4(0.14, 0.28, 0.55, 1.0);
uniform vec4 color_c : source_color = vec4(0.55, 0.42, 0.10, 1.0);
uniform vec4 color_d : source_color = vec4(0.16, 0.4, 0.24, 1.0);
uniform vec4 lead_color : source_color = vec4(0.03, 0.03, 0.035, 1.0);
uniform float lead_width = 0.16;
uniform float emission_strength = 1.5;
uniform float twinkle_speed = 0.15;
uniform float saturation = 0.55;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = hash21(p);
	float m = hash21(p + 17.13);
	return vec2(n, m);
}

// Jittered-grid Worley: returns (f1, f2, cell id) in the given cell space,
// so the leaded boundaries are irregular polygons, never straight grid
// squares -- this is what actually stops the window reading as a checker.
vec3 worley(vec2 p) {
	vec2 base = floor(p);
	float best1 = 8.0;
	float best2 = 8.0;
	vec2 best_id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = base + vec2(float(x), float(y));
			vec2 jitter = hash22(cell);
			vec2 pt = cell + 0.15 + jitter * 0.7;
			float d = length(pt - p);
			if (d < best1) {
				best2 = best1;
				best1 = d;
				best_id = cell;
			} else if (d < best2) {
				best2 = d;
			}
		}
	}
	return vec3(best1, best2, hash21(best_id));
}

void fragment() {
	vec2 uv = UV;

	// Warp into the window's own layout before feeding the Worley cells:
	// a circular rose in the upper arch, narrow vertical lancets below.
	vec2 rose_center = vec2(0.5, 0.8);
	vec2 d = uv - rose_center;
	float radius = length(d) / 0.32;
	vec2 cell_space;
	if (uv.y > 0.42 && radius < 1.15) {
		float ang = atan(d.y, d.x) / 6.28318 + 0.5;
		cell_space = vec2(ang * 10.0, radius * 4.5);
	} else {
		// Elongated lancet panes: few columns, several rows, each pane
		// stretched tall like real Gothic tracery.
		cell_space = vec2(uv.x * 6.0, uv.y * 3.2);
	}

	vec3 w = worley(cell_space);
	float gap = w.y - w.x;
	float lead = 1.0 - smoothstep(lead_width * 0.5, lead_width, gap);
	float h = w.z;

	vec4 base;
	if (h < 0.25) {
		base = color_a;
	} else if (h < 0.5) {
		base = color_b;
	} else if (h < 0.75) {
		base = color_c;
	} else {
		base = color_d;
	}
	// Desaturate the palette toward its own luminance -- authentic leaded
	// glass reads muted/antique, not primary-colour saturated.
	float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	vec3 muted = mix(vec3(lum), base.rgb, saturation);

	// A gentle warm-to-cool gradient down the whole window (top = cool
	// moonlit sky glimpsed through glass, bottom = warm hall-side glow).
	vec3 grad = mix(vec3(1.0, 0.92, 0.8), vec3(0.85, 0.92, 1.05), uv.y);
	vec3 pane_color = muted * grad;

	// Subtle per-pane twinkle so the ballroom feels alive without being noisy.
	float twinkle = 0.92 + 0.08 * sin(TIME * twinkle_speed * 6.283 + h * 40.0);

	vec3 glass_emission = pane_color * emission_strength * twinkle;

	ALBEDO = mix(pane_color * 0.35, lead_color.rgb, lead);
	EMISSION = mix(glass_emission, vec3(0.0), lead);
}
