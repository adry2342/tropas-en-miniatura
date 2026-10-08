class_name SpecialtyTreePanel
extends Control
## Terminal de Especialidades (meta-progresión entre runs). Es la pantalla del ordenador del Centro de
## mando vista de cerca: carcasa metálica (Assets/Terminal/terminal_frame.png, _dev/art/gen_exit_terminal.py)
## y una pantalla de fósforo verde con líneas de barrido.
##  - Al abrirse, la pantalla se enciende (línea → pantalla completa) y la cabecera se escribe sola.
##  - Izquierda: las 7 especialidades como fichas de unidad con 4 marcas de rango.
##  - Centro: el árbol de la elegida: hexágonos unidos por circuitos, el rango 0 (la especialidad) abajo
##    y las mejoras 1..4 hacia arriba. Por los tramos desbloqueados corre un pulso de energía.
##  - Derecha: EXPEDIENTE de la especialidad y ficha del nodo elegido con su botón de acción.
## Esc o el botón APAGAR → emite `closed` y se libera.

signal closed

const FRAME := Vector2(1040, 620)
const SCREEN := Rect2(44, 48, 952, 500)
const LIST_X := 18.0
const LIST_W := 236.0
const TREE_X := 268.0
const TREE_W := 300.0
const INFO_X := 590.0
const INFO_W := 346.0
const HEX_R := 31.0
const HEX_R_BASE := 40.0

const BG := Color("#03100c")
const PHOS := Color("#6dffb6")
const PHOS_DIM := Color("#2f7a59")
const GRID := Color(0.2, 0.9, 0.55, 0.05)
const AMBER := Color("#ffb648")
const RED := Color("#ff5b4f")
const OFF := Color("#1d3a2f")

const SCANLINES := """
shader_type canvas_item;
uniform float lines = 250.0;
void fragment() {
	float s = 0.5 + 0.5 * sin(UV.y * lines * 6.2832);
	float v = distance(UV, vec2(0.5)) * 1.25;
	float roll = smoothstep(0.0, 0.04, abs(fract(UV.y - TIME * 0.08) - 0.5));
	COLOR = vec4(0.0, 0.0, 0.0, 0.16 * s + 0.55 * pow(v, 2.6) + 0.05 * (1.0 - roll));
}
"""

## Especialidad mostrada.
var selected_id: String = ""
## Nodo elegido en el árbol (0 = la especialidad; 1..MAX_RANK = mejoras).
var selected_rank: int = -1

var _frame: Control
var _screen: Control
var _content: Control
var _tree: Control
var _list_buttons: Dictionary = {}
var _node_buttons: Array[Button] = []
var _header: Label
var _medals_label: Label
var _dossier_name: Label
var _dossier_status: Label
var _dossier_desc: Label
var _dossier_passive: Label
var _node_title: Label
var _node_desc: Label
var _node_cost: Label
var _action_button: Button
var _reason_label: Label
var _pulse: float = 0.0
var _header_text := ""
var _type_t: float = -1.0

static var _mono: Font = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	var pm := _pm()
	if pm and pm.has_signal("progress_changed"):
		pm.progress_changed.connect(refresh)
	get_viewport().size_changed.connect(_fit)
	_fit()
	var specs := GameContent.specialties()
	select_specialty(specs[0].id if not specs.is_empty() else "")
	_power_on()


func _pm() -> Node:
	return get_node_or_null("/root/ProfileManager")


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 0.6, 1.0)
	if _tree:
		_tree.queue_redraw()
	if _type_t >= 0.0:
		_type_t += delta
		var n := mini(_header_text.length(), int(_type_t * 60.0))
		_header.text = _header_text.substr(0, n) + ("█" if int(_type_t * 6.0) % 2 == 0 else " ")
		if n >= _header_text.length() and _type_t > float(n) / 60.0 + 0.6:
			_header.text = _header_text
			_type_t = -1.0


