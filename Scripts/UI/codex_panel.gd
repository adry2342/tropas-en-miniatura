class_name CodexPanel
extends Control
## Códice: un LIBRO de cuero con hojas de pergamino. Al abrirlo se levanta la tapa y se pasan las
## hojas para ver todas las habilidades, objetos, armas y especialidades del juego.
##  - Cada capítulo ocupa una doble página: a la izquierda las casillas, a la derecha la ficha.
##    Si un capítulo crece por encima de PER_PAGE entradas, sigue en la doble página siguiente.
##  - Pasar el ratón por una casilla muestra su ficha; hacer clic la deja fijada.
##  - Pasar hoja: botones de las esquinas, flechas ←/→, la rueda del ratón o las cintas
##    de marcapáginas (saltan al capítulo). Esc cierra.
##  - El arte del libro sale de _dev/art/gen_codex_book.py (Assets/Codex/).
##  - `is_unlocked()` decide qué está bloqueado (🔒 y "???").

signal closed
signal page_turned(spread: int)

const TABS := ["Habilidades", "Objetos", "Armas", "Especialidades"]
const TAB_COLORS: Array[Color] = [Color("#7a2a22"), Color("#2d5a3a"), Color("#28466e"), Color("#6a3f78")]
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]

const ART := "res://Assets/Codex/"
const FONT_DIR := "res://Assets/Fonts/"
## Medidas del libro abierto (coordenadas del arte, ver gen_codex_book.py)
const BOOK := Vector2(1040, 600)
const SPINE := 520.0
const LEFT_PAGE := Rect2(40, 26, 477, 544)
const RIGHT_PAGE := Rect2(523, 26, 477, 544)
const TAB_OUT := 78.0              # lo que asoman las cintas por la derecha
const PER_PAGE := 25
const COLUMNS := 5
const TILE := 60.0
const FLIP_TIME := 0.2
const OPEN_TIME := 0.24

## Tinta sobre pergamino
const INK := Color("#3a2a18")
const INK_SOFT := Color("#6e5634")
const INK_GOLD := Color("#8a6220")
const INK_GREEN := Color("#2f5a2a")
const PARCH := Color("#e9dab4")

var _book: Control
var _clip: Control          # deja ver solo la mitad derecha mientras se abre la tapa
var _left: Control
var _right: Control
var _tab_buttons: Array[Button] = []
var _grid: GridContainer
var _count_label: Label
var _chapter_label: Label
var _title_label: Label
var _detail_icon: Label
var _detail_tex: TextureRect
var _detail_name: Label
var _detail_meta: Label
var _detail_desc: Label
var _detail_mods: Label
var _detail_stats: GridContainer
var _icon_frame: PanelContainer
var _page_num_l: Label
var _page_num_r: Label
var _prev_btn: Button
var _next_btn: Button
var _current_tab: int = 0
var _spread: int = 0
var _spreads: Array = []    # [{tab, entries}]
var _pinned: Resource = null
var _tiles: Array[Button] = []
var _busy: bool = false
var _opened: bool = false
var _slide: float = 0.0
var _target: int = 0        # doble página a la que se va (si se salta capítulos se pasan varias hojas)
var _chain: bool = false     # 1 = libro cerrado centrado; 0 = abierto en su sitio

static var _fonts: Dictionary = {}


## Futuro: progreso del jugador (p. ej. habilidades vistas en una partida). Ahora todo está desbloqueado.
static func is_unlocked(res: Resource) -> bool:
	if res is SpecialtyData: # v7.1: las especialidades se desbloquean con hitos del juego
		return SpecialtyProgression.is_unlocked(res.id)
	return true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_spreads()
	_build()
	_show_spread(0)
	get_viewport().size_changed.connect(_fit_book)
	_fit_book()
	_play_open()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				close()
			KEY_RIGHT, KEY_PAGEDOWN:
				next_page()
			KEY_LEFT, KEY_PAGEUP:
				prev_page()
			_:
				return
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			next_page()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			prev_page()
			accept_event()


func close() -> void:
	closed.emit()
	queue_free()


# ================================================================ datos

