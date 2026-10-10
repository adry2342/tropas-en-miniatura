extends CanvasLayer
## Ficha de tropa. Funciona igual con un nodo tropa del tablero (open), con un TroopCard de la
## reserva (open_card) o con un veterano del Cuartel (open_vault_card): todo se lee y se escribe en el card.
##
## Diseño compacto (rework 2026-10-09), dos columnas:
##  - Cabecera: retrato, nombre, nivel y especialidad · monedas y PM · cerrar. El nombre se cambia
##    tocándolo (o el ✎): se vuelve un campo de texto en el sitio; Enter/perder el foco guarda, Esc cancela.
##  - Izquierda: ARSENAL (arma principal resaltada) · EQUIPO (hueco de munición, solo icono, y 3
##    huecos de objeto con icono y nombre) · ESTADÍSTICAS (cuadrícula 6×3; las que valen 0, atenuadas).
##  - Derecha: ESPECIALIDAD (pasiva) · HABILIDADES (celdas iguales).
##  - Pie: Retirar a la reserva · Subir de nivel (o Eliminar veterano en el Cuartel).
## Las explicaciones no ocupan sitio ni se duplican: no hay tooltips; al hacer clic (o tocar en el
## móvil) sale una tarjeta flotante con la explicación y las acciones (quitar, hacer principal, equipar…).

## Modo Cuartel: se cambió algo de un veterano de la bóveda (el arma equipada o el nombre).
signal vault_card_changed(card: TroopCard)
## Modo Cuartel: el jugador mantuvo pulsado "Eliminar" y confirmó. Quien escucha lo quita de la bóveda.
signal vault_remove_confirmed(card: TroopCard)

const DELETE_HOLD_TIME := 2.0
const LEVEL_UP_CHOICE_SCRIPT = preload("res://Scripts/UI/level_up_choice.gd")
const MONO_FONT = preload("res://Assets/Fonts/ShareTechMono.ttf")
const NORMAL_AMMO_ICON = preload("res://Assets/Items/Ammo/normal.png")
const AMMO_ICON_PX := 40.0

const PANEL_W := 900.0
const LEFT_W := 540.0
const CELL_H := 52.0
const AMMO_W := 96.0
const ITEM_W := 150.0
const SKILL_W := 148.0
const POP_W := 280.0
const NAME_H := 46.0 # alto del nombre de la cabecera (etiqueta y campo de texto)

## Paleta "minitropas": verde oliva oscuro, caqui y latón.
const C_BG := Color(0.07, 0.08, 0.07)
const C_PANEL := Color(0.105, 0.12, 0.1)
const C_CELL := Color(0.14, 0.155, 0.13)
const C_LINE := Color(0.33, 0.37, 0.27)
const C_KHAKI := Color(0.86, 0.76, 0.48)
const C_TEXT := Color(0.93, 0.93, 0.87)
const C_MUTED := Color(0.6, 0.62, 0.54)
const C_DIM := Color(0.42, 0.45, 0.38)
const C_MAIN := Color(0.55, 0.85, 0.45)   # arma principal
const C_AMMO := Color(0.5, 0.75, 1.0)     # hueco de munición
const C_ITEM := Color(1.0, 0.62, 0.25)    # huecos de objeto
const C_SKILL := Color(0.45, 0.68, 1.0)
const C_POISON := Color(0.6, 0.95, 0.35)   # veneno (balas venenosas)

var troop: Node = null          # nodo tropa del tablero (null si es una tropa de la reserva)
var card: TroopCard = null
## Modo Cuartel (veterano de la bóveda, fuera de la run): se ve todo, solo se puede cambiar el arma
## equipada y el nombre. Sin monedas/PM, sin subir de nivel, sin quitar objetos ni equipar desde la reserva.
var vault_mode: bool = false
var level_up_choice: CanvasLayer

var _root: Control
var _panel: PanelContainer
var _portrait: TextureRect
var _name_label: Label
var _name_pen: Control
var _name_edit: LineEdit
var _level_label: Label
var _sub_label: Label
var _wallet: Label
var _arsenal: HFlowContainer
var _ammo_slot: HBoxContainer
var _items_row: HBoxContainer
var _stats_grid: GridContainer
var _spec_box: VBoxContainer
var _skills_grid: GridContainer
var _skills_title: Label
var _level_button: Button
var _return_button: Button
var _delete_button: HoldButton
var _confirm_layer: Control
var _confirm_text: Label
var _confirm_yes: Button
var _confirm_no: Button
var _pop_layer: Control
var _pop: PanelContainer
var _theme: Theme
var _mono_sp: FontVariation


func _ready() -> void:
	layer = 20
	visible = false
	_build_ui()
	level_up_choice = LEVEL_UP_CHOICE_SCRIPT.new()
	level_up_choice.name = "LevelUpChoice"
	add_child(level_up_choice)
	level_up_choice.chosen.connect(_on_offer_chosen)

	EventBus.troop_inspect_requested.connect(open)
	EventBus.troop_card_inspect_requested.connect(open_card)
	EventBus.roster_changed.connect(_refresh)
	EventBus.coins_changed.connect(func(_t: int, _d: int): _refresh())
	EventBus.command_points_changed.connect(func(_t: int, _d: int): _refresh())
	EventBus.battle_fight_started.connect(_on_fight_started)


func _exit_tree() -> void:
	if visible:
		_set_blocking(false)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if is_editing_name():
			cancel_name_edit()
		elif is_popover_open():
			close_popover()
		elif is_remove_confirm_open():
			close_remove_confirm()
		elif not _modal_open():
			close()
		get_viewport().set_input_as_handled()


## Tocar fuera del campo del nombre mientras se escribe = confirmar (como perder el foco).
func _input(event: InputEvent) -> void:
	if is_editing_name() and event is InputEventMouseButton and event.pressed \
			and not _name_edit.get_global_rect().has_point(_name_edit.get_global_mouse_position()):
		commit_name_edit()


func _modal_open() -> bool:
	return (level_up_choice != null and level_up_choice.is_open()) or is_remove_confirm_open()


## Abre la ficha de una tropa del tablero.
func open(target: Node) -> void:
	if not is_instance_valid(target):
		return
	var c = target.get("card")
	if not c is TroopCard:
		return
	troop = target
	card = c
	vault_mode = false
	_show()


## Abre la ficha de una tropa de la reserva.
func open_card(c: Resource) -> void:
	if not c is TroopCard:
		return
	troop = null
	card = c
	vault_mode = false
	_show()


