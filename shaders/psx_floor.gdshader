shader_type spatial;
render_mode specular_schlick_ggx;

// PSX CATHEDRAL FLOOR.
// The same PS1 vertex wobble as the walls; the stone is drawn here in pixels
// (TEXEL per metre), in world space, so floors of neighbouring rooms meet.
//
// Styles (one per room, set by level.gd):
//   0 limestone flags - big slabs laid in staggered rows (nave, narthex)
//   1 marble chequer  - dark and grey marble squares (crossing)
//   2 terracotta      - small worn clay tiles (chapels)
//   3 marble lozenges - red and grey marble set diagonally (apse)
// Extras:
//   aisle_half > 0    - a marble runner down the middle of the nave
//   ledgers           - grave slabs in the side aisles (dark polished stone,
//                       a carved border, a cross, worn lines of inscription)
//   radius > 0        - the great Cosmatesque roundel (crossing)
// Every slab is its own shade and tilts a hair (old floors settle), so a
// candle's reflection skips from slab to slab. Marble is polished, and the
// path people walked is worn smooth and shiny. Grime sits in the joints;
// corners are chipped; some slabs are cracked.
// The floor stays darker than chalk, so circles always read.

uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 snap_res = vec2(160.0, 90.0);
uniform int style = 0;
uniform float aisle_half = 0.0;
uniform bool ledgers = false;
uniform float ledger_min_x = 4.95;          // |x| beyond which grave slabs may lie
uniform vec2 centre = vec2(0.0, 0.0);
uniform float radius = 0.0;

const float TEXEL = 40.0;
const vec3 GRIME = vec3(0.09, 0.085, 0.08);
const vec3 PORPHYRY = vec3(0.42, 0.09, 0.11);
const vec3 SERPENTINE = vec3(0.12, 0.3, 0.18);
const vec3 MARBLE = vec3(0.62, 0.6, 0.56);
const vec3 GIALLO = vec3(0.6, 0.46, 0.22);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 3.7) * 0.3 + vnoise(p * 4.3 + 9.1) * 0.15;
}

// Marble: cloudy body with thin veins.
vec3 marble(vec2 q, vec3 body, vec3 vein, float seed) {
	float w = fbm(q * 2.2 + seed);
	vec3 c = body * (0.82 + 0.3 * w);
	float v = abs(sin((q.x * 0.8 + q.y * 1.4 + seed) * 5.0 + fbm(q * 3.0 + seed) * 5.0));
	if (v < 0.07) {
		c = mix(c, vein, 0.75);
	} else if (v < 0.16) {
		c = mix(c, vein, 0.25);
	}
	return c;
}

// The result of one stone: colour, how polished, how far from a joint (m),
// a tilt for the normal, and an id.
struct Stone {
	vec3 col;
	float polish;
	float edge;
	vec2 tilt;
	vec2 id;
};

Stone limestone(vec2 q) {
	Stone s;
	float row = floor(q.y / 0.62);
	float fy = fract(q.y / 0.62);
	float len = 0.95;
	float bx = (q.x + hash12(vec2(row, 1.0)) * len) / len;
	float col = floor(bx);
	float fx = fract(bx);
	s.id = vec2(row, col);
	float h = hash12(s.id);
	float h2 = hash12(s.id + 5.0);
	s.col = mix(vec3(0.4, 0.38, 0.35), vec3(0.34, 0.34, 0.35), h2) * (0.82 + 0.3 * h);
	// fossils and grain
	float g = vnoise(q * 30.0 + h * 10.0);
	s.col *= 0.9 + 0.18 * g;
	if (vnoise(q * 9.0 + s.id) > 0.82) {
		s.col *= 0.85;                                 // a stain soaked in
	}
	s.edge = min(min(fx, 1.0 - fx) * len, min(fy, 1.0 - fy) * 0.62);
	s.polish = 0.12;
	s.tilt = (vec2(h, h2) - 0.5) * 0.12;
	// cracked slabs
	if (hash12(s.id + 11.0) < 0.14) {
		vec2 local = vec2(fx * len, fy * 0.62) - vec2(len, 0.62) * 0.5;
		float ang = hash12(s.id + 12.0) * 3.14159;
		float d = abs(dot(local, vec2(cos(ang), sin(ang))) + (vnoise(local * 18.0 + s.id) - 0.5) * 0.06);
		if (d < 0.006) {
			s.col = GRIME;
		}
	}
	return s;
}

