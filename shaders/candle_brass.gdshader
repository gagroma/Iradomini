shader_type spatial;

// CANDLE BRASS - the chamberstick of the hand candle.
// Like the wax, it is lit by its own flame here rather than by the lamp:
// the lamp is a single point 2-15 cm away, which leaves the socket pitch black
// and burns the dish to flat orange. Here the flame light wraps softly
// (as it would after bouncing off the wax and the hand) and leaves a warm
// highlight on the polished metal. Other lights in the level still light it.

uniform vec3 flame_world = vec3(0.0);
uniform float glow = 1.0;
uniform vec3 light_color : source_color = vec3(1.0, 0.64, 0.32);
uniform vec3 tint : source_color = vec3(0.85, 0.8, 0.72);

void fragment() {
	vec3 c = COLOR.rgb * tint;
	ALBEDO = c;
	METALLIC = 0.3;
	ROUGHNESS = 0.42;
	vec3 lv = (VIEW_MATRIX * vec4(flame_world, 1.0)).xyz - VERTEX;
	float d2 = dot(lv, lv);
	vec3 L = normalize(lv);
	float wrap = max((dot(NORMAL, L) + 0.6) / 1.6, 0.0);
	vec3 H = normalize(L + normalize(-VERTEX));
	float spec = pow(max(dot(NORMAL, H), 0.0), 40.0);
	float fall = glow * 0.016 / (d2 + 0.002);
	EMISSION = light_color * (c * wrap + vec3(1.0, 0.8, 0.5) * spec * 0.5) * fall;
}
