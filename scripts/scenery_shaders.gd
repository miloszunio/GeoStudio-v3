class_name SceneryShaders
extends RefCounted
## Shader sources of the preview surroundings (ground with road, grass, leaves, bark, clouds).
## All of them sway with the same wind uniforms; none of this is ever exported.

## Shared wind: `wind` = direction * strength (strength ~ m/s), returns a world XZ offset factor (per metre of height squared).
const WIND := """
uniform vec2 wind = vec2(0.5, 0.0);
vec2 sway2(vec3 wp, float freq) {
	float ph = dot(wp.xz, vec2(0.23, 0.17)) - TIME * 1.25 * freq;
	float g = 0.55 + 0.45 * sin(ph) + 0.30 * sin(ph * 2.17 + 1.3);
	float len = length(wind);
	vec2 d = len > 0.001 ? wind / len : vec2(1.0, 0.0);
	float amp = 0.05 + len * 0.045;
	vec2 perp = vec2(-d.y, d.x) * sin(ph * 1.7 + wp.x * 0.4) * 0.35 * amp;
	return d * g * amp + perp;
}
"""

const GROUND := """
shader_type spatial;
render_mode cull_back;
uniform vec3 grass_a : source_color = vec3(0.16, 0.30, 0.07);
uniform vec3 grass_b : source_color = vec3(0.30, 0.43, 0.11);
uniform vec3 dry : source_color = vec3(0.46, 0.42, 0.20);
uniform vec2 road_n = vec2(0.0, 1.0);
uniform float road_off = 20.0;
uniform float road_w = 6.0;
uniform float road_on = 1.0;
uniform vec2 pad_min = vec2(-5.0, -4.0);
uniform vec2 pad_max = vec2(5.0, 4.0);
uniform float snow = 0.0;
varying vec3 wpos;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { s += vn(p) * a; p = p * 2.03 + 7.1; a *= 0.5; }
	return s;
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = wpos.xz;
	float n1 = fbm(p * 0.09);
	float n2 = fbm(p * 0.9);
	float n3 = vn(p * 7.0);
	vec3 col = mix(grass_a, grass_b, clamp(n1 * 0.9 + n2 * 0.5 - 0.1, 0.0, 1.0));
	col = mix(col, dry, smoothstep(0.58, 0.8, fbm(p * 0.05 + 11.0)) * 0.7);
	col *= 0.86 + 0.28 * n3;
	float rough = 1.0;
	// bare earth around the building
	vec2 q = max(max(pad_min - p, p - pad_max), vec2(0.0));
	float dq = length(q);
	col = mix(col, vec3(0.34, 0.27, 0.19) * (0.8 + 0.4 * n2), (1.0 - smoothstep(0.2, 1.6 + 1.2 * n2, dq)) * 0.85);
	// road: asphalt, kerb, pavement, gravel verge
	if (road_on > 0.5) {
		vec2 al = vec2(road_n.y, -road_n.x);
		float d = dot(p, road_n) - road_off;
		float along = dot(p, al);
		float ad = abs(d);
		float hw = road_w * 0.5;
		float grain = vn(p * 22.0);
		vec3 asphalt = vec3(0.17, 0.17, 0.18) * (0.8 + 0.4 * grain) + vec3(0.02) * n2;
		float on_road = 1.0 - smoothstep(hw - 0.05, hw, ad);
		float dash = step(fract(along / 5.0), 0.55) * (1.0 - smoothstep(0.07, 0.1, ad));
		float edge = (1.0 - smoothstep(0.05, 0.08, abs(ad - (hw - 0.35))));
		asphalt = mix(asphalt, vec3(0.86, 0.84, 0.7), max(dash * 0.9, edge * 0.75));
		asphalt = mix(asphalt, vec3(0.09), smoothstep(0.55, 0.9, vn(vec2(along * 0.6, d * 0.3))) * 0.35 * (1.0 - edge));
		float kerb = smoothstep(hw - 0.02, hw + 0.02, ad) * (1.0 - smoothstep(hw + 0.2, hw + 0.24, ad));
		float walk = smoothstep(hw + 0.2, hw + 0.24, ad) * (1.0 - smoothstep(hw + 2.05, hw + 2.15, ad));
		vec2 tile = fract(vec2(along, d) / 0.6);
		float joint = 1.0 - smoothstep(0.0, 0.03, min(min(tile.x, tile.y), min(1.0 - tile.x, 1.0 - tile.y)));
		vec3 paving = vec3(0.56, 0.55, 0.52) * (0.9 + 0.2 * h21(floor(vec2(along, d) / 0.6))) * (1.0 - 0.25 * joint);
		float gravel = smoothstep(hw + 2.1, hw + 2.2, ad) * (1.0 - smoothstep(hw + 2.5, hw + 3.4 + n2, ad));
		vec3 gcol = vec3(0.45, 0.42, 0.38) * (0.7 + 0.5 * grain);
		col = mix(col, gcol, gravel * 0.9);
		col = mix(col, paving, walk);
		col = mix(col, vec3(0.65, 0.64, 0.62), kerb);
		col = mix(col, asphalt, on_road);
		rough = mix(1.0, 0.72, on_road);
	}
	col = mix(col, vec3(0.93, 0.95, 0.98), snow * (0.75 + 0.25 * n2));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
"""