# ================================================================ API

func select_specialty(id: String) -> void:
	var sp := GameContent.find_specialty(id)
	if sp == null:
		return
	selected_id = sp.id
	var rank := _rank(sp.id)
	selected_rank = mini(rank + 1, SpecialtyProgression.MAX_RANK) if SpecialtyProgression.is_unlocked(sp.id) else 0
	refresh()


func select_node(r: int) -> void:
	selected_rank = clampi(r, 0, SpecialtyProgression.MAX_RANK)
	refresh()


## Compra el siguiente rango de la especialidad elegida. Devuelve true si se desbloqueó.
func unlock_selected() -> bool:
	var pm := _pm()
	if pm == null or selected_id == "":
		return false
	var ok: bool = pm.unlock_next(selected_id)
	if ok:
		selected_rank = mini(_rank(selected_id) + 1, SpecialtyProgression.MAX_RANK)
		_flash()
	refresh()
	return ok


## Desbloquea la especialidad seleccionada si su hito ya se alcanzó.
func claim_selected() -> bool:
	var pm := _pm()
	if pm == null or not pm.has_method("claim_specialty"):
		return false
	var ok: bool = pm.claim_specialty(selected_id)
	if ok:
		selected_rank = 1
		_flash()
	refresh()
	return ok


func get_unlock_button() -> Button:
	return _action_button if _action_button and _action_button.has_meta("unlock") else null


func refresh() -> void:
	if _content == null:
		return
	var pm := _pm()
	_medals_label.text = "MEDALLAS DE MANDO  🏅 %d" % (int(pm.medals) if pm else 0)
	for id in _list_buttons:
		_style_unit(_list_buttons[id], id)
	_refresh_nodes()
	_refresh_dossier()


# ================================================================ estado

func _rank(id: String) -> int:
	var pm := _pm()
	return int(pm.get_rank(id)) if pm else 0


func _claimable(id: String) -> bool:
	var pm := _pm()
	return pm != null and pm.has_method("is_specialty_claimable") and pm.is_specialty_claimable(id)


## "base", "unlocked", "next", "locked", "sealed" (especialidad bloqueada) o "claimable".
func node_state(id: String, r: int) -> String:
	if not SpecialtyProgression.is_unlocked(id):
		if r == 0:
			return "claimable" if _claimable(id) else "sealed"
		return "locked"
	var rank := _rank(id)
	if r == 0:
		return "base"
	if r <= rank:
		return "unlocked"
	return "next" if r == rank + 1 else "locked"


# ================================================================ construcción

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.01, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_frame = Control.new()
	_frame.name = "Terminal"
	_frame.size = FRAME
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	_screen = Control.new()
	_screen.name = "Screen"
	_screen.position = SCREEN.position
	_screen.size = SCREEN.size
	_screen.clip_contents = true
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_screen)
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = SCREEN.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(bg)
	var grid := Control.new() # rejilla tenue de fondo
	grid.size = SCREEN.size
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.draw.connect(func():
		for x in range(0, int(SCREEN.size.x), 24):
			grid.draw_line(Vector2(x, 0), Vector2(x, SCREEN.size.y), GRID, 1.0)
		for y in range(0, int(SCREEN.size.y), 24):
			grid.draw_line(Vector2(0, y), Vector2(SCREEN.size.x, y), GRID, 1.0))
	_screen.add_child(grid)

	_content = Control.new()
	_content.name = "Content"
	_content.size = SCREEN.size
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(_content)
	_build_header()
	_build_list()
	_build_tree()
	_build_dossier()

	var scan := ColorRect.new()
	scan.name = "Scanlines"
	scan.size = SCREEN.size
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SCANLINES
	sm.shader = sh
	scan.material = sm
	_screen.add_child(scan)

	var frame_tex := TextureRect.new()
	frame_tex.texture = load("res://Assets/Terminal/terminal_frame.png")
	frame_tex.size = FRAME
	frame_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(frame_tex)

	# Botón físico de apagado en la carcasa
	var off := Button.new()
	off.name = "CloseButton"
	off.text = "✕  APAGAR"
	off.focus_mode = Control.FOCUS_NONE
	off.position = Vector2(FRAME.x - 196, 562)
	off.size = Vector2(150, 34)
	off.add_theme_font_override("font", _font())
	off.add_theme_font_size_override("font_size", 15)
	off.tooltip_text = "Apagar el terminal (Esc)"
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#5a1612") if st == "normal" else (Color("#7a1f19") if st == "hover" else Color("#3a0e0b"))
		sb.border_color = Color("#1a0a08")
		sb.set_border_width_all(2)
		sb.border_width_bottom = 4 if st != "pressed" else 2
		sb.set_corner_radius_all(6)
		off.add_theme_stylebox_override(st, sb)
	off.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	off.add_theme_color_override("font_color", Color("#ffd2c8"))
	off.add_theme_color_override("font_hover_color", Color.WHITE)
	off.pressed.connect(close)
	_frame.add_child(off)


