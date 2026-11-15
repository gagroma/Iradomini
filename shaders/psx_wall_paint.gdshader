shader_type spatial;
render_mode specular_disabled;

// PSX STONE WALL WITH OLD WALL PAINTING (the church walls, columns, plinths).
// The same vertex wobble as psx.gdshader. The surface is made here instead
// of from a texture, but still in pixels (TEXEL per metre) to keep the PS1 look.
//
// The stone: dressed limestone blocks (ashlar) laid in courses, every
// course shifted, some blocks long and some short, each block its own shade,
// pitted, chipped at the edges, in recessed mortar joints. The joints and
// block edges bend the normal, so a passing candle picks out the relief.
// Age: damp and dirt creeping up from the floor, water stains running down,
// soot darkening the stone high up.
//
// The painting (paint_bands = 1): up to the zigzag band the wall is
// plastered and painted, as medieval church walls were: a painted curtain
// with gold rosettes and a scalloped hem, an ochre band with a red zigzag,
// and a starry frieze high up. The paint has flaked off in places and shows
// the pale plaster under it; here and there the plaster has fallen too.

uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 snap_res = vec2(3840.0, 2160.0);
uniform float paint_bands = 1.0;            // 0 = bare stone (columns, plinths)
uniform float frieze_y = 5.72;              // centre of the star frieze (above the windows)
uniform float dado_bottom = 0.26;           // where the painted curtain starts (above the plinth)

const float TEXEL = 40.0;                   // pixels per metre
const float COURSE = 0.31;                  // height of a course of stones
const float BLOCK = 0.64;                   // usual length of a stone
const float JOINT = 0.022;                  // mortar joint
const vec3 STONE_A = vec3(0.46, 0.43, 0.39);
const vec3 STONE_B = vec3(0.39, 0.39, 0.42);
const vec3 MORTAR = vec3(0.36, 0.34, 0.3);
const vec3 PLASTER = vec3(0.64, 0.58, 0.48);

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (clip.w > 0.01) {
		vec2 ndc = clip.xy / clip.w;
		ndc = floor(ndc * snap_res + 0.5) / snap_res;
		clip.xy = ndc * clip.w;
	}
	POSITION = clip;
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

// Ashlar at point q (metres along the wall, metres up).
// Returns the colour; bump gets the slope of the surface (for the normal).
vec3 masonry(vec2 q, out vec2 bump) {
	float course = floor(q.y / COURSE);
	float fy = fract(q.y / COURSE);
	float bx = (q.x + hash12(vec2(course, 3.0)) * BLOCK) / BLOCK;
	float block = floor(bx);
	float fx = fract(bx);
	// some joints are left out: a long stone
	float merged = hash12(vec2(course, block)) < 0.28 ? 1.0 : 0.0;
	vec2 id = vec2(course, block - merged);
	float jx = JOINT / BLOCK;
	float jy = JOINT / COURSE;
	bool joint = fy < jy || (fx < jx && merged < 0.5);
	bump = vec2(0.0);
	if (joint) {
		vec3 m = MORTAR * (0.8 + 0.3 * vnoise(q * 70.0));
		return m * 0.72;                                    // recessed, in shadow
	}
	float h1 = hash12(id + 7.0);
	float h2 = hash12(id + 19.0);
	vec3 c = mix(STONE_A, STONE_B, h2) * (0.78 + 0.34 * h1);
	// tooling and pits
	float pit = vnoise(q * 18.0 + id * 3.1) * 0.65 + vnoise(q * 45.0) * 0.35;
	c *= 0.86 + 0.22 * pit;
	if (pit < 0.2) {
		c *= 0.7;                                           // a deep pit
	}
	// worn, rounded block edges: lit on top, shaded underneath
	float top = smoothstep(0.86, 1.0, fy);
	float bottom = 1.0 - smoothstep(jy, jy + 0.1, fy);
	float left = merged > 0.5 ? 0.0 : 1.0 - smoothstep(jx, jx + 0.05, fx);
	float right = smoothstep(0.95, 1.0, fx) * (hash12(vec2(course, block + 1.0)) < 0.28 ? 0.0 : 1.0);
	c *= 1.0 + 0.12 * top - 0.25 * bottom - 0.15 * left - 0.08 * right;
	bump = vec2(right - left, top - bottom) * 0.6 + (vec2(vnoise(q * 50.0 + 3.0), vnoise(q * 50.0 + 9.0)) - 0.5) * 0.35;
	// chipped corners
	float corner = min(min(fx, 1.0 - fx) * BLOCK, min(fy, 1.0 - fy) * COURSE);
	if (corner < 0.05 && vnoise(q * 30.0 + id) > 0.66) {
		c *= 0.62;
	}
	return c;
}