func _entries(tab: int) -> Array:
	var list: Array = []
	match tab:
		0: list.assign(GameContent.skills())
		1: list.assign(GameContent.items())
		2: list.assign(GameContent.weapons())
		3: list.assign(GameContent.specialties())
	# Ordenadas por rareza y nombre
	list.sort_custom(func(a, b): return _rar(a) < _rar(b) if _rar(a) != _rar(b) else String(a.display_name) < String(b.display_name))
	return list


func _build_spreads() -> void:
	_spreads.clear()
	for t in TABS.size():
		var all := _entries(t)
		var i := 0
		while true:
			_spreads.append({"tab": t, "entries": all.slice(i, i + PER_PAGE), "total": all, "part": floori(float(i) / PER_PAGE)})
			i += PER_PAGE
			if i >= all.size():
				break


func spread_count() -> int:
	return _spreads.size()


func current_spread() -> int:
	return _spread


func first_spread_of(tab: int) -> int:
	for i in _spreads.size():
		if _spreads[i].tab == tab:
			return i
	return 0


func get_tiles() -> Array[Button]:
	return _tiles


func is_turning() -> bool:
	return _busy


# ================================================================ navegación

## Abre el capítulo `tab` (con paso de hoja si el libro ya está abierto). El contenido cambia al momento.
func show_tab(tab: int) -> void:
	go_to_spread(first_spread_of(clampi(tab, 0, TABS.size() - 1)))


func next_page() -> void:
	go_to_spread(_spread + 1)


func prev_page() -> void:
	go_to_spread(_spread - 1)


func go_to_spread(i: int) -> void:
	i = clampi(i, 0, _spreads.size() - 1)
	if i == _spread and not _tiles.is_empty():
		return
	if not _opened or not is_inside_tree():
		_show_spread(i)
		return
	_target = i
	if not _busy:
		_flip_step()


## Pasa UNA hoja hacia _target; al terminar, si aún no ha llegado, pasa la siguiente (más rápido).
func _flip_step() -> void:
	if _target == _spread:
		return
	var fwd := _target > _spread
	var remaining := absi(_target - _spread)
	_flip_to(_spread + (1 if fwd else -1), fwd, 0.6 if remaining > 1 or _chain else 1.0)


func _show_spread(i: int) -> void:
	_spread = clampi(i, 0, _spreads.size() - 1)
	if not _busy:
		_target = _spread
	var sp: Dictionary = _spreads[_spread]
	_current_tab = int(sp.tab)
	_fill_left(sp)
	var entries: Array = sp.entries
	_pinned = entries[0] if not entries.is_empty() else null
	_show_detail(_pinned)
	_page_num_l.text = "— %d —" % (_spread * 2 + 1)
	_page_num_r.text = "— %d —" % (_spread * 2 + 2)
	_prev_btn.disabled = _spread == 0
	_next_btn.disabled = _spread >= _spreads.size() - 1
	_prev_btn.modulate.a = 0.25 if _prev_btn.disabled else 1.0
	_next_btn.modulate.a = 0.25 if _next_btn.disabled else 1.0
	_style_tabs()
	page_turned.emit(_spread)


# ================================================================ construcción

