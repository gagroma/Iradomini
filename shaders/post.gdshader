shader_type canvas_item;

// SCREEN EFFECT, drawn over the whole picture.
// 1) Fear effects from the GDD ("Kamera i oshchushchenie"): vignette, film grain
//    and colour fringing (chromatic aberration), all driven by "fear" 0..1.
// 2) The pixel-art look: colours are cut down to a few steps with an ordered
//    (Bayer) dither pattern. Inspiration: PS1 15-bit colour with dithering, and
//    the flat banded palettes of the pixel-splat reference clip.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float fear = 0.0;     // 0 = calm, 1 = demon in your face
uniform float hurt = 0.0;     // 1 while wounded
uniform float flash = 0.0;    // white-gold flash (hit, banishing, ending)
uniform float fade = 0.0;     // 1 = black screen
uniform float levels = 20.0;  // colour steps per channel; lower = harsher banding

float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - vec2(0.5);
	float r2 = dot(d, d);

	// colour fringing grows with fear
	float ca = fear * 0.012 + hurt * 0.006;
	vec3 c;
	c.r = texture(screen_tex, uv + d * ca).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - d * ca).b;

	// film grain
	vec2 cell = floor(FRAGCOORD.xy) + vec2(floor(TIME * 24.0) * 7.13, 0.0);
	float n = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	c += (n - 0.5) * (0.035 + 0.12 * fear);

	// vignette: dark corners that close in with fear
	float vig = 1.0 - smoothstep(0.10, 0.55, r2 * (1.0 + fear * 1.6 + hurt * 1.2));
	c *= mix(1.0, vig, 0.85);

	// wounded: red pulse at the edges
	float pulse = 0.5 + 0.5 * sin(TIME * 6.0);
	c = mix(c, vec3(0.45, 0.0, 0.02), hurt * smoothstep(0.05, 0.4, r2) * (0.35 + 0.25 * pulse));

	// pixel-art banding with ordered dither
	float b = bayer4(FRAGCOORD.xy);
	c = floor(clamp(c, 0.0, 1.0) * levels + b) / levels;

	c = mix(c, vec3(1.0, 0.93, 0.78), clamp(flash, 0.0, 1.0));
	c = mix(c, vec3(0.0), clamp(fade, 0.0, 1.0));
	COLOR = vec4(c, 1.0);
}
