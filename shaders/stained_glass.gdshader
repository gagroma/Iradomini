shader_type spatial;
render_mode unshaded, cull_disabled;

// STAINED GLASS - a tall pointed (lancet) window in the nave wall, moonlight
// coming through it. Made in code, Gothic in style: a column of round
// medallions cut into coloured pieces, a lattice of diamond panes around
// them, and a border, all held by dark lead. Glass is never even: each pane
// has its own shade and streaks.

uniform vec2 size = vec2(1.0, 2.6);       // metres
uniform float brightness = 0.85;
uniform float seed = 0.0;

const vec3 LEAD = vec3(0.02, 0.02, 0.025);

// Pulled a little towards the camera so the wobbling (PSX-snapped) wall
// behind cannot cut into it; see decor.gdshader.
const float PULL = 0.0045;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// the wall's depth error grows as 1/sin of the viewing angle, so the pull does too
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float facing = max(abs(dot(normalize(v.xyz), vn)), 0.15);
	v.xyz *= 1.0 - PULL / facing;
	POSITION = PROJECTION_MATRIX * v;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 glass(float h) {
	// the medieval palette: deep blue, ruby, emerald, amber, white, purple
	if (h < 0.34) return vec3(0.08, 0.16, 0.72);
	if (h < 0.56) return vec3(0.72, 0.06, 0.08);
	if (h < 0.68) return vec3(0.08, 0.45, 0.2);
	if (h < 0.8) return vec3(0.9, 0.58, 0.1);
	if (h < 0.92) return vec3(0.78, 0.78, 0.68);
	return vec3(0.42, 0.12, 0.5);
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * size.x, (1.0 - UV.y) * size.y);   // x across, y up from the sill
	float w = size.x;
	float spring = size.y - w * 0.866;
	// pointed arch: two arcs of radius w, centred on the opposite springers
	if (p.y > spring) {
		if (length(p - vec2(-w * 0.5, spring)) > w || length(p - vec2(w * 0.5, spring)) > w) {
			discard;
		}
	}
	float d_edge = min(w * 0.5 - abs(p.x), p.y);
	if (p.y > spring) {
		d_edge = min(w - length(p - vec2(-w * 0.5, spring)), w - length(p - vec2(w * 0.5, spring)));
	}
	vec3 col;
	float lead = 1.0;
	float id;
	if (d_edge < 0.03) {
		col = LEAD;                                       // the stone frame's shadow
		id = -1.0;
	} else if (d_edge < 0.09) {
		// border: short pieces of alternating colour
		float t = (p.y + abs(p.x) * 3.0) / 0.12;
		float k = floor(t);
		id = k + 100.0;
		col = mod(k, 2.0) < 1.0 ? vec3(0.72, 0.06, 0.08) : vec3(0.82, 0.8, 0.66);
		float f = fract(t);
		lead = smoothstep(0.03, 0.1, min(f, 1.0 - f));
		lead = min(lead, smoothstep(0.004, 0.012, abs(d_edge - 0.09)));
	} else {
		// medallions stacked up the window
		float pitch = w * 0.95;
		float my = (floor((p.y - 0.12) / pitch) + 0.5) * pitch + 0.12;
		vec2 m = vec2(p.x, p.y - my);
		float r = length(m);
		float mr = w * 0.33;
		if (r < mr && my < spring) {
			float ring = r < mr * 0.45 ? 0.0 : 1.0;
			float sector = floor((atan(m.y, m.x) + 3.14159) / 6.28318 * (ring > 0.5 ? 8.0 : 1.0));
			id = my * 13.0 + ring * 5.0 + sector;
			col = glass(hash12(vec2(id, seed)));
			if (ring < 0.5) {
				col = vec3(0.86, 0.74, 0.42);                 // golden centre
			}
			float l1 = abs(r - mr);
			float l2 = abs(r - mr * 0.45);
			float ang = fract((atan(m.y, m.x) + 3.14159) / 6.28318 * 8.0);
			float l3 = ring > 0.5 ? min(ang, 1.0 - ang) * r * 0.785 : 1.0;
			lead = smoothstep(0.008, 0.016, min(min(l1, l2), l3));
		} else {
			// diamond lattice around the medallions
			vec2 dq = vec2(p.x / 0.16 + p.y / 0.22, -p.x / 0.16 + p.y / 0.22);
			vec2 dc = floor(dq);
			vec2 df = fract(dq);
			id = dc.x * 31.0 + dc.y * 7.0;
			col = mod(dc.x + dc.y, 2.0) < 1.0 ? vec3(0.1, 0.18, 0.62) : vec3(0.55, 0.08, 0.1);
			if (hash12(dc + seed) > 0.85) {
				col = glass(hash12(dc + seed + 3.0));
			}
			float l = min(min(df.x, 1.0 - df.x), min(df.y, 1.0 - df.y));
			lead = smoothstep(0.03, 0.07, l);
			lead = min(lead, smoothstep(0.008, 0.016, abs(r - mr)));
		}
	}
	// uneven glass: each pane its own shade, with streaks
	float shade = 0.75 + 0.4 * hash12(vec2(id, seed + 9.0));
	shade *= 0.85 + 0.15 * sin(p.y * 90.0 + p.x * 20.0 + id);
	ALBEDO = mix(LEAD, col * shade * brightness, lead);
}
