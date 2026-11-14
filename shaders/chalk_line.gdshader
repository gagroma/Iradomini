shader_type spatial;
render_mode unshaded, cull_disabled;

// CHALK LINE - how chalk really looks on a stone floor.
// chalk.gd builds each line as a ribbon on the floor:
//   UV.x    = metres along the line (from where it was started)
//   UV.y    = 0..1 across the ribbon (the ribbon is wider than the line,
//             to leave room for ragged edges and dust)
//   COLOR.r = pressure of the hand (0..1)
// What is copied from real chalk:
//  - the stick only touches the high points of the stone, so the line is a
//    dry, broken texture: solid in the middle, crumbling towards the edges;
//    that grain belongs to the FLOOR, so it stays put as you look around;
//  - the worn face of the stick leaves streaks along the stroke;
//  - the edges are ragged, each side differently;
//  - light pressure leaves a thinner, patchier line;
//  - a little loose dust lies along the line.
// Pixels are either chalk or not (no blending), which suits the PSX look.

uniform vec4 color : source_color = vec4(0.95, 0.9, 0.74, 1.0);
uniform float fade : hint_range(0.0, 1.0) = 0.0;   // 1 = rubbed away
uniform float seed = 0.0;
uniform float burn_front = -1.0;                  // title screen only
uniform vec2 burn_origin = vec2(0.0);

const float EDGE = 0.62;    // |across| where the line nominally ends

varying vec3 wpos;

// Pulled a little towards the camera so the wobbling (PSX-snapped) floor
// cannot swallow the line far away; see decor.gdshader.
const float PULL = 0.004;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// the wall's depth error grows as 1/sin of the viewing angle, so the pull does too
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);   // the ribbon has no normals: it lies flat
	float facing = max(abs(dot(normalize(v.xyz), vn)), 0.15);
	v.xyz *= 1.0 - PULL / facing;
	POSITION = PROJECTION_MATRIX * v;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
	           mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float s = UV.x;
	float across = UV.y * 2.0 - 1.0;
	float side = across > 0.0 ? 1.0 : 0.0;
	float d = abs(across) / EDGE;                  // 1 = nominal edge of the line
	float pressure = COLOR.r;

	// ragged edges, a different tear on each side
	float tear = vnoise(vec2(s * 34.0, side * 7.0 + seed)) * 0.6
	           + vnoise(vec2(s * 95.0, side * 13.0 + seed * 2.0)) * 0.4;
	float edge = 0.72 + 0.36 * tear;

	// the floor's grain: chalk catches on the bumps of the stone
	float grain = vnoise(wpos.xz * 95.0) * 0.6 + vnoise(wpos.xz * 31.0 + 5.3) * 0.4;
	// streaks along the stroke from the stick's worn face
	float streak = vnoise(vec2(s * 5.0, across * 7.0 + seed * 3.1));

	float need = smoothstep(0.1, 1.0, d / edge) * 0.75
	           + (1.0 - pressure) * 0.3
	           + (streak - 0.5) * 0.55
	           + fade * 1.1;
	float chalk = (d < edge && grain > need) ? 1.0 : 0.0;

	// loose dust just outside the line
	float dust_n = vnoise(wpos.xz * 140.0 + 11.0);
	float dust = (d < 1.55 && dust_n > 0.84 + 0.12 * smoothstep(0.9, 1.55, d) + fade) ? 1.0 : 0.0;

	if (chalk < 0.5 && dust < 0.5) {
		discard;
	}
	float tone = 0.7 + 0.4 * grain + 0.12 * (streak - 0.5);
	if (chalk < 0.5) {
		tone *= 0.75;                               // dust is thinner, a bit darker
	}
	ALBEDO = color.rgb * tone;

	if (burn_front > -0.09) {
		// Two ember fronts travel from the near edge and meet at the back.
		vec2 offset = wpos.xz - burn_origin;
		float angle = abs(atan(offset.x, offset.y)) / PI;
		float distance_to_front = angle - burn_front;
		distance_to_front += (grain - 0.5) * 0.045;
		if (distance_to_front < 0.0) {
			discard;
		}
		float heat = 1.0 - smoothstep(0.015, 0.105, distance_to_front);
		vec3 ember = mix(vec3(0.56, 0.07, 0.014), vec3(1.0, 0.62, 0.20), grain);
		ALBEDO = mix(ALBEDO, ember, heat);
		EMISSION = ember * heat * 0.65;
	}
}