Stone chequer(vec2 q, float size, vec3 dark, vec3 light, float diagonal) {
	Stone s;
	vec2 r = q;
	if (diagonal > 0.5) {
		r = vec2(q.x + q.y, q.y - q.x) * 0.7071;
	}
	vec2 cell = floor(r / size);
	vec2 f = fract(r / size);
	s.id = cell;
	bool dk = mod(cell.x + cell.y, 2.0) < 1.0;
	s.col = dk ? marble(q, dark, dark * 2.4, cell.x * 3.1 + cell.y) : marble(q, light, light * 0.55, cell.x + cell.y * 2.7);
	s.col *= 0.9 + 0.2 * hash12(cell + 2.0);
	s.edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * size;
	s.polish = 0.6;
	s.tilt = (vec2(hash12(cell + 7.0), hash12(cell + 8.0)) - 0.5) * 0.08;
	return s;
}

Stone terracotta(vec2 q) {
	Stone s;
	float size = 0.22;
	vec2 cell = floor(q / size);
	vec2 f = fract(q / size);
	s.id = cell;
	float h = hash12(cell);
	s.col = mix(vec3(0.42, 0.19, 0.11), vec3(0.36, 0.22, 0.14), hash12(cell + 3.0)) * (0.78 + 0.35 * h);
	s.col *= 0.85 + 0.25 * vnoise(q * 40.0);
	s.edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * size;
	// a broken corner here and there
	if (h < 0.12 && length(f - vec2(1.0, 0.0)) < 0.35) {
		s.col = GRIME * 1.3;
	}
	s.polish = 0.2;
	s.tilt = (vec2(h, hash12(cell + 4.0)) - 0.5) * 0.18;
	return s;
}

// a grave slab set into the floor; true if q is on one
bool ledger(vec2 q, out Stone s) {
	vec2 cell = floor(q / vec2(1.3, 2.4));
	if (hash12(cell + 40.0) > 0.38) {
		return false;
	}
	vec2 c = (cell + 0.5) * vec2(1.3, 2.4);
	if (abs(c.x) < ledger_min_x) {
		return false;
	}
	vec2 l = q - c;
	vec2 half_size = vec2(0.46, 0.96);
	if (abs(l.x) > half_size.x || abs(l.y) > half_size.y) {
		return false;
	}
	float h = hash12(cell + 41.0);
	s.id = cell + 100.0;
	s.col = marble(q, vec3(0.16, 0.16, 0.17) * (0.85 + 0.3 * h), vec3(0.3, 0.3, 0.32), h * 9.0);
	s.edge = min(half_size.x - abs(l.x), half_size.y - abs(l.y));
	s.polish = 0.75;
	s.tilt = (vec2(h, hash12(cell + 42.0)) - 0.5) * 0.06;
	float wear = vnoise(q * 3.0 + h * 7.0);              // feet have rubbed the carving away in places
	bool carved = false;
	// carved border
	if (abs(s.edge - 0.06) < 0.008) {
		carved = true;
	}
	// a cross in the upper part (the head end faces the altar: -z)
	vec2 cr = l - vec2(0.0, -0.5);
	if ((abs(cr.x) < 0.015 && abs(cr.y) < 0.2) || (abs(cr.y + 0.06) < 0.015 && abs(cr.x) < 0.12)) {
		carved = true;
	}
	// lines of inscription: words as dashes
	if (l.y > -0.18 && l.y < 0.7 && abs(l.x) < 0.33) {
		float line = floor((l.y + 0.18) / 0.075);
		float in_line = fract((l.y + 0.18) / 0.075);
		float word = floor((l.x + 0.33) / 0.05 + hash12(vec2(line, h)) * 3.0);
		if (in_line > 0.35 && in_line < 0.65 && hash12(vec2(word, line + h * 13.0)) > 0.3 && mod(floor((l.x + 0.33) / 0.0125), 4.0) < 3.0) {
			carved = true;
		}
	}
	if (carved && wear > 0.3) {
		s.col *= 0.45;
	}
	return true;
}

vec3 tri_cells(vec2 cell, vec2 f, float set) {
	bool upper = f.x + f.y > 1.0;
	float h = hash12(cell + (upper ? 7.0 : 0.0) + set);
	vec3 c = h < 0.4 ? PORPHYRY : (h < 0.75 ? SERPENTINE : MARBLE);
	if (mod(cell.x + cell.y, 2.0) < 1.0 && upper) {
		c = MARBLE;
	}
	return c;
}