func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.02, 0.03, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_book = Control.new()
	_book.name = "Book"
	_book.size = BOOK
	_book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_book)

	# Cintas de marcapáginas (detrás del libro: asoman por la derecha)
	for i in TABS.size():
		var b := Button.new()
		b.name = "Tab_%s" % TABS[i]
		b.text = TABS[i]
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.position = Vector2(BOOK.x - 40.0, 70.0 + i * 54.0)
		b.size = Vector2(40.0 + TAB_OUT + 34.0, 42)
		b.add_theme_font_override("font", _font("title_bold"))
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = "Ir al capítulo %s · %s" % [ROMAN[i], TABS[i]]
		b.pressed.connect(show_tab.bind(i))
		_book.add_child(b)
		_tab_buttons.append(b)

	_clip = Control.new()
	_clip.name = "Clip"
	_clip.clip_contents = true
	_clip.size = BOOK
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(_clip)
	var inner := Control.new()
	inner.name = "Inner"
	inner.size = BOOK
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(inner)
	var spread_tex := TextureRect.new()
	spread_tex.name = "Spread"
	spread_tex.texture = load(ART + "book_spread.png")
	spread_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spread_tex.stretch_mode = TextureRect.STRETCH_SCALE
	spread_tex.size = BOOK
	spread_tex.mouse_filter = Control.MOUSE_FILTER_PASS # rueda del ratón → pasar hoja (lo recoge el panel)
	inner.add_child(spread_tex)

	_left = _page(inner, "LeftPage", LEFT_PAGE)
	_right = _page(inner, "RightPage", RIGHT_PAGE)
	_build_left()
	_build_right()

	# Cerrar (botón redondo de cuero, arriba a la derecha)
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "✕"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.size = Vector2(40, 40)
	close_btn.position = Vector2(BOOK.x - 22, -18)
	close_btn.add_theme_font_size_override("font_size", 18)
	_style_round(close_btn, Color("#3a3524"), Color("#c9a35a"), Color("#f2dfae"))
	close_btn.tooltip_text = "Cerrar el Códice (Esc)"
	close_btn.pressed.connect(close)
	_book.add_child(close_btn)


func _page(parent: Control, n: String, r: Rect2) -> Control:
	var p := Control.new()
	p.name = n
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _build_left() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(40, 30)
	v.size = Vector2(LEFT_PAGE.size.x - 74, LEFT_PAGE.size.y - 84)
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(v)
	_chapter_label = _lbl("", "title", 13, INK_SOFT, true)
	v.add_child(_chapter_label)
	_title_label = _lbl("", "title_bold", 30, INK, true)
	_title_label.name = "ChapterTitle"
	v.add_child(_title_label)
	v.add_child(_ornament())
	_count_label = _lbl("", "italic", 15, INK_SOFT, true)
	v.add_child(_count_label)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	v.add_child(gap)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(center)
	_grid = GridContainer.new()
	_grid.name = "CodexGrid"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	center.add_child(_grid)
	_page_num_l = _lbl("", "regular", 14, INK_SOFT, true)
	_page_num_l.position = Vector2(0, LEFT_PAGE.size.y - 34)
	_page_num_l.size = Vector2(LEFT_PAGE.size.x, 20)
	_left.add_child(_page_num_l)
	_prev_btn = _corner_button("PrevPage", "‹  Anterior", true)
	_prev_btn.position = Vector2(18, LEFT_PAGE.size.y - 40)
	_prev_btn.pressed.connect(prev_page)
	_left.add_child(_prev_btn)


func _build_right() -> void:
	var v := VBoxContainer.new()
	v.name = "Detail"
	v.position = Vector2(46, 30)
	v.size = Vector2(RIGHT_PAGE.size.x - 86, RIGHT_PAGE.size.y - 70)
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.add_child(v)
	v.add_child(_lbl("FICHA DE CAMPO", "title", 13, INK_SOFT, true))
	var ic := CenterContainer.new()
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	_icon_frame = PanelContainer.new()
	_icon_frame.custom_minimum_size = Vector2(96, 96)
	_icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.add_child(_icon_frame)
	_detail_icon = _lbl("", "regular", 48, INK, true)
	_detail_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_frame.add_child(_detail_icon)
	_detail_tex = UiKit.icon_rect(null, 80)
	_icon_frame.add_child(_detail_tex)
	_detail_name = _lbl("", "title_bold", 24, INK, true)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_name)
	_detail_meta = _lbl("", "italic", 15, INK_SOFT, true)
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_meta)
	v.add_child(_ornament())
	_detail_desc = _lbl("", "regular", 17, INK, true)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size.x = 300
	v.add_child(_detail_desc)
	_detail_mods = _lbl("", "italic", 15, INK_GREEN, true)
	_detail_mods.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_mods.custom_minimum_size.x = 300
	v.add_child(_detail_mods)
	_detail_stats = GridContainer.new()
	_detail_stats.name = "WeaponStats"
	_detail_stats.columns = 2
	_detail_stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail_stats.add_theme_constant_override("h_separation", 18)
	_detail_stats.add_theme_constant_override("v_separation", 2)
	v.add_child(_detail_stats)
	_page_num_r = _lbl("", "regular", 14, INK_SOFT, true)
	_page_num_r.position = Vector2(0, RIGHT_PAGE.size.y - 34)
	_page_num_r.size = Vector2(RIGHT_PAGE.size.x, 20)
	_right.add_child(_page_num_r)
	_next_btn = _corner_button("NextPage", "Siguiente  ›", false)
	_next_btn.position = Vector2(RIGHT_PAGE.size.x - 18 - 120, RIGHT_PAGE.size.y - 40)
	_next_btn.pressed.connect(next_page)
	_right.add_child(_next_btn)