## Abre la ficha de un veterano del Cuartel (ProfileManager.vault).
func open_vault_card(c: TroopCard) -> void:
	if c == null:
		return
	troop = null
	card = c
	vault_mode = true
	_show()


func _show() -> void:
	var was_visible := visible
	visible = true
	_set_blocking(true)
	_refresh()
	if not was_visible:
		_panel.modulate.a = 0.0
		_panel.scale = Vector2.ONE * 0.97
		var tw := _panel.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.14)
		tw.tween_property(_panel, "scale", Vector2.ONE, 0.16)
	# Ofertas ya pagadas y sin elegir: el modal sale directamente
	if not vault_mode and not card.pending_offers.is_empty():
		level_up_choice.open(card)


func close() -> void:
	if not visible:
		return
	cancel_name_edit()
	close_popover()
	close_remove_confirm()
	troop = null
	card = null
	vault_mode = false
	visible = false
	_set_blocking(false)


func _on_fight_started() -> void:
	if _modal_open():
		level_up_choice.visible = false # las ofertas siguen guardadas en el card
	close()


func _set_blocking(value: bool) -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm:
		gsm.ui_blocking = value


func _gsm() -> Node:
	return get_node_or_null("/root/GameStateManager")


# ================================================================ estilo

func _sb(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 3, pad: float = 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = true
	return sb


func _box(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 3, pad: float = 8.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(bg, border, bw, radius, pad))
	return p


## Esquinas de "visor" en un marco (el toque bélico): pequeñas escuadras en las 4 esquinas.
func _brackets(c: Control, col: Color, len: float = 9.0, w: float = 2.0) -> void:
	c.draw.connect(func() -> void:
		var s := c.size
		for corner in [Vector2(0, 0), Vector2(s.x, 0), Vector2(0, s.y), s]:
			var dx := len if corner.x == 0.0 else -len
			var dy := len if corner.y == 0.0 else -len
			c.draw_line(corner, corner + Vector2(dx, 0), col, w)
			c.draw_line(corner, corner + Vector2(0, dy), col, w))


func _lbl(text: String, size: int = 14, color: Color = C_TEXT, mono: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if mono:
		l.add_theme_font_override("font", _mono_sp)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Título de sección: "▌ ARSENAL ─────────".
func _section(text: String, extra: Label = null) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := ColorRect.new()
	bar.color = C_KHAKI
	bar.custom_minimum_size = Vector2(3, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	h.add_child(_lbl(text, 12, C_KHAKI, true))
	if extra:
		h.add_child(extra)
	var line := ColorRect.new()
	line.color = Color(C_LINE, 0.6)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(line)
	return h


func _button(text: String, bg: Color, border: Color, font: Color, size: int = 15) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", _sb(bg, border, 1, 3, 8))
	b.add_theme_stylebox_override("hover", _sb(bg.lightened(0.1), border.lightened(0.25), 1, 3, 8))
	b.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.15), border, 1, 3, 8))
	b.add_theme_stylebox_override("disabled", _sb(Color(bg, 0.35).darkened(0.3), Color(border, 0.25), 1, 3, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", font)
	b.add_theme_color_override("font_hover_color", font.lightened(0.2))
	b.add_theme_color_override("font_pressed_color", font)
	b.add_theme_color_override("font_disabled_color", Color(font, 0.35))
	return b


## Celda pulsable (arma, munición, objeto, habilidad…): fondo, borde y contenido libre.
## Clic/toque = tarjeta flotante (on_tap). `_tip` se queda solo como nota para quien lee el código.
func _cell(bg: Color, border: Color, _tip: String, on_tap: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	b.custom_minimum_size.y = CELL_H
	b.add_theme_stylebox_override("normal", _sb(bg, border, 1, 3, 6))
	b.add_theme_stylebox_override("hover", _sb(bg.lightened(0.08), border.lightened(0.3), 1, 3, 6))
	b.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.1), border.lightened(0.3), 1, 3, 6))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", _sb(bg, border, 1, 3, 6))
	if on_tap.is_valid():
		b.pressed.connect(func() -> void: on_tap.call(b))
	return b


## Contenido de una celda: icono (textura o emoji) + nombre (opcional) + etiqueta pequeña arriba a la derecha.
func _fill_cell(b: Button, icon, title: String, title_col: Color, tag: String = "", tag_col: Color = C_MUTED) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 7
	h.offset_right = -6
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if title == "":
		h.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(h)
	if icon is Texture2D:
		var r := TextureRect.new()
		r.texture = icon
		r.custom_minimum_size = Vector2(38, 38)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(r)
	elif icon is String and icon != "":
		var e := _lbl(UiKit.emo(icon), 22)
		e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(e)
	elif icon is Control:
		h.add_child(icon)
	if title != "":
		var t := _lbl(title, 13, title_col)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.size_flags_vertical = Control.SIZE_FILL
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.max_lines_visible = 2
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t.add_theme_constant_override("line_spacing", -3)
		h.add_child(t)
	if tag != "":
		var g := _lbl(tag, 10, tag_col, true)
		g.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		g.offset_left = -80
		g.offset_right = -5
		g.offset_top = 2
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.add_child(g)


## Tema propio (por si algún control hijo mostrara un tooltip del motor, que vaya a juego).
func _make_theme() -> Theme:
	var t := Theme.new()
	var tp := _sb(Color(0.05, 0.06, 0.05, 0.97), C_KHAKI.darkened(0.2), 1, 3, 8)
	t.set_stylebox("panel", "TooltipPanel", tp)
	t.set_color("font_color", "TooltipLabel", C_TEXT)
	t.set_font_size("font_size", "TooltipLabel", 13)
	return t


# ================================================================ construcción

