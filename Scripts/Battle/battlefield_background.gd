class_name BattlefieldBackground
extends CanvasLayer
## Suelo del campo de batalla: hierba oliva con manchas de tierra, una franja de tierra de nadie
## en el centro y viñeteado suave. Es un shader procedural (sin texturas) a pantalla completa,
## así que se adapta solo a cualquier tamaño de ventana y no cuesta nada generarlo.
## Vive en una capa por debajo de todo (layer -10) y se mantiene también durante el combate.

const SHADER_CODE := """
shader_type canvas_item;

uniform vec4 grass_light : source_color = vec4(0.27, 0.31, 0.19, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.18, 0.21, 0.13, 1.0);
uniform vec4 dirt : source_color = vec4(0.33, 0.28, 0.2, 1.0);
uniform vec4 dirt_dark : source_color = vec4(0.22, 0.19, 0.14, 1.0);
uniform vec2 screen_size = vec2(1152.0, 648.0);
uniform float seed = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 px = UV * screen_size;
	// Hierba: dos escalas de ruido para que no se vea repetida
	float g = fbm(px / 140.0) * 0.7 + fbm(px / 22.0) * 0.3;
	vec3 col = mix(grass_dark.rgb, grass_light.rgb, smoothstep(0.3, 0.75, g));
	// Briznas: grano fino
	col *= 0.94 + 0.12 * noise(px / 2.5);
	// Manchas de tierra dispersas
	float d = fbm(px / 95.0 + 17.0);
	col = mix(col, dirt.rgb, smoothstep(0.6, 0.72, d) * 0.55);
	// Tierra de nadie: franja central de tierra con borde irregular
	float cx = abs(px.x - screen_size.x * 0.5) / screen_size.x;
	float edge = 0.1 + (fbm(vec2(px.y / 60.0, 3.1)) - 0.5) * 0.06;
	float band = 1.0 - smoothstep(edge - 0.035, edge + 0.035, cx);
	vec3 mud = mix(dirt_dark.rgb, dirt.rgb, fbm(px / 40.0 + 5.0));
	col = mix(col, mud, band * 0.75);
	// Viñeteado
	vec2 q = UV - 0.5;
	col *= 1.0 - dot(q, q) * 0.55;
	COLOR = vec4(col, 1.0);
}
"""

var _rect: ColorRect


func _ready() -> void:
	layer = -10
	_rect = ColorRect.new()
	_rect.name = "Ground"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("seed", randf() * 10.0)
	_rect.material = mat
	add_child(_rect)
	get_viewport().size_changed.connect(_update_size)
	_update_size()


func _update_size() -> void:
	if _rect and _rect.material:
		(_rect.material as ShaderMaterial).set_shader_parameter("screen_size", get_viewport().get_visible_rect().size)