func _fill_left(sp: Dictionary) -> void:
	var tab: int = int(sp.tab)
	var total: Array = sp.total
	var part: int = int(sp.part)
	var parts: int = maxi(1, ceili(float(total.size()) / PER_PAGE))
	_chapter_label.text = "CAPÍTULO %s" % ROMAN[tab] + ("  ·  %d/%d" % [part + 1, parts] if parts > 1 else "")
	_title_label.text = TABS[tab]
	var unlocked := 0
	for res in total:
		if is_unlocked(res):
			unlocked += 1
	_count_label.text = "%d de %d descubiertos" % [unlocked, total.size()]
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_tiles.clear()
	for res in sp.entries:
		var t := _make_tile(res)
		_grid.add_child(t)
		_tiles.append(t)


func _make_tile(res: Resource) -> Button:
	var open := is_unlocked(res)
	var b := Button.new()
	b.custom_minimum_size = Vector2(TILE, TILE)
	b.focus_mode = Control.FOCUS_NONE
	b.text = UiKit.emo(String(res.get("emoji"))) if open else "🔒"
	if open and res is WeaponData:
		b.text = ""
		b.icon = res.get_icon()
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 27)
	var col: Color = _ink_color(res) if open else Color("#8a7d66")
	var bg: Color = PARCH.lerp(col, 0.14) if open else Color("#d6c7a4")
	b.add_theme_stylebox_override("normal", _tile_style(bg, col, 2))
	b.add_theme_stylebox_override("hover", _tile_style(bg.lightened(0.18), col, 3))
	b.add_theme_stylebox_override("pressed", _tile_style(bg.darkened(0.08), col, 3))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.tooltip_text = ("%s\n%s" % [res.display_name, String(res.description)]) if open else "???  Aún no descubierto"
	b.set_meta("entry", res)
	b.mouse_entered.connect(_show_detail.bind(res))
	b.mouse_exited.connect(func(): _show_detail(_pinned))
	b.pressed.connect(func():
		_pinned = res
		_show_detail(res))
	return b