func _build_ui() -> void:
	_mono_sp = FontVariation.new()
	_mono_sp.base_font = MONO_FONT
	_mono_sp.spacing_glyph = 1
	_theme = _make_theme()

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _theme
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_panel = _box(C_BG, C_LINE, 1, 4, 14)
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	_panel.resized.connect(func(): _panel.pivot_offset = _panel.size * 0.5)
	_brackets(_panel, C_KHAKI, 14.0, 2.0)
	center.add_child(_panel)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	_panel.add_child(main)
	main.add_child(_build_header())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	main.add_child(body)

	# Izquierda: arsenal, equipo, estadísticas
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 7)
	left.custom_minimum_size.x = LEFT_W
	body.add_child(left)
	left.add_child(_section("ARSENAL"))
	_arsenal = HFlowContainer.new()
	_arsenal.add_theme_constant_override("h_separation", 6)
	_arsenal.add_theme_constant_override("v_separation", 6)
	left.add_child(_arsenal)

	# Equipo: munición (hueco propio, solo icono) y objetos (icono + nombre)
	var eq := HBoxContainer.new()
	eq.add_theme_constant_override("separation", 12)
	left.add_child(eq)
	var ammo_col := VBoxContainer.new()
	ammo_col.add_theme_constant_override("separation", 7)
	ammo_col.custom_minimum_size.x = AMMO_W
	eq.add_child(ammo_col)
	ammo_col.add_child(_section("MUNICIÓN"))
	_ammo_slot = HBoxContainer.new()
	ammo_col.add_child(_ammo_slot)
	var item_col := VBoxContainer.new()
	item_col.add_theme_constant_override("separation", 7)
	item_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq.add_child(item_col)
	item_col.add_child(_section("OBJETOS"))
	_items_row = HBoxContainer.new()
	_items_row.add_theme_constant_override("separation", 6)
	item_col.add_child(_items_row)

	left.add_child(_section("ESTADÍSTICAS"))
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 6
	_stats_grid.add_theme_constant_override("h_separation", 6)
	_stats_grid.add_theme_constant_override("v_separation", 6)
	left.add_child(_stats_grid)

	# Separador vertical
	var vline := ColorRect.new()
	vline.color = Color(C_LINE, 0.5)
	vline.custom_minimum_size.x = 1
	vline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(vline)

	# Derecha: especialidad y habilidades
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 7)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(_section("ESPECIALIDAD"))
	_spec_box = VBoxContainer.new()
	_spec_box.add_theme_constant_override("separation", 4)
	right.add_child(_spec_box)
	_skills_title = _lbl("", 12, C_DIM, true)
	right.add_child(_section("HABILIDADES", _skills_title))
	var sscroll := ScrollContainer.new()
	sscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sscroll.custom_minimum_size.y = 120
	sscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sscroll)
	_skills_grid = GridContainer.new()
	_skills_grid.columns = 2
	_skills_grid.add_theme_constant_override("h_separation", 6)
	_skills_grid.add_theme_constant_override("v_separation", 6)
	sscroll.add_child(_skills_grid)

	main.add_child(_build_footer())
	_build_remove_confirm(_root)
	_build_popover_layer()


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)

	var pframe := _box(C_PANEL, C_LINE, 1, 3, 4)
	pframe.custom_minimum_size = Vector2(76, 76)
	_brackets(pframe, C_KHAKI, 8.0, 2.0)
	header.add_child(pframe)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pframe.add_child(_portrait)

	var htext := VBoxContainer.new()
	htext.add_theme_constant_override("separation", 2)
	htext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	htext.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(htext)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	htext.add_child(name_row)
	_build_name_editor(name_row)
	var lv := _box(Color(C_KHAKI, 0.12), Color(C_KHAKI, 0.8), 1, 2, 0)
	var lsb: StyleBoxFlat = lv.get_theme_stylebox("panel")
	lsb.content_margin_left = 8
	lsb.content_margin_right = 8
	lsb.content_margin_top = 1
	lsb.content_margin_bottom = 1
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(lv)
	_level_label = _lbl("", 15, C_KHAKI, true)
	lv.add_child(_level_label)
	_sub_label = _lbl("", 15, C_MUTED)
	htext.add_child(_sub_label)

	_wallet = _lbl("", 18, UiKit.GOLD, true)
	_wallet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_wallet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_wallet)
	var close_btn := _button("✕", C_PANEL, C_LINE, C_TEXT, 16)
	close_btn.custom_minimum_size = Vector2(38, 34)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_btn.pressed.connect(func():
		if not _modal_open():
			close())
	header.add_child(close_btn)
	return header


## Nombre de la cabecera: etiqueta pulsable + ✎ discreto; al tocarlos, un LineEdit ocupa su sitio.
func _build_name_editor(row: HBoxContainer) -> void:
	_name_label = _lbl("", 28, C_TEXT)
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_pen = _pencil_icon()
	for l: Control in [_name_label, _name_pen]:
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		l.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
				begin_name_edit())
	row.add_child(_name_label)

	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.visible = false
	_name_edit.max_length = TroopCard.NAME_MAX_LEN
	_name_edit.expand_to_text_length = true
	_name_edit.custom_minimum_size = Vector2(240, NAME_H)
	_name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_edit.virtual_keyboard_enabled = true   # móvil: abre el teclado del sistema
	_name_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_name_edit.context_menu_enabled = false
	_name_edit.add_theme_font_size_override("font_size", 28)
	_name_edit.add_theme_color_override("font_color", C_TEXT)
	_name_edit.add_theme_color_override("caret_color", C_KHAKI)
	_name_edit.add_theme_color_override("selection_color", Color(C_KHAKI, 0.35))
	var sb := _sb(C_CELL, C_KHAKI, 0, 2, 0)
	sb.border_width_bottom = 2
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	_name_edit.add_theme_stylebox_override("normal", sb)
	_name_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_name_edit.text_submitted.connect(func(_t): commit_name_edit())
	_name_edit.focus_exited.connect(commit_name_edit)
	_name_edit.editing_toggled.connect(func(on: bool):
		if not on:
			commit_name_edit())
	# Esc lo atiende el campo antes que nadie: cancela solo la edición (no cierra la ficha)
	_name_edit.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_cancel"):
			cancel_name_edit()
			_name_edit.accept_event())
	row.add_child(_name_edit)
	row.add_child(_name_pen)
	# Misma altura con y sin campo: la cabecera no salta al empezar a escribir
	_name_label.custom_minimum_size.y = NAME_H


## Lápiz dibujado a trazos (sin emoji: el ✎ de la fuente sale en color y desentona). Caqui al pasar el ratón.
func _pencil_icon() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(16, 16)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.draw.connect(func() -> void:
		var col := C_KHAKI if Rect2(Vector2.ZERO, c.size).has_point(c.get_local_mouse_position()) else C_DIM
		var a := Vector2(4, 12)   # punta (abajo a la izquierda)
		var b := Vector2(13, 3)   # cabeza
		c.draw_line(a.lerp(b, 0.22), b, col, 3.0)
		c.draw_colored_polygon(PackedVector2Array([a, a + Vector2(3.4, -0.6), a + Vector2(0.6, -3.4)]), col)
		c.draw_line(Vector2(2, 15), Vector2(14, 15), Color(col, 0.6), 1.0))
	c.mouse_entered.connect(c.queue_redraw)
	c.mouse_exited.connect(c.queue_redraw)
	return c


