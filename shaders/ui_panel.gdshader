shader_type canvas_item;
render_mode unshaded;

uniform sampler2D backdrop : hint_screen_texture, filter_linear;
uniform vec2 panel_size = vec2(148.0, 30.0);
uniform float opacity = 0.95;

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
	           mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * panel_size;
	vec2 corner = abs(p - panel_size * 0.5) - panel_size * 0.5 + vec2(8.0);
	float contour = length(max(corner, 0.0)) + min(max(corner.x, corner.y), 0.0) - 4.0;
	float fibres = noise(p * vec2(0.21, 0.50));
	float speckle = hash(floor(p));
	float fray = (noise(p * 0.27) - 0.5) * 3.8 + (fibres - 0.5) * 2.1 + (speckle - 0.5) * 1.5;
	float surface = 1.0 - smoothstep(-0.40, 0.64, contour + fray);
	float bleed = 1.0 - smoothstep(0.0, 3.6, contour + fray * 0.66);
	float rim = smoothstep(-8.0, 0.8, contour + fray * 0.5);

	vec3 ash = mix(vec3(0.137, 0.133, 0.149), vec3(0.078, 0.075, 0.086), rim * 0.9);
	ash += (fibres - 0.5) * 0.032 + (speckle - 0.5) * 0.014;
	ash += step(0.94, speckle) * noise(p * 0.16) * 0.041;
	vec2 offset = SCREEN_PIXEL_SIZE * 1.5;
	vec3 blur = (texture(backdrop, SCREEN_UV + vec2(offset.x, 0.0)).rgb
	           + texture(backdrop, SCREEN_UV - vec2(offset.x, 0.0)).rgb
	           + texture(backdrop, SCREEN_UV + vec2(0.0, offset.y)).rgb
	           + texture(backdrop, SCREEN_UV - vec2(0.0, offset.y)).rgb) * 0.25;
	vec3 color = mix(ash * 0.67, ash, surface);
	color = mix(color, blur * 0.36, 0.14 + 0.24 * rim);
	COLOR = vec4(color, max(surface * opacity, bleed * 0.23));
}