func _build_header() -> void:
	_header = _lbl("", 15, PHOS)
	_header.position = Vector2(LIST_X, 12)
	_header.size = Vector2(560, 22)
	_content.add_child(_header)
	_medals_label = _lbl("", 16, AMBER)
	_medals_label.name = "MedalsLabel"
	_medals_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_medals_label.position = Vector2(SCREEN.size.x - 336, 11)
	_medals_label.size = Vector2(318, 24)
	_medals_label.tooltip_text = SpecialtyProgression.medals_hint()
	_medals_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.add_child(_medals_label)
	var line := ColorRect.new()
	line.color = PHOS_DIM
	line.position = Vector2(LIST_X, 40)
	line.size = Vector2(SCREEN.size.x - LIST_X * 2, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(line)


func _build_list() -> void:
	var t := _lbl("// UNIDADES", 12, PHOS_DIM)
	t.position = Vector2(LIST_X, 50)
	_content.add_child(t)
	var y := 70.0
	for sp in GameContent.specialties():
		var b := Button.new()
		b.name = "Spec_%s" % sp.id
		b.position = Vector2(LIST_X, y)
		b.size = Vector2(LIST_W, 54)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(select_specialty.bind(sp.id))
		var icon := _lbl("", 24, PHOS)
		icon.name = "Icon"
		icon.position = Vector2(8, 8)
		icon.size = Vector2(38, 38)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(icon)
		var n := _lbl("", 16, PHOS)
		n.name = "NameLabel"
		n.position = Vector2(52, 7)
		n.size = Vector2(LIST_W - 60, 20)
		b.add_child(n)
		var s := _lbl("", 12, PHOS_DIM)
		s.name = "StatusLabel"
		s.position = Vector2(52, 28)
		s.size = Vector2(LIST_W - 60, 18)
		b.add_child(s)
		_content.add_child(b)
		_list_buttons[sp.id] = b
		y += 59.0


func _build_tree() -> void:
	_tree = Control.new()
	_tree.name = "Tree"
	_tree.position = Vector2(TREE_X, 48)
	_tree.size = Vector2(TREE_W, SCREEN.size.y - 60)
	_tree.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree.draw.connect(_draw_tree)
	_content.add_child(_tree)
	for r in SpecialtyProgression.MAX_RANK + 1:
		var b := Button.new()
		b.name = "Node%d" % r
		var rad := HEX_R_BASE if r == 0 else HEX_R
		b.size = Vector2(rad * 2.0, rad * 2.0)
		b.position = _node_pos(r) - b.size * 0.5
		b.focus_mode = Control.FOCUS_NONE
		b.flat = true
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, empty)
		b.add_theme_font_size_override("font_size", 24 if r == 0 else 18)
		b.add_theme_font_override("font", _font())
		b.pressed.connect(select_node.bind(r))
		b.mouse_entered.connect(func(): _tree.set_meta("hover", r))
		b.mouse_exited.connect(func(): _tree.set_meta("hover", -1))
		_tree.add_child(b)
		_node_buttons.append(b)
	var cap := _lbl("// ÁRBOL DE MEJORAS", 12, PHOS_DIM)
	cap.position = Vector2(0, 2)
	cap.size = Vector2(TREE_W, 16)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tree.add_child(cap)


