shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform float brightness = 0.8;
uniform float seed = 3.0;

const vec3 LEAD = vec3(0.02, 0.02, 0.025);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 glass(float h) {
	if (h < 0.34) return vec3(0.08, 0.16, 0.72);
	if (h < 0.56) return vec3(0.72, 0.06, 0.08);
	if (h < 0.68) return vec3(0.08, 0.45, 0.2);
	if (h < 0.8) return vec3(0.9, 0.58, 0.1);
	if (h < 0.92) return vec3(0.78, 0.78, 0.68);
	return vec3(0.42, 0.12, 0.5);
}

float line(float d, float w, float aa) {
	return smoothstep(w, w + aa, d);
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	if (r > 0.5) {
		discard;
	}
	float aa = max(fwidth(r) * 1.5, 0.002);
	float ang = (atan(p.y, p.x) + 3.14159265) / 6.2831853;
	float w = 0.006;
	vec3 col;
	float lead = 1.0;
	float id;
	if (r > 0.47) {
		col = LEAD;
		id = -1.0;
	} else if (r > 0.405) {
		float k = floor(ang * 32.0);
		id = k + 200.0;
		col = mod(k, 2.0) < 1.0 ? vec3(0.72, 0.06, 0.08) : vec3(0.82, 0.8, 0.66);
		float f = fract(ang * 32.0);
		lead = line(min(f, 1.0 - f) * r * 6.2831853 / 32.0 * 1.0, w * 0.6, aa);
		lead = min(lead, line(abs(r - 0.405), w, aa));
		lead = min(lead, line(abs(r - 0.47), w, aa));
	} else if (r > 0.16) {
		float petals = 12.0;
		float k = floor(ang * petals);
		float f = fract(ang * petals);
		float inner = r < 0.285 ? 0.0 : 1.0;
		id = k * 2.0 + inner;
		vec2 lobe_c = vec2(cos((k + 0.5) / petals * 6.2831853 - 3.14159265), sin((k + 0.5) / petals * 6.2831853 - 3.14159265)) * 0.33;
		float lobe = length(p - lobe_c);
		if (lobe < 0.055) {
			col = vec3(0.86, 0.74, 0.42);
			id += 50.0;
		} else {
			col = glass(hash12(vec2(id, seed)));
			if (mod(k, 2.0) < 1.0 && inner < 0.5) {
				col = vec3(0.1, 0.18, 0.62);
			}
		}
		lead = line(min(f, 1.0 - f) * r * 6.2831853 / petals, w, aa);
		lead = min(lead, line(abs(r - 0.285), w, aa));
		lead = min(lead, line(abs(r - 0.16), w, aa));
		lead = min(lead, line(abs(lobe - 0.055), w * 0.8, aa));
	} else {
		float k = floor(ang * 4.0);
		id = k + 300.0;
		col = r < 0.06 ? vec3(0.9, 0.8, 0.5) : vec3(0.86, 0.74, 0.42) * (0.8 + 0.2 * mod(k, 2.0));
		float f = fract(ang * 4.0);
		lead = r < 0.06 ? 1.0 : line(min(f, 1.0 - f) * r * 6.2831853 / 4.0, w, aa);
		lead = min(lead, line(abs(r - 0.06), w, aa));
	}
	float shade = 0.75 + 0.4 * hash12(vec2(id, seed + 9.0));
	shade *= 0.88 + 0.12 * sin(p.y * 60.0 + p.x * 14.0 + id);
	ALBEDO = mix(LEAD, col * shade * brightness, lead);
}
