shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float brightness = 1.0;
uniform vec3 flash_color : source_color = vec3(1.0, 0.5, 0.1);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 rim_color : source_color = vec3(0.55, 0.45, 0.9);
uniform float roughness = 0.62;
uniform float skin_detail = 0.0;
uniform bool linear_color = false;

varying vec3 obj_pos;
varying float metal;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	obj_pos = VERTEX;
	metal = UV.y;
	float n = noise3(VERTEX * 9.0);
	VERTEX += NORMAL * dissolve * n * 0.05;
	VERTEX.y += dissolve * dissolve * n * 0.4;
}

void fragment() {
	float n = noise3(obj_pos * 14.0) * 0.6 + noise3(obj_pos * 40.0) * 0.4;
	if (n < dissolve * 1.05) {
		discard;
	}
	vec3 c = (linear_color ? COLOR.rgb : pow(COLOR.rgb, vec3(2.2))) * brightness;
	float ember = linear_color ? smoothstep(0.9, 1.0, COLOR.a) : 0.0;
	float gloss = linear_color ? min(COLOR.a, 0.8) * (1.0 - ember) : 0.0;
	float mottle = noise3(obj_pos * 22.0) * 0.6 + noise3(obj_pos * 70.0) * 0.4;
	c *= 1.0 + (mottle - 0.5) * 0.35 * skin_detail;
	float burn = 1.0 - smoothstep(dissolve * 1.05, dissolve * 1.05 + 0.08, n);
	ALBEDO = mix(c, flash_color, flash);
	METALLIC = metal;
	ROUGHNESS = mix(mix(roughness + (mottle - 0.5) * 0.2 * skin_detail, 0.28, metal), 0.2, gloss);
	SPECULAR = mix(mix(0.35, 0.8, metal), 0.7, gloss);
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color * edge * rim_strength + flash_color * flash * 0.6 + vec3(1.0, 0.45, 0.1) * burn * step(0.001, dissolve) * 2.0 + COLOR.rgb * ember * (1.6 + 0.8 * sin(TIME * 2.3 + obj_pos.y * 9.0));
}