func _build_footer() -> HBoxContainer:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	footer.alignment = BoxContainer.ALIGNMENT_END
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_return_button = _button("↩  Retirar a la reserva", C_PANEL, C_LINE, C_TEXT, 14)
	_return_button.custom_minimum_size = Vector2(200, 42)
	_return_button.pressed.connect(_on_return_pressed)
	footer.add_child(_return_button)
	_level_button = _button("", Color(0.26, 0.22, 0.08), UiKit.GOLD, Color(1.0, 0.92, 0.62), 16)
	_level_button.custom_minimum_size = Vector2(240, 42)
	_level_button.pressed.connect(_on_level_up_pressed)
	footer.add_child(_level_button)
	# Modo Cuartel: eliminar al veterano (mantener pulsado + confirmar)
	_delete_button = HoldButton.new()
	_delete_button.name = "DeleteVeteranButton"
	_delete_button.text = "🗑  Eliminar veterano"
	_delete_button.holding_text = "Mantén pulsado…"
	_delete_button.hold_time = DELETE_HOLD_TIME
	_delete_button.custom_minimum_size = Vector2(240, 42)
	_delete_button.add_theme_font_size_override("font_size", 15)
	UiKit.style_button(_delete_button, Color(0.26, 0.09, 0.08), UiKit.DOWN, Color(1.0, 0.82, 0.8), 3)
	_delete_button.held.connect(open_remove_confirm)
	_delete_button.visible = false
	footer.add_child(_delete_button)
	return footer


## Ventana "¿Seguro?" para eliminar un veterano (encima del panel).
func _build_remove_confirm(root: Control) -> void:
	_confirm_layer = Control.new()
	_confirm_layer.name = "RemoveConfirm"
	_confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_layer.visible = false
	root.add_child(_confirm_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(center)
	var box := _box(C_BG, UiKit.DOWN, 1, 4, 20)
	box.custom_minimum_size = Vector2(480, 0)
	_brackets(box, UiKit.DOWN, 12.0, 2.0)
	center.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	box.add_child(v)
	var t := _lbl("🗑  ¿Eliminar veterano?", 22, UiKit.DOWN)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_confirm_text = _lbl("", 14, C_TEXT)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size.x = 440
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_confirm_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	_confirm_no = _button("Cancelar", C_PANEL, C_LINE, C_TEXT, 15)
	_confirm_no.name = "ConfirmNoButton"
	_confirm_no.custom_minimum_size = Vector2(180, 42)
	_confirm_no.focus_mode = Control.FOCUS_ALL
	_confirm_no.pressed.connect(close_remove_confirm)
	row.add_child(_confirm_no)
	_confirm_yes = _button("Sí, eliminar", Color(0.4, 0.1, 0.08), UiKit.DOWN, Color.WHITE, 15)
	_confirm_yes.name = "ConfirmYesButton"
	_confirm_yes.custom_minimum_size = Vector2(180, 42)
	_confirm_yes.pressed.connect(confirm_remove)
	row.add_child(_confirm_yes)


## Capa de la tarjeta flotante: un clic fuera la cierra.
func _build_popover_layer() -> void:
	_pop_layer = Control.new()
	_pop_layer.name = "Popover"
	_pop_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pop_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_pop_layer.visible = false
	_pop_layer.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			close_popover())
	_root.add_child(_pop_layer)


func is_remove_confirm_open() -> bool:
	return _confirm_layer != null and _confirm_layer.visible


func open_remove_confirm() -> void:
	if not vault_mode or card == null:
		return
	_confirm_text.text = "%s (Nv. %d · %s) dejará el Cuartel para siempre.\nSolo se recupera venciendo otra vez al Jefe Final y guardando otra tropa." % [
		card.unit_name, card.level, card.get_specialty_name()]
	_confirm_layer.visible = true
	_confirm_no.grab_focus()


func close_remove_confirm() -> void:
	if _confirm_layer:
		_confirm_layer.visible = false
	if _delete_button:
		_delete_button.reset()


## Elimina de verdad (tras mantener pulsado y confirmar).
func confirm_remove() -> void:
	if not is_remove_confirm_open() or card == null:
		return
	var c := card
	close()
	vault_remove_confirmed.emit(c)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if not _modal_open():
			close()


# ================================================================ tarjeta flotante

func is_popover_open() -> bool:
	return _pop_layer != null and _pop_layer.visible


func close_popover() -> void:
	if _pop and is_instance_valid(_pop):
		_pop.queue_free()
	_pop = null
	if _pop_layer:
		_pop_layer.visible = false


## Tarjeta junto a `anchor`: título, línea de tipo, texto y acciones [[texto, callable, activo]].
## `extra` (opcional) se añade tras el texto (p. ej. la lista de cosas de la reserva para equipar).
func _popover(anchor: Control, title: String, color: Color, kind: String, body: String,
		actions: Array = [], extra: Control = null) -> void:
	close_popover()
	_pop = _box(Color(0.06, 0.07, 0.06, 0.98), Color(color, 0.85), 1, 3, 12)
	_pop.custom_minimum_size.x = POP_W
	_pop.mouse_filter = Control.MOUSE_FILTER_STOP
	_brackets(_pop, color, 8.0, 2.0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_pop.add_child(v)
	var tl := _lbl(title, 17, color)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tl)
	if kind != "":
		v.add_child(_lbl(kind.to_upper(), 11, C_DIM, true))
	if body != "":
		var bl := _lbl(body, 13, C_TEXT.darkened(0.06))
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.custom_minimum_size.x = POP_W - 24
		v.add_child(bl)
	if extra:
		v.add_child(extra)
	if not actions.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		v.add_child(row)
		for a in actions:
			var b := _button(a[0], C_PANEL, C_LINE, C_TEXT, 13)
			b.custom_minimum_size.y = 32
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.disabled = a.size() > 2 and not a[2]
			var fn: Callable = a[1]
			b.pressed.connect(func() -> void:
				close_popover()
				fn.call())
			row.add_child(b)
	_pop_layer.add_child(_pop)
	_pop_layer.visible = true
	_place_popover.call_deferred(anchor)