func _node_pos(r: int) -> Vector2:
	var h := SCREEN.size.y - 60
	var bottom := h - 52.0
	var top := 62.0
	var step := (bottom - top) / SpecialtyProgression.MAX_RANK
	# zigzag suave para que parezca un circuito y no una lista
	var dx := 0.0 if r == 0 else (-46.0 if r % 2 == 1 else 46.0)
	return Vector2(TREE_W * 0.5 + dx, bottom - step * r)


func _build_dossier() -> void:
	var box := VBoxContainer.new()
	box.name = "Dossier"
	box.position = Vector2(INFO_X, 50)
	box.size = Vector2(INFO_W, SCREEN.size.y - 66)
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(box)
	box.add_child(_lbl("// EXPEDIENTE", 12, PHOS_DIM))
	_dossier_name = _lbl("", 26, PHOS)
	box.add_child(_dossier_name)
	_dossier_status = _lbl("", 13, PHOS_DIM)
	box.add_child(_dossier_status)
	_dossier_desc = _wrap("", 14, Color(PHOS, 0.85))
	box.add_child(_dossier_desc)
	_dossier_passive = _wrap("", 13, AMBER)
	box.add_child(_dossier_passive)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	var sep := ColorRect.new()
	sep.color = PHOS_DIM
	sep.custom_minimum_size = Vector2(INFO_W, 1)
	box.add_child(sep)
	box.add_child(_lbl("// NODO SELECCIONADO", 12, PHOS_DIM))
	_node_title = _lbl("", 19, PHOS)
	box.add_child(_node_title)
	_node_desc = _wrap("", 14, Color(PHOS, 0.85))
	box.add_child(_node_desc)
	_node_cost = _lbl("", 14, AMBER)
	box.add_child(_node_cost)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(fill)
	_reason_label = _lbl("", 13, RED)
	_reason_label.name = "ReasonLabel"
	_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_reason_label)
	_action_button = Button.new()
	_action_button.name = "UnlockButton"
	_action_button.custom_minimum_size = Vector2(INFO_W, 50)
	_action_button.focus_mode = Control.FOCUS_NONE
	_action_button.add_theme_font_override("font", _font())
	_action_button.add_theme_font_size_override("font_size", 18)
	_action_button.pressed.connect(_on_action)
	box.add_child(_action_button)


# ================================================================ refresco

func _style_unit(b: Button, id: String) -> void:
	var sp := GameContent.find_specialty(id)
	var on := id == selected_id
	var open := SpecialtyProgression.is_unlocked(id)
	var ready := not open and _claimable(id)
	var col: Color = PHOS if open else (AMBER if ready else PHOS_DIM)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col, 0.16 if on else (0.08 if st == "hover" else 0.0))
		sb.border_color = Color(col, 0.95 if on else 0.35)
		sb.set_border_width_all(1)
		sb.border_width_left = 4 if on else 1
		sb.set_corner_radius_all(2)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var icon: Label = b.get_node("Icon")
	icon.text = UiKit.emo(sp.emoji) if open else ("🔓" if ready else "🔒")
	icon.modulate = Color.WHITE if open else Color(1, 1, 1, 0.55)
	var n: Label = b.get_node("NameLabel")
	n.text = sp.display_name.to_upper() if open or ready else "▒▒▒▒▒▒▒▒"
	n.add_theme_color_override("font_color", col)
	var s: Label = b.get_node("StatusLabel")
	if open:
		var rank := _rank(id)
		s.text = "RANGO " + "■".repeat(rank) + "□".repeat(SpecialtyProgression.MAX_RANK - rank)
		s.add_theme_color_override("font_color", AMBER if rank >= SpecialtyProgression.MAX_RANK else PHOS_DIM)
	elif ready:
		s.text = ">> HITO CONSEGUIDO"
		s.add_theme_color_override("font_color", AMBER)
	else:
		s.text = "ACCESO DENEGADO"
		s.add_theme_color_override("font_color", Color(RED, 0.7))
	b.tooltip_text = "" if open else SpecialtyProgression.unlock_text(id)