// The Cosmatesque roundel; true if q is on it.
bool inlay(vec2 q, out Stone s) {
	vec2 p = q - centre;
	if (radius <= 0.0 || max(abs(p.x), abs(p.y)) > radius * 1.06) {
		return false;
	}
	float r = length(p) / radius;
	float a = atan(p.y, p.x);
	vec3 c;
	float seam = 1.0;
	if (r < 0.3) {
		c = marble(q, PORPHYRY, vec3(0.6, 0.3, 0.3), 3.0);
	} else if (r < 0.34) {
		c = MARBLE;
	} else if (r < 0.62) {
		float u = (a + 3.14159) / 6.28318 * 40.0;
		float v = (r - 0.34) / 0.28 * 3.0;
		c = tri_cells(floor(vec2(u, v)), fract(vec2(u, v)), 1.0);
		vec2 f = fract(vec2(u, v));
		seam = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	} else if (r < 0.66) {
		c = MARBLE;
	} else if (r < 0.9) {
		float k = floor((a + 3.14159) / 6.28318 * 16.0);
		c = mod(k, 2.0) < 1.0 ? marble(q, PORPHYRY, vec3(0.6, 0.3, 0.3), k) : marble(q, SERPENTINE, vec3(0.4, 0.6, 0.45), k);
		float f = fract((a + 3.14159) / 6.28318 * 16.0);
		if (f < 0.04 || f > 0.96) {
			c = MARBLE;
		}
	} else if (r < 0.95) {
		c = GIALLO;
	} else if (r < 1.0) {
		c = MARBLE;
	} else if (max(abs(p.x), abs(p.y)) > radius * 1.02) {
		c = MARBLE;
	} else {
		vec2 qq = p / (radius * 0.1);
		c = tri_cells(floor(qq), fract(qq), 5.0);
		vec2 f = fract(qq);
		seam = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	}
	c *= 0.85 + 0.2 * vnoise(q * 25.0);
	c *= mix(0.55, 1.0, smoothstep(0.0, 0.08, seam));
	s.col = c;
	s.edge = 1.0;
	s.polish = 0.65;
	s.tilt = vec2(0.0);
	s.id = vec2(-7.0);
	return true;
}

void fragment() {
	vec2 q = (floor(world_pos.xz * TEXEL) + 0.5) / TEXEL;
	Stone s;
	bool special = inlay(q, s);
	if (!special && ledgers) {
		special = ledger(q, s);
	}
	if (!special && aisle_half > 0.0 && abs(q.x) < aisle_half) {
		// the marble runner down the nave
		float bx = aisle_half - abs(q.x);
		if (bx < 0.14) {
			s.col = bx < 0.03 || bx > 0.11 ? marble(q, MARBLE * 0.75, MARBLE * 0.4, 2.0) : marble(q, PORPHYRY * 0.8, vec3(0.5, 0.25, 0.25), 4.0);
			s.edge = bx < 0.03 ? min(bx, 0.03 - bx) : (bx > 0.11 ? min(bx - 0.11, 0.14 - bx) : min(bx - 0.03, 0.11 - bx));
			s.polish = 0.6;
			s.tilt = vec2(0.0);
			s.id = vec2(-3.0, floor(q.y));
		} else {
			s = chequer(q, 0.36, vec3(0.13, 0.17, 0.15), vec3(0.4, 0.39, 0.36), 1.0);
		}
		special = true;
	}
	if (!special) {
		if (style == 1) {
			s = chequer(q, 0.6, vec3(0.12, 0.14, 0.13), vec3(0.31, 0.3, 0.29), 0.0);
		} else if (style == 2) {
			s = terracotta(q);
		} else if (style == 3) {
			s = chequer(q, 0.45, vec3(0.2, 0.05, 0.05), vec3(0.26, 0.25, 0.24), 1.0);
		} else {
			s = limestone(q);
		}
	}
	vec3 c = s.col;
	// joints: grime-filled, the stone edge worn round
	float joint = smoothstep(0.004, 0.012, s.edge);
	c = mix(GRIME, c, joint);
	if (s.edge < 0.035 && s.edge > 0.008 && vnoise(q * 22.0 + s.id) > 0.72) {
		c *= 0.72;                                       // chipped edge
	}
	// dirt and dust: blotches, darker where nobody walks
	float walk = aisle_half > 0.0 ? exp(-pow(q.x / 1.6, 2.0)) : 0.3;
	float dirt = fbm(q * 0.7 + 40.0);
	c *= 1.0 - 0.22 * smoothstep(0.45, 0.85, dirt) * (1.0 - walk);
	c = mix(c, vec3(0.3, 0.29, 0.27), 0.12 * smoothstep(0.6, 0.9, fbm(q * 1.7 + 70.0)));   // dust
	float polish = clamp(s.polish + 0.3 * walk * (1.0 - dirt), 0.0, 1.0) * joint;
	ALBEDO = c * tint.rgb;
	ROUGHNESS = mix(0.95, 0.22, polish);
	SPECULAR = mix(0.2, 0.6, polish);
	METALLIC = 0.0;
	// slabs that have settled unevenly; joints sunk
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(s.tilt.x, 0.0, s.tilt.y) * joint);
}