func _place_popover(anchor: Control) -> void:
	if _pop == null or not is_instance_valid(_pop) or not is_instance_valid(anchor):
		return
	_pop.reset_size()
	var vp := _root.get_viewport_rect().size
	var a := anchor.get_global_rect()
	var p := Vector2(a.position.x, a.end.y + 6)
	if p.y + _pop.size.y > vp.y - 8:
		p.y = a.position.y - _pop.size.y - 6
	p.x = clampf(p.x, 8, vp.x - _pop.size.x - 8)
	p.y = clampf(p.y, 8, vp.y - _pop.size.y - 8)
	_pop.position = p


## Lista de recursos de la reserva para equipar desde la tarjeta (icono + nombre).
func _bench_list(res_list: Array, on_pick: Callable) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(_lbl("DE LA RESERVA", 11, C_DIM, true))
	for r in res_list:
		var b := _button("", C_PANEL, C_LINE, C_TEXT, 13)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 32
		if r is WeaponData:
			b.text = " " + r.display_name
			UiKit.set_weapon_icon(b, r, 26)
		else:
			if r.icon:
				b.text = " " + r.display_name
				b.icon = r.icon
				b.add_theme_constant_override("icon_max_width", 26)
			else:
				b.text = "%s  %s" % [UiKit.emo(r.emoji), r.display_name]
		b.pressed.connect(func() -> void:
			close_popover()
			on_pick.call(r))
		v.add_child(b)
	return v


# ================================================================ refresco

func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func _refresh() -> void:
	if not visible or card == null:
		return
	if troop != null and (not is_instance_valid(troop) or troop.is_queued_for_deletion()):
		close()
		return
	close_popover()
	var gsm := _gsm()
	var coins: int = gsm.coins if gsm else 0
	var points: int = gsm.command_points if gsm else 0
	var s := TroopStats.compute(card)

	_portrait.texture = UiKit.troop_texture(card)
	_name_label.text = card.unit_name
	_level_label.text = "NV %d" % card.level
	if card.specialty:
		_sub_label.text = "%s %s" % [UiKit.emo(card.specialty.emoji), card.specialty.display_name]
	else:
		_sub_label.text = "🔰 Recluta"
	_sub_label.add_theme_color_override("font_color", UiKit.specialty_color(card))
	_wallet.text = "💰 %d   ⭐ %d" % [coins, points]
	_wallet.visible = not vault_mode

	_refresh_arsenal(points)
	_refresh_equipment()
	_refresh_stats(s)
	_refresh_specialty()
	_refresh_skills()
	_refresh_footer(points)


func _refresh_arsenal(points: int) -> void:
	_clear(_arsenal)
	var main_i := clampi(card.equipped_weapon, 0, maxi(0, card.weapons.size() - 1))
	for i in card.weapons.size():
		var w: WeaponData = card.weapons[i]
		if w == null:
			continue
		var is_main := i == main_i
		var wl: int = card.get_weapon_level(w)
		var aff := card.specialty != null and card.specialty.is_affine(w)
		var border := C_MAIN if is_main else C_LINE
		var bg := Color(0.13, 0.19, 0.12) if is_main else C_CELL
		var tip := "%s · %s%s\n%s" % [w.display_name, w.get_family_name(), " · afín" if aff else "", _weapon_line(w)]
		var b := _cell(bg, border, tip, _tap_weapon.bind(i))
		b.custom_minimum_size.x = 172
		var tag := "PRINCIPAL" if is_main else ""
		var wname := w.display_name + ("  ★%d" % wl if wl > 1 else "")
		_fill_cell(b, w.get_icon(), wname, UiKit.rarity_color(w.rarity).lerp(C_TEXT, 0.3) if is_main else C_MUTED,
				tag, C_MAIN if is_main else C_KHAKI)
		if is_main and not vault_mode and wl < Economy.WEAPON_MAX_LEVEL and points >= card.get_weapon_upgrade_cost(w):
			var up := _lbl("▲", 10, UiKit.GOLD)
			up.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			up.offset_left = -16
			up.offset_top = -16
			b.add_child(up)
		_arsenal.add_child(b)
	# Hueco para añadir un arma de la reserva
	var gsm := _gsm()
	if not vault_mode and gsm:
		var addable: Array = []
		for wp in gsm.get_bench_weapons():
			if not card.has_weapon(wp.id):
				addable.append(wp)
		if not addable.is_empty():
			var add := _cell(Color(0, 0, 0, 0), Color(C_LINE, 0.7), "Añadir un arma de la reserva", func(btn: Control) -> void:
				_popover(btn, "Añadir arma", C_KHAKI, "Arsenal", "", [], _bench_list(addable, equip_bench_weapon)))
			add.custom_minimum_size.x = CELL_H
			_fill_cell(add, "", "", C_TEXT)
			var plus := _lbl("+", 22, C_KHAKI)
			plus.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			plus.grow_horizontal = Control.GROW_DIRECTION_BOTH
			plus.grow_vertical = Control.GROW_DIRECTION_BOTH
			add.add_child(plus)
			_arsenal.add_child(add)


func _weapon_line(w: WeaponData) -> String:
	var dmg := ("%d×%d" % [w.pellets, roundi(w.damage)]) if w.pellets > 1 else str(roundi(w.damage))
	return "Daño %s · %.1f disp/s · alcance %d · cargador %s" % [dmg, w.fire_rate, roundi(w.attack_range), UiKit.magazine_text(w.magazine)]


func _tap_weapon(btn: Control, index: int) -> void:
	var w: WeaponData = card.weapons[index]
	var is_main := index == clampi(card.equipped_weapon, 0, card.weapons.size() - 1)
	var aff := card.specialty != null and card.specialty.is_affine(w)
	var body := _weapon_line(w)
	if aff:
		body += "\nAfín a su especialidad: +15 de daño y +10 de precisión."
	var actions: Array = []
	if not is_main:
		actions.append(["Hacer principal", equip_weapon.bind(index)])
	if not vault_mode and is_main:
		var lv: int = card.get_weapon_level(w)
		if lv < Economy.WEAPON_MAX_LEVEL:
			var gsm := _gsm()
			var pm: int = gsm.command_points if gsm else 0
			var cost: int = card.get_weapon_upgrade_cost(w)
			actions.append(["Mejorar a ★%d · ⭐ %d" % [lv + 1, cost], upgrade_weapon, pm >= cost,
					Economy.weapon_upgrade_hint(w)])
		else:
			body += "\nMejorada al máximo (★%d)." % lv
	var kind := "%s · %s" % [w.get_family_name(), "principal" if is_main else "de reserva"]
	_popover(btn, w.display_name, UiKit.rarity_color(w.rarity).lerp(C_TEXT, 0.25), kind, body, actions)


