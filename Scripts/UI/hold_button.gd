class_name HoldButton
extends Button
## Botón que hay que MANTENER pulsado `hold_time` segundos para activarse (acciones destructivas).
## Mientras se mantiene, una barra se va llenando por dentro; si se suelta antes, se vacía y no pasa nada.

signal held

@export var hold_time: float = 2.0
@export var fill_color: Color = Color(1.0, 0.35, 0.3, 0.45)
var idle_text: String = ""
var holding_text: String = "Mantén pulsado…"

var _progress: float = 0.0
var _holding: bool = false
var _fill: ColorRect


func _ready() -> void:
	if idle_text == "":
		idle_text = text
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	_fill = ColorRect.new()
	_fill.name = "HoldFill"
	_fill.color = fill_color
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	mouse_exited.connect(_on_up)
	_update_fill()


func get_progress() -> float:
	return _progress


func _on_down() -> void:
	if disabled:
		return
	_holding = true
	text = holding_text


func _on_up() -> void:
	if not _holding:
		return
	_holding = false
	reset()


func reset() -> void:
	_holding = false
	_progress = 0.0
	text = idle_text
	_update_fill()


func _process(delta: float) -> void:
	if not _holding:
		return
	_progress = minf(1.0, _progress + delta / maxf(0.05, hold_time))
	_update_fill()
	if _progress >= 1.0:
		reset()
		held.emit()


func _update_fill() -> void:
	if _fill:
		_fill.position = Vector2.ZERO
		_fill.size = Vector2(size.x * _progress, size.y)