const GRASS := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 tint_a : source_color = vec3(0.10, 0.22, 0.05);
uniform vec3 tint_b : source_color = vec3(0.45, 0.62, 0.20);
varying float h;
varying vec3 nrm;
""" + WIND + """
void vertex() {
	h = UV.y;
	mat4 M = MODEL_MATRIX;
	vec3 wp = (M * vec4(VERTEX, 1.0)).xyz;
	vec3 base = (M * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float blade_h = length(M[1].xyz);
	vec2 s = sway2(base, 1.0) * blade_h * h * h * 1.6;
	float flutter = sin(TIME * 5.0 + base.x * 3.1 + base.z * 2.3) * 0.012 * length(wind) * h;
	wp += vec3(s.x + flutter, 0.0, s.y);
	VERTEX = (inverse(M) * vec4(wp, 1.0)).xyz;
	nrm = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
void fragment() {
	vec3 c = mix(tint_a, tint_b, h) * COLOR.rgb;
	ALBEDO = c;
	NORMAL = nrm;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = c * 0.55;
}
"""

const LEAVES := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float ao_min = 0.45;
uniform float sway_k = 0.45;
uniform float flutter_k = 1.0;
""" + WIND + """
void vertex() {
	mat4 M = MODEL_MATRIX;
	vec3 wp = (M * vec4(VERTEX, 1.0)).xyz;
	vec3 base = vec3(INSTANCE_CUSTOM.y, 0.0, INSTANCE_CUSTOM.z);
	float H = max(INSTANCE_CUSTOM.x, 1.0);
	float hh = clamp(wp.y / H, 0.0, 1.0);
	vec2 s = sway2(base, 0.8) * H * sway_k * hh * hh;
	vec2 s2 = sway2(wp * 1.7, 2.1) * 0.35 * flutter_k;
	float len = length(wind);
	vec3 fl = vec3(sin(TIME * 7.0 + wp.x * 2.3), sin(TIME * 8.3 + wp.z * 2.9), sin(TIME * 6.1 + wp.y * 3.1)) * (0.02 + 0.025 * len) * flutter_k;
	wp += vec3(s.x + s2.x, 0.0, s.y + s2.y) + fl;
	VERTEX = (inverse(M) * vec4(wp, 1.0)).xyz;
}
void fragment() {
	vec4 t = texture(tex, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 c = t.rgb * COLOR.rgb * mix(ao_min, 1.0, COLOR.a);
	ALBEDO = c;
	ROUGHNESS = 0.75;
	SPECULAR = 0.15;
	BACKLIGHT = c * 0.5;
}
"""

const BARK := """
shader_type spatial;
uniform vec3 base_col : source_color = vec3(0.26, 0.19, 0.13);
uniform vec3 mark_col : source_color = vec3(0.07, 0.06, 0.05);
uniform float marks = 0.0;
uniform float stripes = 7.0;
""" + WIND + """
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 base = vec3(CUSTOM0.x, 0.0, CUSTOM0.y);
	float H = max(CUSTOM0.z, 1.0);
	float hh = clamp(wp.y / H, 0.0, 1.0);
	vec2 s = sway2(base, 0.8) * H * 0.45 * hh * hh;
	wp += vec3(s.x, 0.0, s.y);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
}
void fragment() {
	vec2 uv = UV;
	float fur = vn(vec2(uv.x * stripes, uv.y * 3.0)) * 0.6 + vn(vec2(uv.x * stripes * 3.0, uv.y * 11.0)) * 0.4;
	vec3 c = base_col * (0.55 + 0.9 * fur);
	float m = smoothstep(0.62, 0.7, vn(vec2(uv.x * 4.0, uv.y * 9.0))) * marks;
	c = mix(c, mark_col, m);
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
"""

const CLOUD := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 drift = vec2(2.0, 0.0);
uniform float range = 1600.0;
uniform vec3 lit_col : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 shade_col : source_color = vec3(0.58, 0.65, 0.78);
uniform float cover = 1.0;
varying float fade;
varying float shade;
varying vec2 uvf;
void vertex() {
	vec3 b = MODEL_MATRIX[3].xyz;
	vec2 xz = b.xz + drift * TIME;
	xz = mod(xz + vec2(range), vec2(2.0 * range)) - vec2(range);
	fade = 1.0 - smoothstep(0.7 * range, range, max(abs(xz.x), abs(xz.y)));
	vec3 c = vec3(xz.x, b.y, xz.y);
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	float s = INSTANCE_CUSTOM.y;
	vec3 wp = c + (right * VERTEX.x + up * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	float f = INSTANCE_CUSTOM.x;
	uvf = (UV + vec2(mod(f, 4.0), floor(f / 4.0))) * 0.25;
	shade = INSTANCE_CUSTOM.z;
}
void fragment() {
	vec4 t = texture(tex, uvf);
	vec3 c = mix(shade_col, lit_col, shade) * (0.75 + 0.5 * t.r);
	ALBEDO = c;
	ALPHA = t.a * 0.8 * fade * cover;
}
"""