func _refresh_equipment() -> void:
	_clear(_ammo_slot)
	var gsm := _gsm()
	var bench_items: Array = gsm.get_bench_items() if gsm and not vault_mode else []
	# --- Munición: solo el icono; la explicación, al tocarla
	var am := card.ammo
	var tip := _ammo_tip()
	var ab := _cell(Color(0.07, 0.11, 0.16), Color(C_AMMO, 0.85 if am else 0.45), tip, _tap_ammo)
	# forma distinta a los objetos: más redondeado y con doble borde
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = ab.get_theme_stylebox(st)
		sb.set_corner_radius_all(14)
		sb.border_width_left = 2
		sb.border_width_right = 2
	ab.custom_minimum_size = Vector2(AMMO_W, CELL_H)
	_fill_cell(ab, _ammo_icon(am), "", C_TEXT)
	var new_ammo := 0
	for it in bench_items:
		if card.is_ammo(it) and card.can_add_item(it):
			new_ammo += 1
	if new_ammo > 0:
		_corner_dot(ab)
	_ammo_slot.add_child(ab)
	# --- Objetos: icono + nombre
	_clear(_items_row)
	var fit_items: Array = []
	for it in bench_items:
		if not card.is_ammo(it) and card.can_add_item(it):
			fit_items.append(it)
	for i in TroopCard.MAX_ITEM_SLOTS:
		var b: Button
		if i < card.items.size() and card.items[i] != null:
			var it: ItemData = card.items[i]
			b = _cell(Color(0.17, 0.13, 0.08), Color(C_ITEM, 0.7), "%s\n%s" % [it.display_name, it.description], _tap_item.bind(it))
			_fill_cell(b, it.emoji, it.display_name, UiKit.rarity_color(it.rarity).lerp(C_TEXT, 0.35))
		else:
			var can := not fit_items.is_empty()
			b = _cell(Color(0, 0, 0, 0.18), Color(C_LINE, 0.55), "Hueco libre", _tap_empty_item if can else Callable())
			var e := _lbl("+" if can else "—", 18 if can else 14, C_KHAKI if can else C_DIM)
			e.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			e.grow_horizontal = Control.GROW_DIRECTION_BOTH
			e.grow_vertical = Control.GROW_DIRECTION_BOTH
			b.add_child(e)
			if not can:
				b.mouse_default_cursor_shape = Control.CURSOR_ARROW
		b.custom_minimum_size.x = ITEM_W
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_items_row.add_child(b)


func _ammo_tip() -> String:
	var tip := ""
	if card.ammo:
		tip = "%s\n%s" % [card.ammo.display_name, card.ammo.description]
	else:
		tip = "%s\nSin efecto especial." % TroopCard.NORMAL_AMMO_NAME
	if not TroopStats.uses_ammo(card.get_weapon()):
		tip += "\nSu arma principal no dispara balas: solo cuenta con sus armas de bala."
	return tip


## Punto de aviso en la esquina: hay algo en la reserva que se puede equipar aquí.
func _corner_dot(b: Control) -> void:
	var d := ColorRect.new()
	d.color = C_KHAKI
	d.custom_minimum_size = Vector2(6, 6)
	d.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	d.offset_left = -10
	d.offset_top = 4
	d.offset_right = -4
	d.offset_bottom = 10
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(d)


## Icono de la munición (3 cartuchos; la punta cambia según el tipo). Arte: _dev/art/gen_ammo_icons.py.
func _ammo_icon(am: ItemData) -> TextureRect:
	var r := TextureRect.new()
	r.texture = am.icon if am and am.icon else NORMAL_AMMO_ICON
	r.custom_minimum_size = Vector2(AMMO_ICON_PX, AMMO_ICON_PX)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _tap_ammo(btn: Control) -> void:
	var gsm := _gsm()
	var loadable: Array = []
	if gsm and not vault_mode:
		for it in gsm.get_bench_items():
			if card.is_ammo(it) and card.can_add_item(it):
				loadable.append(it)
	var actions: Array = []
	if card.ammo and not vault_mode:
		actions.append(["Quitar", remove_item.bind(card.ammo), true, "Vuelve a las balas normales; la munición regresa a la reserva."])
	var body := card.ammo.description if card.ammo else "Sin efecto especial."
	if not TroopStats.uses_ammo(card.get_weapon()):
		body += "\nSu arma principal no dispara balas: solo cuenta con sus armas de bala."
	if not loadable.is_empty() and card.ammo:
		body += "\nCargar otra sustituye a esta, que se pierde."
	var extra: Control = _bench_list(loadable, equip_bench_item) if not loadable.is_empty() else null
	_popover(btn, card.get_ammo_name(), C_AMMO, "Munición", body, actions, extra)


func _tap_item(btn: Control, it: ItemData) -> void:
	var body := it.description
	var actions: Array = []
	if not vault_mode:
		actions.append(["Quitar", remove_item.bind(it), true, "Devuelve el objeto a la reserva."])
	_popover(btn, it.display_name, UiKit.rarity_color(it.rarity).lerp(C_TEXT, 0.25),
			"%s · %s" % [it.get_slot_name(), UiKit.rarity_name(it.rarity)], body, actions)


func _tap_empty_item(btn: Control) -> void:
	var gsm := _gsm()
	var fit: Array = []
	if gsm:
		for it in gsm.get_bench_items():
			if not card.is_ammo(it) and card.can_add_item(it):
				fit.append(it)
	_popover(btn, "Hueco libre", C_ITEM, "Objeto", "", [], _bench_list(fit, equip_bench_item))


