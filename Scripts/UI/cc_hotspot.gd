class_name CCHotspot
extends TextureButton
## Objeto clicable del centro de mando: solo responde sobre su silueta (máscara por alfa) y
## brilla con un contorno al pasar el ratón, al tener el foco o al tocarlo (móvil).

signal activated

const OUTLINE_SHADER := preload("res://Assets/Shaders/hover_outline.gdshader")
const ALPHA_THRESHOLD := 0.5

var glow_color: Color = Color(0.36, 0.95, 1.0)
var _glow: float = 0.0
var _tween: Tween
## Pulso suave para llamar la atención (p. ej. especialidades listas para desbloquear en el terminal).
var attention: bool = false:
	set(v):
		attention = v
		if not v and not is_hovered():
			_apply_glow(0.0)
var _t: float = 0.0


func setup(tex: Texture2D, color: Color) -> void:
	texture_normal = tex
	glow_color = color
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_SCALE
	size = tex.get_size()
	custom_minimum_size = size
	var img := tex.get_image()
	if img:
		if img.is_compressed():
			img.decompress()
		var bm := BitMap.new()
		bm.create_from_image_alpha(img, ALPHA_THRESHOLD)
		texture_click_mask = bm
	var mat := ShaderMaterial.new()
	mat.shader = OUTLINE_SHADER
	mat.set_shader_parameter("glow_color", color)
	mat.set_shader_parameter("glow", 0.0)
	material = mat
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not mouse_entered.is_connected(_on_hover):
		mouse_entered.connect(_on_hover.bind(true))
		mouse_exited.connect(_on_hover.bind(false))
		focus_entered.connect(_on_hover.bind(true))
		focus_exited.connect(_on_hover.bind(false))
		button_down.connect(func(): set_glow(1.0, 0.05))
		pressed.connect(_on_pressed)


func _on_hover(on: bool) -> void:
	set_glow(1.0 if on else 0.0)


func _on_pressed() -> void:
	# En táctil no hay "hover": un destello confirma el toque.
	set_glow(1.0, 0.05)
	if not is_hovered():
		var tw := create_tween()
		tw.tween_interval(0.25)
		tw.tween_callback(func(): if not is_hovered() and not has_focus(): set_glow(0.0))
	activated.emit()


## true si un punto (coordenadas locales) cae sobre la silueta (lo mismo que usa el clic).
func hits(local: Vector2) -> bool:
	var bm := texture_click_mask
	if bm == null:
		return Rect2(Vector2.ZERO, size).has_point(local)
	var p := Vector2i(local)
	var bs := bm.get_size()
	return p.x >= 0 and p.y >= 0 and p.x < bs.x and p.y < bs.y and bm.get_bitv(p)


func _process(delta: float) -> void:
	if not attention or is_hovered() or has_focus() or (_tween and _tween.is_running()):
		return
	_t += delta
	_apply_glow(0.25 + 0.35 * (0.5 + 0.5 * sin(_t * 3.5)))


func is_glowing() -> bool:
	return _glow > 0.5


func set_glow(target: float, time: float = 0.15) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_apply_glow, _glow, target, time)


func _apply_glow(v: float) -> void:
	_glow = v
	if material:
		(material as ShaderMaterial).set_shader_parameter("glow", v)
