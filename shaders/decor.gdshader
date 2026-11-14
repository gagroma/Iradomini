shader_type spatial;
render_mode specular_schlick_ggx;

// DECOR - plain material for things fixed to the walls: gilt frames, the
// crosses and plaques of the Stations of the Cross, the back of the altarpiece.
//
// Why it exists: the walls wobble (PSX vertex snapping), and far away or at a
// steep angle that moves the wall surface by several centimetres in depth -
// enough to cut through anything hanging on it. So every piece of wall decor
// is pulled a little towards the camera along the line of sight: by
// PULL x distance / sin(viewing angle), which is just more than the wobble can
// move the wall. On screen it stays exactly where it was; only its depth
// changes, so the wall behind can no longer cut into it, while anything
// standing more than PULL x distance in front of it (4.5 cm at 10 m) still
// hides it properly.
// The same pull is in painting, mosaic, stained_glass and chalk_line shaders.

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_nearest;
uniform bool use_tex = false;
uniform bool use_vertex_color = false;
uniform float metallic = 0.0;
uniform float roughness = 0.8;

const float PULL = 0.0045;          // fraction of the distance to the camera

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// the wall's depth error grows as 1/sin of the viewing angle, so the pull does too
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float facing = max(abs(dot(normalize(v.xyz), vn)), 0.15);
	v.xyz *= 1.0 - PULL / facing;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec3 c = albedo.rgb;
	if (use_tex) {
		c *= texture(tex, UV).rgb;
	}
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	METALLIC = metallic;
	ROUGHNESS = roughness;
}