## Cuadrícula de estadísticas (las del arma principal). Salen todas, aunque valgan 0 (atenuadas).
## Al tocar una, una tarjeta explica qué es.
func _refresh_stats(s: Dictionary) -> void:
	_clear(_stats_grid)
	var mag: int = int(s.magazine)
	var hit := ("%d×%d" % [s.pellets, roundi(s.hit_damage)]) if s.pellets > 1 else str(roundi(s.hit_damage))
	var supp: float = float(s.get("suppress_hit", 0.0))
	# [título, valor, color, ¿vale 0?, explicación]
	var cells: Array = [
		["VIDA", "%d" % roundi(s.max_health), UiKit.HEALTH, false, "Vida máxima."],
		["DAÑO", UiKit.pct(s.damage_mult), UiKit.DAMAGE, false, "Puntos de daño: con 100 pega lo base del arma y cada punto más suma una centésima. Cada impacto hace %s." % hit],
		["IMPACTO", hit, UiKit.DAMAGE, false, "Daño de cada impacto (arma × daño)." + (" Dispara %d perdigones a la vez." % s.pellets if s.pellets > 1 else "")],
		["CADENCIA", "%d" % roundi(s.fire_rate_pts), C_TEXT, false, "Puntos de cadencia: con 100 dispara al ritmo base del arma. Ahora: %s disparos por segundo." % ("%.1f" % s.fire_rate).replace(".", ",")],
		["PRECISIÓN", UiKit.pct(s.accuracy), C_TEXT, false, "Puntos de precisión (0–100): cuántos de cada 100 disparos acierta a su distancia óptima (%d). Más lejos, baja." % roundi(s.optimal_range)],
		["ÓPTIMO", "%d" % roundi(s.optimal_range), C_TEXT, false, "Distancia óptima: hasta aquí acierta con toda su precisión; más lejos, va fallando más."],
		["ALCANCE", "%d" % roundi(s.attack_range), C_TEXT, false, "Distancia máxima a la que dispara."],
		["CARGADOR", UiKit.magazine_text(mag), C_TEXT, false, "Balas por cargador." if mag > 0 else "Sin cargador: nunca recarga."],
		["RECARGA", ("%.1f s" % s.reload_time) if mag > 0 else "—", C_TEXT, mag <= 0, "Tiempo que tarda en recargar. Solo recarga estando quieto."],
		["MOVILIDAD", "%d" % roundi(s.move_speed), C_TEXT, false, "Velocidad al moverse por el campo."],
		["EVASIÓN", UiKit.pct(s.dodge), C_AMMO, s.dodge <= 0.0, "Puntos de evasión: de cada 100 impactos, cuántos esquiva."],
		["ARMADURA", UiKit.pct(s.armor), C_AMMO, s.armor <= 0.0, "Puntos de armadura: de cada 100 de daño recibido, cuánto se evita."],
		["PERFORA", "%d" % int(s.pierce), C_TEXT, int(s.pierce) <= 0, "Enemigos extra que atraviesa cada bala."],
		["VENENO", "%.1f/s" % s.poison_dps, C_POISON, s.poison_pct <= 0.0, "Daño por segundo estimado del veneno: con %d puntos, cada 100 de daño de un impacto añade %d de veneno, que el blanco va perdiendo en %d s. Ignora la armadura y el envenenado se cura la mitad." % [roundi(s.poison_pct * 100.0), roundi(s.poison_pct * 100.0), roundi(TroopStats.POISON_DURATION)]],
		["SUPRESIÓN", "%.1f s" % supp, C_AMMO, supp <= 0.0, "Segundos que sus impactos dejan Suprimido al blanco: dispara y se mueve más lento y apunta peor."],
		["EXPLOSIÓN", "%d" % roundi(s.aoe_radius), UiKit.DAMAGE, s.aoe_radius <= 0.0, "Radio de la explosión de sus disparos."],
		["CURACIÓN", UiKit.pct(s.heal_mult), UiKit.HEALTH, is_equal_approx(s.heal_mult, 1.0), "Puntos de curación: con 100 cura lo normal; cada punto más suma una centésima (botiquín, autocuración, Doctor)."],
		["DPS", "%.1f" % s.dps, UiKit.GOLD, false, "Daño por segundo estimado, con precisión a distancia óptima y recargas." + (" Incluye el veneno (%.1f directo + %.1f de veneno)." % [s.direct_dps, s.poison_dps] if s.poison_pct > 0.0 else "")],
	]
	for c in cells:
		var zero: bool = c[3]
		var p := _box(C_PANEL if not zero else Color(C_PANEL, 0.5), Color(0, 0, 0, 0), 0, 3, 5)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -3)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(v)
		v.add_child(_lbl(c[0], 9, C_DIM, true))
		v.add_child(_lbl(c[1], 16, C_DIM if zero else c[2], true))
		var title: String = ("DPS" if c[0] == "DPS" else String(c[0]).capitalize()) + "  ·  " + String(c[1])
		var body: String = c[4]
		var col: Color = c[2]
		_on_tap(p, func() -> void: _popover(p, title, col, "Estadística", body))
		_stats_grid.add_child(p)


## Clic o toque sobre un control que no es botón: llama a `fn`.
func _on_tap(c: Control, fn: Callable) -> void:
	c.gui_input.connect(func(e: InputEvent) -> void:
		var up_click: bool = e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed
		var up_touch: bool = e is InputEventScreenTouch and not e.pressed
		if up_click or up_touch:
			c.accept_event()
			fn.call())


func _refresh_specialty() -> void:
	_clear(_spec_box)
	var sp := card.specialty
	if sp == null:
		_spec_box.add_child(_lbl("🔰 Recluta", 16, UiKit.RECRUIT))
		var l := _lbl("Elige especialidad al llegar a Nv. %d." % TroopCard.SPECIALTY_LEVEL, 12, C_MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_spec_box.add_child(l)
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_spec_box.add_child(head)
	head.add_child(_lbl("%s %s" % [UiKit.emo(sp.emoji), sp.display_name], 16, sp.color))
	# Familias afines como etiquetas pequeñas
	for f in sp.affine_families:
		var tag := _box(Color(sp.color, 0.1), Color(sp.color, 0.45), 1, 2, 0)
		var tsb: StyleBoxFlat = tag.get_theme_stylebox("panel")
		tsb.content_margin_left = 5
		tsb.content_margin_right = 5
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.add_child(_lbl(WeaponData.FAMILY_NAMES[clampi(int(f), 0, WeaponData.FAMILY_NAMES.size() - 1)].to_upper(), 10, sp.color.lightened(0.2), true))
		head.add_child(tag)
	# Pasiva: nombre y descripción (es la faceta de la especialidad). Al tocarla: afinidad y sinergia.
	var pv := _box(Color(sp.color, 0.08), Color(sp.color, 0.35), 1, 3, 8)
	pv.mouse_filter = Control.MOUSE_FILTER_STOP
	pv.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var fam_names: Array[String] = []
	for f in sp.affine_families:
		fam_names.append(WeaponData.FAMILY_NAMES[clampi(int(f), 0, WeaponData.FAMILY_NAMES.size() - 1)])
	var info := "Armas afines (+15 de daño y +10 de precisión): %s." % ", ".join(fam_names)
	if sp.synergy_text != "":
		info += "\n🤝 " + sp.synergy_text
	_on_tap(pv, func() -> void: _popover(pv, sp.display_name, sp.color, "Especialidad · " + sp.passive_name, info))
	var pvb := VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 1)
	pv.add_child(pvb)
	pvb.add_child(_lbl("✦ " + sp.passive_name, 13, sp.color.lightened(0.25)))
	var d := _lbl(sp.passive_description, 12, C_TEXT.darkened(0.12))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = SKILL_W * 2 + 6 - 16
	pvb.add_child(d)
	_spec_box.add_child(pv)


