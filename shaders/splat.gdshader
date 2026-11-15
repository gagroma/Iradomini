shader_type spatial;
render_mode unshaded, cull_disabled;

// PIXEL-SPLAT MODELS (the demon, relics, the body).
// Inspiration: the pixel-art Gaussian splat clip used as the style reference,
// and the gen.py script that made the first two demon models. A model is
// thousands of tiny flat squares; each square has one flat colour from a short
// palette, and the shading is baked into those colours. Rendered at 480x270
// the squares turn into chunky pixels.
// "dissolve" makes the squares fly apart (used when the demon is banished).

uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float brightness = 1.0;
uniform vec3 flash_color : source_color = vec3(1.0, 0.5, 0.1);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 rim_color : source_color = vec3(0.55, 0.45, 0.9);

varying float rnd;
varying vec3 surface_normal;

void vertex() {
	rnd = UV.x;   // one random number per square, stored when the model was built
	surface_normal = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	VERTEX += NORMAL * dissolve * (0.2 + rnd) * 1.2;
	VERTEX.y += dissolve * rnd * 1.5;
}

void fragment() {
	if (rnd < dissolve) {
		discard;
	}
	if (dot(normalize(surface_normal), VIEW) < -0.2) {
		discard;
	}
	vec3 c = pow(COLOR.rgb, vec3(2.2)) * brightness;
	float edge = pow(1.0 - clamp(dot(normalize(surface_normal), VIEW), 0.0, 1.0), 3.0);
	c += rim_color * edge * rim_strength;
	ALBEDO = mix(c, flash_color, flash);
}