vec3 wall_paint(float along, float y, out bool painted) {
	painted = true;
	float hem = 1.22 - 0.045 * abs(sin(along * 3.14159 / 0.36));
	if (y > dado_bottom && y < hem) {
		float fold = 0.68 + 0.32 * sin(along * 6.2832 / 0.18 + sin(along * 1.7) * 0.8);
		vec3 p = vec3(0.4, 0.09, 0.08) * fold;
		vec2 g = vec2(fract(along / 0.36) - 0.5, fract((y - 0.2) / 0.32) - 0.5) * vec2(0.36, 0.32);
		if (length(g) < 0.024) {
			p = vec3(0.68, 0.5, 0.2);
		}
		return p;
	}
	if (y >= 1.24 && y < 1.4) {
		float t = abs(fract(along / 0.16) - 0.5) * 2.0;
		vec3 p = abs(y - (1.27 + t * 0.1)) < 0.02 ? vec3(0.42, 0.09, 0.07) : vec3(0.6, 0.43, 0.19);
		if (y < 1.255 || y > 1.385) {
			p = vec3(0.1, 0.07, 0.05);
		}
		return p;
	}
	if (abs(y - frieze_y) < 0.25) {
		vec3 p = vec3(0.06, 0.08, 0.22);
		vec2 s = abs(vec2(fract(along / 0.4) - 0.5, (y - frieze_y) / 0.4) * 0.4);
		if (s.x + s.y < 0.045 || (s.x < 0.01 && s.y < 0.06) || (s.y < 0.01 && s.x < 0.06)) {
			p = vec3(0.72, 0.55, 0.2);
		}
		if (abs(y - frieze_y) > 0.22) {
			p = vec3(0.5, 0.36, 0.14);
		}
		return p;
	}
	painted = false;
	return vec3(0.0);
}

void fragment() {
	vec3 n = abs(normalize(world_nrm));
	float along;
	float y = world_pos.y;
	vec3 t_axis;
	bool upright = true;
	if (n.x > n.y && n.x > n.z) {
		along = world_pos.z;
		t_axis = vec3(0.0, 0.0, 1.0);
	} else if (n.z > n.y) {
		along = world_pos.x;
		t_axis = vec3(1.0, 0.0, 0.0);
	} else {
		// tops of walls, columns, tables
		upright = false;
		along = world_pos.x;
		y = world_pos.z;
		t_axis = vec3(1.0, 0.0, 0.0);
	}
	// work in whole pixels, like a small texture would
	vec2 q = (floor(vec2(along, y) * TEXEL) + 0.5) / TEXEL;
	vec2 bump;
	vec3 c = masonry(q, bump);

	if (upright) {
		bool painted = false;
		vec3 paint = vec3(0.0);
		if (paint_bands > 0.5) {
			paint = wall_paint(q.x, q.y, painted);
		}
		if (painted) {
			// paint on plaster; where it flaked off the plaster shows, and
			// where the plaster fell the stone does
			float f = vnoise(q * vec2(4.0, 5.0)) * 0.55 + vnoise(q * 13.0) * 0.3 + vnoise(q * 40.0) * 0.15;
			vec3 plaster = PLASTER * (0.85 + 0.25 * vnoise(q * 30.0));
			if (f > 0.86) {
				// stone (keep it)
			} else if (f > 0.71) {
				c = plaster * (f < 0.73 ? 0.75 : 1.0);   // a thin dark lip at the edge of the paint
				bump *= 0.2;
			} else {
				c = mix(paint, plaster, 0.12) * (0.88 + 0.2 * vnoise(q * 25.0));
				bump *= 0.1;
			}
		}
		// damp and dirt rising from the floor
		float damp = 1.0 - smoothstep(0.0, 0.85 + 0.25 * vnoise(vec2(q.x * 2.0, 0.0)), y);
		c *= 1.0 - 0.38 * damp;
		// water stains running down
		float streak = smoothstep(0.62, 0.9, vnoise(vec2(q.x * 7.0, y * 0.35)));
		c *= 1.0 - 0.2 * streak * smoothstep(0.5, 2.5, y);
		// soot high up
		c *= 1.0 - 0.3 * smoothstep(3.0, 6.5, y);
	}
	ALBEDO = c * tint.rgb;
	vec3 up = upright ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0);
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * (t_axis * bump.x + up * bump.y) * 0.5);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