func _refresh_nodes() -> void:
	var sp := GameContent.find_specialty(selected_id)
	if sp == null:
		return
	for r in _node_buttons.size():
		var st := node_state(sp.id, r)
		var b := _node_buttons[r]
		b.set_meta("state", st)
		b.set_meta("rank", r)
		match st:
			"base": b.text = UiKit.emo(sp.emoji)
			"unlocked": b.text = "✓"
			"next": b.text = str(r)
			"claimable": b.text = "🔓"
			_: b.text = "🔒" if r == 0 else str(r)
		var col := _state_color(st, sp)
		b.add_theme_color_override("font_color", col)
		b.add_theme_color_override("font_hover_color", col.lightened(0.3))
		b.add_theme_color_override("font_pressed_color", col)
		b.tooltip_text = _node_name(sp, r)
	_tree.queue_redraw()


func _state_color(st: String, sp: SpecialtyData) -> Color:
	match st:
		"base", "unlocked": return sp.color.lerp(PHOS, 0.35)
		"next", "claimable": return AMBER
		_: return PHOS_DIM


func _node_name(sp: SpecialtyData, r: int) -> String:
	if r == 0:
		return sp.display_name
	return str(SpecialtyProgression.node(sp.id, r).get("name", "Mejora %d" % r))


func _refresh_dossier() -> void:
	var sp := GameContent.find_specialty(selected_id)
	if sp == null:
		return
	var open := SpecialtyProgression.is_unlocked(sp.id)
	var ready := _claimable(sp.id)
	_dossier_name.text = sp.display_name.to_upper() if open or ready else "CLASIFICADO"
	_dossier_name.add_theme_color_override("font_color", sp.color.lerp(PHOS, 0.35) if open else (AMBER if ready else RED))
	var rank := _rank(sp.id)
	if open:
		_dossier_status.text = "ESTADO: ACTIVA  ·  RANGO %d/%d" % [rank, SpecialtyProgression.MAX_RANK]
		_dossier_desc.text = sp.description
		_dossier_passive.text = "PASIVA » %s: %s" % [sp.passive_name, sp.passive_description]
	else:
		_dossier_status.text = "ESTADO: " + ("HITO CONSEGUIDO" if ready else "BLOQUEADA")
		_dossier_desc.text = ("Requisito cumplido: " if ready else "Requisito: ") + SpecialtyProgression.unlock_text(sp.id)
		_dossier_passive.text = "PASIVA » %s" % sp.passive_name if ready else ""

	var r := selected_rank
	var st := node_state(sp.id, r)
	_node_title.text = "[%s] %s" % ["BASE" if r == 0 else "R%d" % r, _node_name(sp, r).to_upper() if (open or ready or r == 0) else "????"]
	_node_title.add_theme_color_override("font_color", _state_color(st, sp))
	var desc := ""
	if r == 0:
		desc = "La especialidad tal cual: su pasiva y sus afinidades de arma."
	else:
		var n := SpecialtyProgression.node(sp.id, r)
		desc = str(n.get("description", ""))
		var mods: Dictionary = n.get("modifiers", {})
		if not mods.is_empty():
			desc += "\n» " + TroopStats.describe_modifiers(mods)
	_node_desc.text = desc
	_node_cost.text = ("COSTE: 🏅 %d" % SpecialtyProgression.cost(sp.id, r)) if r > 0 else ""

	# Botón de acción según el nodo
	_reason_label.text = ""
	var pm := _pm()
	var medals: int = int(pm.medals) if pm else 0
	_action_button.remove_meta("unlock")
	_action_button.remove_meta("claim")
	_action_button.disabled = true
	var label := ""
	var accent := PHOS_DIM
	match st:
		"claimable":
			label = "[ ACTIVAR ESPECIALIDAD ]"
			_action_button.disabled = false
			_action_button.set_meta("claim", true)
			accent = AMBER
		"next":
			var cost := SpecialtyProgression.cost(sp.id, r)
			label = "[ DESBLOQUEAR · 🏅 %d ]" % cost
			_action_button.set_meta("unlock", true)
			_action_button.disabled = pm == null or not pm.can_unlock_next(sp.id)
			accent = AMBER
			if _action_button.disabled:
				_reason_label.text = "MEDALLAS INSUFICIENTES · FALTAN %d 🏅" % maxi(0, cost - medals)
		"unlocked", "base":
			label = "[ OPERATIVO ✓ ]"
			accent = PHOS
		"sealed":
			label = "[ ACCESO DENEGADO ]"
			accent = RED
		_:
			label = "[ BLOQUEADO ]"
			_reason_label.text = "PRIMERO: RANGO %d" % (r - 1) if open else ""
	_action_button.text = label
	for stn in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		var a := 0.22 if stn == "hover" else (0.3 if stn == "pressed" else 0.12)
		if stn == "disabled":
			a = 0.04
		sb.bg_color = Color(accent, a)
		sb.border_color = Color(accent, 0.9 if stn != "disabled" else 0.4)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(2)
		_action_button.add_theme_stylebox_override(stn, sb)
	_action_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_action_button.add_theme_color_override("font_color", accent)
	_action_button.add_theme_color_override("font_hover_color", accent.lightened(0.3))
	_action_button.add_theme_color_override("font_disabled_color", Color(accent, 0.75))