func _tile_style(bg: Color, border: Color, w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(8)
	sb.shadow_color = Color(0.25, 0.17, 0.07, 0.25)
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(0, 1)
	return sb


func _show_detail(res: Resource) -> void:
	for c in _detail_stats.get_children():
		_detail_stats.remove_child(c)
		c.queue_free()
	_detail_mods.text = ""
	if res == null:
		_detail_icon.text = ""
		_detail_tex.texture = null
		_detail_name.text = ""
		_detail_meta.text = ""
		_detail_desc.text = ""
		_icon_frame.add_theme_stylebox_override("panel", _frame_style(INK_SOFT))
		return
	if not is_unlocked(res):
		_detail_icon.text = "🔒"
		_detail_tex.texture = null
		_detail_name.text = "???"
		_detail_name.add_theme_color_override("font_color", INK_SOFT)
		_detail_meta.text = "Especialidad bloqueada" if res is SpecialtyData else "Aún no descubierto"
		_detail_desc.text = ("🔓 " + SpecialtyProgression.unlock_text(res.id)) if res is SpecialtyData else ""
		_icon_frame.add_theme_stylebox_override("panel", _frame_style(INK_SOFT))
		return
	var rarity: int = _rar(res)
	var col := _ink_color(res)
	_icon_frame.add_theme_stylebox_override("panel", _frame_style(col))
	_detail_icon.text = "" if res is WeaponData else UiKit.emo(String(res.get("emoji")))
	_detail_tex.texture = res.get_icon() if res is WeaponData else null
	_detail_name.text = String(res.display_name)
	_detail_name.add_theme_color_override("font_color", col.darkened(0.15))
	_detail_desc.text = String(res.description)
	var meta := UiKit.rarity_name(rarity)
	var mods := ""
	if res is SpecialtyData:
		var sp := res as SpecialtyData
		var fams: Array[String] = []
		for f in sp.affine_families:
			fams.append(WeaponData.FAMILY_NAMES[clampi(int(f), 0, WeaponData.FAMILY_NAMES.size() - 1)])
		_detail_meta.text = "Especialidad · se elige al subir a Nv. %d · afín a %s" % [TroopCard.SPECIALTY_LEVEL, ", ".join(fams)]
		var smods := "✦ %s: %s" % [sp.passive_name, sp.passive_description]
		if sp.synergy_text != "":
			smods += "\n🤝 " + sp.synergy_text
		_detail_mods.text = smods
		return
	if res is SkillData:
		var s := res as SkillData
		meta += " · Habilidad pasiva (no ocupa hueco)"
		if s.stackable:
			meta += " · Acumulable"
		mods = TroopStats.describe_modifiers(s.modifiers)
	elif res is ItemData:
		var it := res as ItemData
		meta += " · Objeto · %s · ocupa 1 hueco" % it.get_slot_name()
		mods = TroopStats.describe_modifiers(it.modifiers)
	elif res is WeaponData:
		var w := res as WeaponData
		meta += " · Arma · %s" % w.get_family_name()
		_detail_meta.text = meta
		var rows := [
			["Daño", ("%d × %d" % [w.pellets, roundi(w.damage)]) if w.pellets > 1 else str(roundi(w.damage))],
			["Cadencia", "%.1f disparos/s" % w.fire_rate],
			["Alcance", "%d" % roundi(w.attack_range)],
			["Precisión", UiKit.pct(w.accuracy)],
			["Cargador", UiKit.magazine_text(w.magazine)],
		]
		for r in rows:
			_detail_stats.add_child(_lbl(r[0], "title", 13, INK_SOFT, false))
			_detail_stats.add_child(_lbl(r[1], "regular", 16, INK, false))
		return
	_detail_meta.text = meta
	# Sin repetir: los efectos solo se listan si la descripción no los dice ya
	var plain_mods := mods.strip_edges().trim_suffix(".")
	_detail_mods.text = "" if plain_mods == "" or String(res.description).to_lower().contains(plain_mods.to_lower()) else "Efecto: " + mods


func _frame_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PARCH.lerp(col, 0.12)
	sb.border_color = col
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(48)
	sb.shadow_color = Color(0.25, 0.17, 0.07, 0.3)
	sb.shadow_size = 3
	return sb


func _style_tabs() -> void:
	for i in _tab_buttons.size():
		var on := i == _current_tab
		var b := _tab_buttons[i]
		var col: Color = TAB_COLORS[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.12) if on else col.darkened(0.15)
		sb.border_color = Color("#d9b56a") if on else col.darkened(0.4)
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_width_right = 2 if on else 1
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_right = 6
		sb.content_margin_right = 12
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 4
		for st in ["normal", "hover", "pressed"]:
			var s2: StyleBoxFlat = sb.duplicate()
			if st == "hover":
				s2.bg_color = s2.bg_color.lightened(0.1)
			b.add_theme_stylebox_override(st, s2)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", Color("#f6e7c1") if on else Color("#d8c9a5"))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		# la cinta activa asoma más
		b.position.x = BOOK.x - 40.0 + (12.0 if on else 0.0)


func _corner_button(n: String, txt: String, left: bool) -> Button:
	var b := Button.new()
	b.name = n
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(120, 30)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	b.add_theme_font_override("font", _font("title_bold"))
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", INK_GOLD)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", INK_SOFT)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	b.tooltip_text = "Pasar hoja (%s)" % ("←" if left else "→")
	return b


