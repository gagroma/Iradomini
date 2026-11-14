shader_type spatial;
render_mode cull_back;

// CANDLE WAX - the body, the melted top and old spilled wax of the hand candle.
// Wax lets light through: near the flame it glows warm from inside, and the
// pool of liquid wax around the wick is glossy. Vertex colours come from
// tools/make_candle.py; their alpha is "wetness" (1 = liquid wax).
// "cut_height" hides everything above the current burn height, so the candle
// gets shorter while the drips lower down stay where they ran.

uniform float cut_height = 100.0;   // model height above which the wax is gone
uniform float top_y = 0.16;         // model height of the burning top (for the glow)
uniform float glow = 1.0;           // flame strength, 0 = out
uniform vec3 glow_color : source_color = vec3(1.0, 0.52, 0.2);
// The candle's own OmniLight3D skips the wax (its own render layer): from 2 cm
// away it would burn the wax to flat white. Its light is done here instead,
// soft and wrapped around, the way light spreads inside wax.
uniform vec3 flame_world = vec3(0.0);
uniform vec3 light_color : source_color = vec3(1.0, 0.64, 0.32);

varying vec3 obj;
varying vec3 view_pos;

void vertex() {
	obj = VERTEX;
}

void fragment() {
	if (obj.y > cut_height) {
		discard;
	}
	vec3 c = COLOR.rgb;
	ALBEDO = c;
	ROUGHNESS = mix(0.5, 0.1, COLOR.a);
	SPECULAR = 0.4;
	BACKLIGHT = c * vec3(0.55, 0.4, 0.25);
	float below = max(top_y - obj.y, 0.0);
	float through = exp(-below / 0.012) * (0.55 + 0.45 * COLOR.a);
	vec3 lv = (VIEW_MATRIX * vec4(flame_world, 1.0)).xyz - VERTEX;
	float dist2 = dot(lv, lv);
	float wrap = max((dot(NORMAL, normalize(lv)) + 0.45) / 1.45, 0.0);
	float lit = wrap * glow * 0.0045 / (dist2 + 0.0006);
	// lit wax glows a little all over: light wanders inside it
	float inner = 0.15 * glow;
	EMISSION = glow_color * glow * through * 0.45 + c * light_color * (lit + inner);
}
