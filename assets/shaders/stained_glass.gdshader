shader_type spatial;
render_mode unshaded, cull_back;
// Procedural leaded stained glass: a rectangular came (lead) lattice with a
// diagonal tracery accent, each pane tinted from a small fixed palette
// (hashed per-cell) and blended along a top-to-bottom colour gradient, with
// a warm emissive core so the panel reads as backlit glass rather than a
// flat coloured quad.

uniform vec4 color_a : source_color = vec4(0.55, 0.12, 0.14, 1.0);
uniform vec4 color_b : source_color = vec4(0.14, 0.28, 0.55, 1.0);
uniform vec4 color_c : source_color = vec4(0.55, 0.42, 0.10, 1.0);
uniform vec4 color_d : source_color = vec4(0.16, 0.4, 0.24, 1.0);
uniform vec4 lead_color : source_color = vec4(0.03, 0.03, 0.035, 1.0);
uniform float grid_x = 4.0;
uniform float grid_y = 7.0;
uniform float lead_width = 0.05;
uniform float emission_strength = 2.4;
uniform float twinkle_speed = 0.15;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 cell = uv * vec2(grid_x, grid_y);
	vec2 cell_id = floor(cell);
	vec2 cell_f = fract(cell);

	// Rectangular came lines.
	float lead = 0.0;
	lead = max(lead, step(cell_f.x, lead_width) + step(1.0 - lead_width, cell_f.x));
	lead = max(lead, step(cell_f.y, lead_width) + step(1.0 - lead_width, cell_f.y));
	// Diagonal tracery accent through the middle of each pane (gothic quatrefoil feel).
	float diag = abs(cell_f.x - cell_f.y);
	float diag2 = abs(cell_f.x + cell_f.y - 1.0);
	lead = max(lead, 1.0 - smoothstep(0.0, lead_width * 0.6, min(diag, diag2)));
	lead = clamp(lead, 0.0, 1.0);

	// Per-pane colour, picked from a small fixed palette by a cell hash.
	float h = hash21(cell_id);
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
	// A gentle warm-to-cool gradient down the whole window (top = cool
	// moonlit sky glimpsed through glass, bottom = warm hall-side glow).
	vec3 grad = mix(vec3(1.05, 0.95, 0.8), vec3(0.85, 0.95, 1.1), uv.y);
	vec3 pane_color = base.rgb * grad;

	// Subtle per-pane twinkle so the ballroom feels alive without being noisy.
	float twinkle = 0.9 + 0.1 * sin(TIME * twinkle_speed * 6.283 + h * 40.0);

	vec3 glass_emission = pane_color * emission_strength * twinkle;
	vec3 final_color = mix(glass_emission, lead_color.rgb, lead);

	ALBEDO = mix(pane_color * 0.4, lead_color.rgb, lead);
	EMISSION = mix(glass_emission, vec3(0.0), lead);
}