func _style_round(b: Button, bg: Color, border: Color, fg: Color) -> void:
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg.lightened(0.15) if st == "hover" else bg
		sb.border_color = border
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(20)
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 4
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", Color.WHITE)


func _ornament() -> Label:
	return _lbl("———  ✦  ———", "regular", 14, INK_GOLD, true)


func _lbl(text: String, font: String, size: int, color: Color, centered: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font(font))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Fuentes del libro: Cinzel (títulos) y EB Garamond (texto), OFL. Los emojis caen a la fuente del sistema.
static func _font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var file := "EBGaramond.ttf"
	var wght := 450
	match kind:
		"title":
			file = "Cinzel.ttf"
			wght = 500
		"title_bold":
			file = "Cinzel.ttf"
			wght = 700
		"italic":
			file = "EBGaramond-Italic.ttf"
		"bold":
			wght = 650
	var base: FontFile = load(FONT_DIR + file)
	var f := FontVariation.new()
	f.base_font = base
	var ts := TextServerManager.get_primary_interface()
	f.variation_opentype = {ts.name_to_tag("wght"): wght}
	_fonts[kind] = f
	return f


static func _rar(res: Resource) -> int:
	var r = res.get("rarity")
	return int(r) if r != null else 0


## Color de tinta según rareza / especialidad (más oscuro que en la UI para leerse sobre pergamino).
static func _ink_color(res: Resource) -> Color:
	if res is SpecialtyData:
		return (res as SpecialtyData).color.darkened(0.3)
	match _rar(res):
		0: return Color("#5b5040")
		1: return Color("#22579a")
		2: return Color("#6b2f92")
		_: return Color("#a06a08")


# ================================================================ escala y animaciones

func _fit_book() -> void:
	if _book == null:
		return
	var vp := get_viewport_rect().size
	var total := Vector2(BOOK.x + TAB_OUT + 20.0, BOOK.y + 40.0)
	var s := minf(1.0, minf(vp.x * 0.97 / total.x, vp.y * 0.95 / total.y))
	_book.scale = Vector2(s, s)
	_book.position = ((vp - total * s) * 0.5 + Vector2(10, 24) * s).round()
	_book.position.x -= roundf((SPINE - 12.0) * 0.5 * s * _slide)


