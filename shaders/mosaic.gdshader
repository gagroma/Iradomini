shader_type spatial;
render_mode specular_schlick_ggx;

// MOSAIC - a Byzantine-style wall mosaic made from a painting.
// The wall is cut into small square stones (tesserae) set in grey mortar.
// Each stone takes one colour from the painting under its centre. The gold
// stones (the background, and gold in the painting itself) are gold leaf
// under glass: each sits at a slightly different angle, so as a candle or
// the moon moves they flash one by one - the shimmer of real gold mosaics.
// Around the picture: an arched frame of red stones on a gold field, and a
// coloured border along the edges of the wall.

uniform sampler2D tex : source_color, filter_nearest;
uniform vec2 size = vec2(5.8, 4.0);      // metres, the whole mosaic
uniform float tile = 0.045;              // metres, one stone
uniform float image_h = 3.0;             // metres, height of the picture panel
uniform float tex_aspect = 0.68;         // width / height of the picture
uniform float seed = 0.0;

const vec3 GOLD = vec3(0.86, 0.64, 0.24);
const vec3 GROUT = vec3(0.16, 0.15, 0.13);

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

bool goldish(vec3 c) {
	float l = dot(c, vec3(0.333));
	return c.r > c.g && c.g > c.b * 1.25 && l > 0.32 && (c.r - c.b) > 0.22;
}

void fragment() {
	vec2 p = vec2(UV.x, 1.0 - UV.y) * size;          // metres, y up
	float far = smoothstep(0.25, 0.7, length(fwidth(p)) / tile);
	float row = floor(p.y / tile);
	p.x += mod(row, 2.0) * tile * 0.5;               // stones are laid in staggered rows
	vec2 cell = floor(p / tile);
	vec2 local = fract(p / tile);
	float r1 = hash12(cell + seed);
	float r2 = hash12(cell + seed + 17.0);
	// stones are cut by hand: uneven gaps
	vec2 gap = vec2(0.07 + 0.06 * r1, 0.07 + 0.06 * r2);
	bool grout = (local.x < gap.x || local.y < gap.y) && far < 0.5;

	vec2 centre = (cell + 0.5) * tile;
	centre.x -= mod(row, 2.0) * tile * 0.5;
	vec3 col = GOLD;
	bool gold = true;

	// the picture panel: centred, with a round arch on top
	float pw = image_h * tex_aspect;
	vec2 pc = vec2(size.x * 0.5, size.y * 0.47);
	vec2 q = centre - pc;
	float half_w = pw * 0.5;
	float arch_y = image_h * 0.5 - half_w;           // where the arch starts
	float d_arch = q.y > arch_y ? length(vec2(q.x, q.y - arch_y)) - half_w : abs(q.x) - half_w;
	float d_box = max(d_arch, -image_h * 0.5 - q.y);
	if (d_box < 0.0) {
		vec2 uv = vec2(q.x / pw + 0.5, 0.5 - q.y / image_h);
		col = texture(tex, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
		gold = goldish(col);
		if (gold) {
			col = GOLD;
		}
	} else if (d_box < tile * 2.2) {
		col = vec3(0.55, 0.09, 0.08);                // red frame around the picture
		gold = false;
	} else if (d_box < tile * 3.2) {
		col = vec3(0.85, 0.82, 0.74);                // white line outside it
		gold = false;
	}
	// border along the edges of the wall: blue with red and white diamonds
	float edge = min(min(centre.x, size.x - centre.x), min(centre.y, size.y - centre.y));
	if (edge < tile * 6.0) {
		gold = false;
		col = vec3(0.08, 0.14, 0.42);
		float along = (centre.x < tile * 6.0 || size.x - centre.x < tile * 6.0) ? centre.y : centre.x;
		vec2 dm = vec2(fract(along / (tile * 8.0)) - 0.5, (edge / (tile * 6.0)) - 0.5);
		if (abs(dm.x) + abs(dm.y) < 0.32) {
			col = vec3(0.6, 0.1, 0.09);
		} else if (abs(dm.x) + abs(dm.y) < 0.4) {
			col = vec3(0.86, 0.84, 0.78);
		}
		if (edge < tile * 1.1) {
			col = vec3(0.85, 0.82, 0.74);
		}
	}

	// every stone is a slightly different shade
	col *= mix(0.82 + 0.3 * r1, 0.9, far);
	if (grout) {
		ALBEDO = GROUT;
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
		SPECULAR = 0.1;
	} else {
		ALBEDO = col;
		// each stone tilted a little
		vec3 ax = normalize(MODEL_MATRIX[0].xyz);
		vec3 ay = normalize(MODEL_MATRIX[1].xyz);
		vec3 tilt = ax * (r1 - 0.5) + ay * (r2 - 0.5);
		NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * tilt * (gold ? 0.7 : 0.25) * (1.0 - far));
		ROUGHNESS = gold ? 0.22 : 0.5;
		METALLIC = gold ? 0.85 : 0.0;
		SPECULAR = gold ? 0.6 : 0.4;
		// gold leaf under glass gives back a little light even in the dark
		EMISSION = gold ? GOLD * 0.06 * mix(0.6 + 0.8 * r2, 1.0, far) : vec3(0.0);
	}
}
