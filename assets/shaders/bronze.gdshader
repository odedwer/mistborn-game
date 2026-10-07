shader_type spatial;
// Weathered statuary bronze (WorldMaterials.Mat.BRONZE). The verdigris is not
// a random mottle: it gathers where weathering puts it on a real statue.
//  - Recesses: the mesh's vertex colour darkens folds, the waist, under the
//    arms, the eye sockets and the mouth (1 = open surface), and the patina
//    builds up there.
//  - Ledges: faces turned up (shoulders, the head, the base plate, the
//    banner's top edge) hold rainwater and go green.
//  - Runs: on the upright faces it streaks downward from the shoulders, the
//    belt and the head, fading towards the hem. Each run (see `runs`) has its
//    own width (1-5 cm), length and place, with gaps between some, and
//    narrows as it fades; the streak noise breaks it up along its length.
// Works in model space, so each statue weathers the same way relative to its
// own folds; the instance position only offsets the runs, so no two match.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 metal_color : source_color = vec3(0.3, 0.225, 0.15);
uniform vec3 patina_color : source_color = vec3(0.25, 0.34, 0.29);
uniform sampler2D streaks : filter_linear_mipmap, repeat_enable;
uniform sampler2D mottle : filter_linear_mipmap, repeat_enable;
uniform float rim_amount = 0.25;

varying vec3 lp;
varying vec3 ln;
varying flat float seed;  // (flat: the run hashes amplify interpolation noise)

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	vec2 o = MODEL_MATRIX[3].xz;
	seed = fract(sin(dot(o, vec2(12.9898, 78.233))) * 43758.5453);
}

float hash1(float x) {
	// (no sin of large arguments: its precision varies between GPUs)
	x = fract(x * 0.1031);
	x *= x + 33.33;
	x *= x + x;
	return fract(x);
}

// How far down a run of relative length `len` reaches below the ledges water
// runs off (the shoulders, the belt, the chin), strongest just under each.
float drip(float y, float len) {
	float d = max(max(
			exp(-max(1.5 - y, 0.0) / (0.5 * len)) * step(y, 1.56),
			0.8 * exp(-max(1.15 - y, 0.0) / (0.35 * len)) * step(y, 1.2)),
			0.7 * exp(-max(1.74 - y, 0.0) / (0.12 * len)) * step(y, 1.76));
	return max(d, 0.15);
}

// Verdigris runs across `u` (m along an upright face) at height `y`: one
// candidate run per 11 cm cell, a quarter of them missing, each placed,
// sized and lengthened by its own hash, so neither spacing nor width repeats.
float runs(float u, float y, float sd) {
	const float CW = 0.11;
	float ci = floor(u / CW);
	float best = 0.0;
	for (int k = -1; k <= 1; k++) {
		float c = ci + float(k) + floor(sd * 997.0);
		if (hash1(c) < 0.25) {
			continue;
		}
		float centre = (ci + float(k) + 0.1 + 0.8 * hash1(c + 17.3)) * CW;
		float h = hash1(c + 41.9);
		float w = mix(0.012, 0.05, h * h);
		float d = drip(y, mix(0.45, 2.0, hash1(c + 73.1)));
		float we = w * (0.45 + 0.55 * d);  // narrower where it fades
		float amp = mix(0.7, 1.0, hash1(c + 5.7));
		best = max(best, (1.0 - smoothstep(we * 0.3, we, abs(u - centre))) * sqrt(d) * amp);
	}
	return best;
}

void fragment() {
	vec3 n = normalize(ln);
	float cavity = smoothstep(0.86, 0.62, COLOR.r);
	float ledge = smoothstep(0.45, 0.9, n.y);
	// Runs, projected on the two upright planes and blended by the normal.
	vec2 wv = abs(n.xz) + 0.001;
	wv /= wv.x + wv.y;
	float y = lp.y;
	float wob = 0.012 * sin(y * 9.0 + (lp.x + lp.z) * 5.0);
	float r = runs(lp.z + wob + seed * 3.1, y, seed) * wv.x + runs(lp.x + wob + seed * 1.7, y, seed + 0.5) * wv.y;
	// (the streak noise breaks each run up along its length)
	float v = y * 0.34 + seed * 5.0;
	float s = texture(streaks, vec2(lp.z * 2.2 + seed, v)).r * wv.x
			+ texture(streaks, vec2(lp.x * 2.2 + seed * 1.7, v + 0.37)).r * wv.y;
	float run = r * (0.7 + 0.3 * smoothstep(0.3, 0.7, s)) * (1.0 - ledge);
	float m = max(max(cavity, ledge * 0.85), run * 0.9);
	// A fine grain so the areas between aren't flat.
	float f = texture(mottle, vec2(lp.x + lp.z, lp.y) * 1.6 + seed).r;
	m = clamp(m * (0.6 + 0.8 * f), 0.0, 1.0);
	vec3 bronze = metal_color * (0.82 + 0.36 * f);
	ALBEDO = mix(bronze, patina_color * (0.9 + 0.2 * f), m) * COLOR.rgb;
	ROUGHNESS = mix(0.45, 0.88, m);
	METALLIC = 0.35 * (1.0 - 0.6 * m);
	SPECULAR = 0.5;
	// A faint rim along the silhouette picks the figure out of a dark street.
	RIM = rim_amount;
	RIM_TINT = 0.6;
}