## Al abrir: aparece el libro cerrado y se levanta la tapa hacia la izquierda.
func _play_open() -> void:
	if not is_inside_tree():
		_opened = true
		return
	_busy = true
	_clip.position.x = SPINE
	_clip.size.x = BOOK.x - SPINE
	(_clip.get_node("Inner") as Control).position.x = -SPINE
	for b in _tab_buttons:
		b.modulate.a = 0.0
	var cover := TextureRect.new()
	cover.name = "Cover"
	cover.texture = load(ART + "book_cover.png")
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_SCALE
	cover.position = Vector2(SPINE - 24.0, 0)
	cover.size = Vector2(BOOK.x - SPINE + 24.0, BOOK.y)
	cover.pivot_offset = Vector2(24.0, BOOK.y * 0.5)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_book.add_child(cover)
	var inside := TextureRect.new() # cara interior: la mitad izquierda del libro abierto
	inside.name = "CoverInside"
	var at := AtlasTexture.new()
	var spread_tex: Texture2D = load(ART + "book_spread.png")
	at.atlas = spread_tex
	at.region = Rect2(0, 0, spread_tex.get_width() * SPINE / BOOK.x, spread_tex.get_height())
	inside.texture = at
	inside.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	inside.stretch_mode = TextureRect.STRETCH_SCALE
	inside.size = Vector2(SPINE, BOOK.y)
	inside.pivot_offset = Vector2(SPINE, BOOK.y * 0.5)
	inside.scale.x = 0.0
	inside.visible = false
	_book.add_child(inside)
	_left.modulate.a = 0.0
	var dim: ColorRect = get_node("Dim")
	dim.modulate.a = 0.0
	_book.modulate.a = 0.0
	# el libro cerrado sale centrado y se desliza a su sitio mientras se abre la tapa
	_slide = 1.0
	_fit_book()
	var slide := create_tween()
	slide.tween_interval(0.30)
	slide.tween_method(func(v: float):
		_slide = v
		_fit_book(), 1.0, 0.0, OPEN_TIME * 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var tw := create_tween()
	tw.tween_property(dim, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(_book, "modulate:a", 1.0, 0.18)
	tw.tween_interval(0.12)
	tw.tween_property(cover, "scale:x", 0.0, OPEN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tw.parallel().tween_property(cover, "modulate", Color(0.6, 0.6, 0.6), OPEN_TIME)
	tw.tween_callback(func():
		cover.queue_free()
		inside.visible = true
		inside.modulate = Color(0.6, 0.6, 0.6))
	tw.tween_property(inside, "scale:x", 1.0, OPEN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(inside, "modulate", Color.WHITE, OPEN_TIME)
	tw.tween_callback(func():
		_clip.position.x = 0
		_clip.size.x = BOOK.x
		(_clip.get_node("Inner") as Control).position.x = 0
		inside.queue_free())
	tw.tween_property(_left, "modulate:a", 1.0, 0.15)
	for b in _tab_buttons:
		tw.parallel().tween_property(b, "modulate:a", 1.0, 0.2)
	tw.tween_callback(func():
		_busy = false
		_opened = true)


## Captura de lo que se ve ahora en un rectángulo del libro (para la hoja que se levanta).
func _snapshot(page: Control) -> Texture2D:
	var vp := get_viewport()
	var img: Image = vp.get_texture().get_image() if vp and vp.get_texture() else null
	if img == null or img.is_empty():
		return null
	var r: Rect2 = vp.get_final_transform() * (page.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, page.size))
	var ri := Rect2i(r.position.round(), r.size.round()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if ri.size.x < 4 or ri.size.y < 4:
		return null
	return ImageTexture.create_from_image(img.get_region(ri))


func _sheet(tex: Texture2D, r: Rect2, pivot_right: bool) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.position = r.position
	t.size = r.size
	t.pivot_offset = Vector2(r.size.x if pivot_right else 0.0, r.size.y * 0.5)
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	_book.add_child(t)
	return t


## Pasa la hoja: la página vieja se levanta desde el borde, gira sobre el lomo y cae al otro lado;
## al posarse, la tinta de la página nueva aparece.
func _flip_to(i: int, forward: bool, speed: float = 1.0) -> void:
	_busy = true
	var ft := FLIP_TIME * speed
	var old_l := _snapshot(_left)
	var old_r := _snapshot(_right)
	var blank_l: Texture2D = load(ART + "book_page_left.png")
	var blank_r: Texture2D = load(ART + "book_page_right.png")
	# Lo que se queda quieto (la página del lado hacia el que cae la hoja) y la hoja que se levanta
	var still_rect := LEFT_PAGE if forward else RIGHT_PAGE
	var lift_rect := RIGHT_PAGE if forward else LEFT_PAGE
	var still := _sheet((old_l if forward else old_r) if (old_l and old_r) else (blank_l if forward else blank_r), still_rect, false)
	var leaf := _sheet((old_r if forward else old_l) if (old_l and old_r) else (blank_r if forward else blank_l), lift_rect, not forward)
	_show_spread(i) # el contenido nuevo ya está debajo
	var tw := create_tween()
	tw.tween_property(leaf, "scale:x", 0.0, ft).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(leaf, "modulate", Color(0.72, 0.68, 0.6), ft)
	tw.tween_callback(func():
		leaf.texture = blank_l if forward else blank_r
		leaf.position = still_rect.position
		leaf.size = still_rect.size
		leaf.pivot_offset = Vector2(still_rect.size.x if forward else 0.0, still_rect.size.y * 0.5))
	tw.tween_property(leaf, "scale:x", 1.0, ft).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(leaf, "modulate", Color.WHITE, ft)
	tw.tween_callback(func(): still.queue_free())
	tw.tween_property(leaf, "modulate:a", 0.0, 0.14 * speed)
	tw.tween_callback(func():
		leaf.queue_free()
		_busy = false
		_chain = _target != _spread
		if _chain:
			_flip_step())
