shader_type spatial;

// CANDLE WICK - charred black, with an ember tip that glows while the candle
// burns and fades slowly after it goes out. Vertex alpha marks the tip
// (from tools/make_candle.py).

uniform float ember = 1.0;

void fragment() {
	ALBEDO = mix(COLOR.rgb, vec3(0.03, 0.025, 0.02), COLOR.a);
	ROUGHNESS = 0.95;
	EMISSION = vec3(1.0, 0.3, 0.05) * COLOR.a * ember * 3.0;
}