func _on_action() -> void:
	if _action_button.has_meta("claim"):
		claim_selected()
	elif _action_button.has_meta("unlock"):
		unlock_selected()


# ================================================================ dibujo del árbol

func _hex(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw_tree() -> void:
	var sp := GameContent.find_specialty(selected_id)
	if sp == null:
		return
	var rank := _rank(sp.id) if SpecialtyProgression.is_unlocked(sp.id) else -1
	var hover: int = int(_tree.get_meta("hover", -1))
	# Circuitos entre nodos (codo horizontal-vertical)
	for r in range(1, SpecialtyProgression.MAX_RANK + 1):
		var a := _node_pos(r - 1)
		var b := _node_pos(r)
		var mid := Vector2(b.x, a.y - (a.y - b.y) * 0.5)
		var path := PackedVector2Array([a, Vector2(a.x, mid.y), Vector2(b.x, mid.y), b])
		var lit := r <= rank
		var col := sp.color.lerp(PHOS, 0.35) if lit else (AMBER if r == rank + 1 else OFF)
		if lit or r == rank + 1:
			_tree.draw_polyline(path, Color(col, 0.18), 9.0)
		_tree.draw_polyline(path, Color(col, 0.9 if lit else 0.55), 2.0)
		if lit: # pulso de energía que sube por el circuito
			var t := fmod(_pulse + r * 0.17, 1.0)
			var p := _along(path, t)
			_tree.draw_circle(p, 6.0, Color(col, 0.25))
			_tree.draw_circle(p, 3.0, Color.WHITE.lerp(col, 0.3))
	# Hexágonos
	for r in SpecialtyProgression.MAX_RANK + 1:
		var c := _node_pos(r)
		var rad := HEX_R_BASE if r == 0 else HEX_R
		var st := node_state(sp.id, r)
		var col := _state_color(st, sp)
		var lit := st in ["base", "unlocked"]
		var glow := st in ["next", "claimable"]
		if glow:
			var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			_tree.draw_colored_polygon(_hex(c, rad + 8.0 + 3.0 * k), Color(col, 0.10 + 0.12 * k))
		if r == selected_rank:
			var sel := _hex(c, rad + 7.0)
			sel.append(sel[0])
			_tree.draw_polyline(sel, Color(PHOS, 0.95), 1.5)
		_tree.draw_colored_polygon(_hex(c, rad), Color(col, 0.22) if lit else Color(BG.lightened(0.04), 1.0))
		var outline := _hex(c, rad)
		outline.append(outline[0])
		_tree.draw_polyline(outline, Color(col, 1.0 if lit or glow else 0.6) if r != hover else col.lightened(0.35), 2.5 if lit or glow else 1.5)
		var inner := _hex(c, rad - 6.0)
		inner.append(inner[0])
		_tree.draw_polyline(inner, Color(col, 0.35), 1.0)
		# etiqueta al lado
		var font := _font()
		var name_txt := _node_name(sp, r) if (rank >= 0 or r == 0 or st == "claimable") else "????"
		var side := 1.0 if c.x <= TREE_W * 0.5 else -1.0
		var tx := c.x + side * (rad + 12.0)
		var tw := font.get_string_size(name_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var pos := Vector2(tx if side > 0 else tx - tw, c.y + 5.0)
		if r == 0:
			pos = Vector2(c.x - font.get_string_size(name_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x * 0.5, c.y + rad + 18.0)
		_tree.draw_string(font, pos, name_txt.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(col, 0.95 if lit or glow else 0.6))


func _along(path: PackedVector2Array, t: float) -> Vector2:
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	var d := t * total
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if d <= seg:
			return path[i].lerp(path[i + 1], d / maxf(seg, 0.001))
		d -= seg
	return path[path.size() - 1]


# ================================================================ efectos

func _fit() -> void:
	var vp := get_viewport_rect().size
	var s := minf(1.0, minf(vp.x * 0.97 / FRAME.x, vp.y * 0.96 / FRAME.y))
	_frame.scale = Vector2(s, s)
	_frame.position = ((vp - FRAME * s) * 0.5).round()


## Encendido de CRT: una línea brillante que se abre a pantalla completa y la cabecera se teclea sola.
func _power_on() -> void:
	_header_text = "> MANDO CENTRAL // PROGRAMA DE ESPECIALIDADES v7.3"
	_header.text = ""
	_content.modulate.a = 0.0
	var flash := ColorRect.new()
	flash.color = Color(0.75, 1.0, 0.88)
	flash.size = Vector2(SCREEN.size.x, 2)
	flash.position = Vector2(0, SCREEN.size.y * 0.5 - 1)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(flash)
	_screen.move_child(flash, 1)
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_property(flash, "size:y", SCREEN.size.y, 0.16).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(flash, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 0.0, 0.22)
	tw.parallel().tween_property(_content, "modulate:a", 1.0, 0.22)
	tw.tween_callback(func():
		flash.queue_free()
		_type_t = 0.0)


## Destello verde sobre la pantalla al desbloquear algo.
func _flash() -> void:
	var f := ColorRect.new()
	f.color = Color(PHOS, 0.35)
	f.size = SCREEN.size
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(f)
	var tw := create_tween()
	tw.tween_property(f, "modulate:a", 0.0, 0.35)
	tw.tween_callback(f.queue_free)


func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wrap(text: String, size: int, color: Color) -> Label:
	var l := _lbl(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = INFO_W
	return l


static func _font() -> Font:
	if _mono == null:
		_mono = load("res://Assets/Fonts/ShareTechMono.ttf")
	return _mono
