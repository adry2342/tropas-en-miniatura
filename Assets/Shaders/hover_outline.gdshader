shader_type canvas_item;
// Contorno brillante al pasar el ratón / tocar (centro de mando).
// Usa el alfa con umbral (las sombras y halos suaves del arte no cuentan como silueta).

uniform vec4 glow_color : source_color = vec4(0.36, 0.95, 1.0, 1.0);
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform float width = 5.0;
uniform float threshold = 0.5;

float solid(sampler2D tex, vec2 uv) {
	return step(threshold, texture(tex, uv).a);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (glow > 0.001) {
		float me = solid(TEXTURE, UV);
		float near = 0.0;
		for (int i = 0; i < 16; i++) {
			float ang = float(i) * 0.3926991;
			vec2 d = vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE * width;
			near = max(near, solid(TEXTURE, UV + d));
			near = max(near, solid(TEXTURE, UV + d * 0.5));
		}
		float edge = clamp(near - me, 0.0, 1.0) * glow;
		vec3 lit = c.rgb * (1.0 + 0.18 * glow) + glow_color.rgb * 0.06 * glow * me;
		c = vec4(mix(lit, glow_color.rgb, edge), max(c.a, edge * glow_color.a));
	}
	COLOR = c;
}