func _refresh_skills() -> void:
	_clear(_skills_grid)
	var order: Array = []
	var counts := {}
	var by_id := {}
	for sk in card.skills:
		if sk == null:
			continue
		if not counts.has(sk.id):
			order.append(sk.id)
			by_id[sk.id] = sk
		counts[sk.id] = int(counts.get(sk.id, 0)) + 1
	_skills_title.text = "%d" % card.skills.size() if not card.skills.is_empty() else ""
	if order.is_empty():
		var l := _lbl("Sin habilidades todavía.", 12, C_DIM)
		_skills_grid.add_child(l)
		return
	# Agrupadas por categoría (△ □ S ○); celdas iguales con el símbolo y el borde del color de su categoría
	order.sort_custom(func(x, y): return int(by_id[x].category) < int(by_id[y].category))
	for id in order:
		var sk: SkillData = by_id[id]
		var n: int = counts[id]
		var ccol: Color = sk.get_category_color()
		var tip := "%s · %s\n%s" % [sk.display_name, sk.get_category_name(), sk.description]
		var b := _cell(Color(0.08, 0.11, 0.16).lerp(ccol, 0.06), Color(ccol, 0.55), tip, _tap_skill.bind(sk, n))
		b.custom_minimum_size = Vector2(SKILL_W, 40)
		_fill_cell(b, sk.emoji, sk.display_name, Color(0.84, 0.9, 1.0), ("×%d" % n) if n > 1 else "", C_SKILL)
		var badge := CategoryBadge.make(int(sk.category), 14)
		badge.position = Vector2(2, 2)
		b.add_child(badge)
		_skills_grid.add_child(b)


func _tap_skill(btn: Control, sk: SkillData, n: int) -> void:
	var kind := "Habilidad · %s" % sk.get_category_name() + (" · ×%d" % n if n > 1 else "")
	_popover(btn, sk.display_name, sk.get_category_color().lightened(0.15), kind, sk.description)


func _refresh_footer(points: int) -> void:
	_return_button.visible = troop != null
	_level_button.visible = not vault_mode
	_delete_button.visible = vault_mode
	if vault_mode:
		return
	if not card.pending_offers.is_empty():
		_level_button.text = "⭐  Elegir mejora pendiente"
		_level_button.disabled = false
	elif card.level >= TroopCard.MAX_LEVEL:
		_level_button.text = "Nivel máximo"
		_level_button.disabled = true
	else:
		var cost := card.get_level_up_cost()
		_level_button.text = "⬆  Subir a Nv. %d  ·  ⭐ %d" % [card.level + 1, cost]
		_level_button.disabled = points < cost


# ================================================================ acciones

func _changed() -> void:
	EventBus.roster_changed.emit()


# ---------------------------------------------------------------- nombre

func is_editing_name() -> bool:
	return _name_edit != null and _name_edit.visible


## Convierte el nombre de la cabecera en un campo de texto con el nombre actual seleccionado.
func begin_name_edit() -> void:
	if card == null or is_editing_name() or _modal_open():
		return
	close_popover()
	_name_edit.text = card.unit_name
	_name_label.visible = false
	_name_pen.visible = false
	_name_edit.visible = true
	_name_edit.grab_focus()
	_name_edit.edit() # en móvil saca el teclado virtual
	_name_edit.select_all()


## Guarda lo escrito (si queda vacío tras limpiarlo, se queda el nombre anterior).
func commit_name_edit() -> void:
	if not is_editing_name():
		return
	var n := TroopCard.clean_name(_name_edit.text)
	_end_name_edit()
	rename(n)


func cancel_name_edit() -> void:
	if is_editing_name():
		_end_name_edit()


func _end_name_edit() -> void:
	_name_edit.visible = false # primero: así el focus_exited que provoca ocultarlo no vuelve a confirmar
	_name_label.visible = true
	_name_pen.visible = true


## Cambia el nombre de la tropa. Devuelve true si el nombre era válido.
func rename(new_name: String) -> bool:
	var n := TroopCard.clean_name(new_name)
	if card == null or n == "":
		return false
	if n == card.unit_name:
		return true
	card.unit_name = n
	if vault_mode:
		vault_card_changed.emit(card) # el Cuartel lo guarda en el perfil
		_refresh()
		return true
	_changed()
	return true


func equip_weapon(index: int) -> void:
	if card == null or index < 0 or index >= card.weapons.size():
		return
	card.equipped_weapon = index
	if vault_mode:
		vault_card_changed.emit(card)
		_refresh()
		return
	_changed()


## Mejora el arma equipada gastando PM. Devuelve true si se pudo.
func upgrade_weapon() -> bool:
	if card == null or not LevelUpSystem.upgrade_weapon(card):
		return false
	_changed()
	return true


func remove_item(item: ItemData) -> bool:
	if card == null:
		return false
	var ok := card.remove_item(item) # lo devuelve a la reserva (emite roster_changed vía GSM)
	if ok:
		_changed()
	return ok


func equip_bench_item(item: ItemData) -> bool:
	var gsm := _gsm()
	if card == null or gsm == null:
		return false
	var ok: bool = gsm.equip_item_from_bench(card, item)
	if ok:
		_changed()
	return ok


func equip_bench_weapon(weapon: WeaponData) -> bool:
	var gsm := _gsm()
	if card == null or gsm == null:
		return false
	var ok: bool = gsm.equip_weapon_from_bench(card, weapon)
	if ok:
		_changed()
	return ok


func _on_level_up_pressed() -> void:
	if card == null:
		return
	if not card.pending_offers.is_empty():
		level_up_choice.open(card)
		return
	if LevelUpSystem.begin_level_up(card):
		level_up_choice.open(card) # (idempotente: el modal ya escucha level_up_offers_ready)
	_refresh()


func _on_offer_chosen(_c: TroopCard, _offer: Dictionary) -> void:
	_refresh()


func _on_return_pressed() -> void:
	var target: Node = troop
	var gsm := _gsm()
	close()
	if gsm and is_instance_valid(target):
		gsm.return_troop_to_bench(target)
