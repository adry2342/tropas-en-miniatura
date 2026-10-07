class_name CodexPanel
extends Control
## Códice (librito del menú principal): todas las habilidades, objetos y armas del juego en casillas.
##  - Pasar el ratón por una casilla muestra su ficha (y un tooltip); hacer clic la deja fijada.
##  - Preparado para el futuro: `is_unlocked()` decide qué está bloqueado (🔒 y "???").
##    De momento todo está desbloqueado.

signal closed

const TILE := 66.0
const COLUMNS := 8
const TABS := ["Habilidades", "Objetos", "Armas", "Especialidades"]

var _tab_buttons: Array[Button] = []
var _grid: GridContainer
var _count_label: Label
var _detail_icon: Label
var _detail_name: Label
var _detail_meta: Label
var _detail_desc: Label
var _detail_mods: Label
var _current_tab: int = 0
var _pinned: Resource = null
var _tiles: Array[Button] = []


## Futuro: progreso del jugador (p. ej. habilidades vistas en una partida). Ahora todo está desbloqueado.
static func is_unlocked(res: Resource) -> bool:
	if res is SpecialtyData: # v7.1: las especialidades se desbloquean con hitos del juego
		return SpecialtyProgression.is_unlocked(res.id)
	return true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	show_tab(0)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	closed.emit()
	queue_free()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UiKit.panel(UiKit.BG, UiKit.GOLD, 14, 2, 18)
	panel.custom_minimum_size = Vector2(1000, 560)
	center.add_child(panel)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	panel.add_child(main)

	# Cabecera: título, pestañas y cerrar
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	main.add_child(header)
	header.add_child(UiKit.label("📖 CÓDICE", 26, UiKit.GOLD))
	var gap := Control.new()
	gap.custom_minimum_size.x = 16
	header.add_child(gap)
	for i in TABS.size():
		var b := Button.new()
		b.name = "Tab_%s" % TABS[i]
		b.text = TABS[i]
		b.custom_minimum_size = Vector2(118, 34)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(show_tab.bind(i))
		header.add_child(b)
		_tab_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_count_label = UiKit.label("", 13, UiKit.MUTED)
	header.add_child(_count_label)
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(38, 34)
	close_btn.focus_mode = Control.FOCUS_NONE
	UiKit.style_button(close_btn, UiKit.PANEL_2, UiKit.BORDER, UiKit.TEXT, 8)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	main.add_child(UiKit.label("Pasa el ratón por una casilla para ver qué hace; haz clic para dejarla fijada.", 13, Color("#C8C8B8")))

	# Cuerpo: casillas a la izquierda, ficha a la derecha
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	main.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLUMNS * (TILE + 8.0) + 16.0, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "CodexGrid"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)

	var detail := UiKit.panel(UiKit.PANEL, UiKit.BORDER, 12, 1, 16)
	detail.name = "Detail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	detail.add_child(dv)
	_detail_icon = UiKit.label("", 46, UiKit.TEXT)
	_detail_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(_detail_icon)
	_detail_name = UiKit.label("", 20, UiKit.TEXT)
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_detail_name)
	_detail_meta = UiKit.label("", 13, UiKit.MUTED)
	_detail_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_detail_meta)
	dv.add_child(HSeparator.new())
	_detail_desc = UiKit.wrap_label("", 14, UiKit.TEXT, 260.0)
	dv.add_child(_detail_desc)
	_detail_mods = UiKit.wrap_label("", 13, UiKit.UP, 260.0)
	dv.add_child(_detail_mods)


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


func show_tab(tab: int) -> void:
	_current_tab = clampi(tab, 0, TABS.size() - 1)
	for i in _tab_buttons.size():
		var on := i == _current_tab
		UiKit.style_button(_tab_buttons[i], Color(0.32, 0.25, 0.05) if on else UiKit.PANEL_2, UiKit.GOLD if on else UiKit.BORDER,
				Color(1.0, 0.92, 0.6) if on else UiKit.MUTED, 8)
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_tiles.clear()
	var entries := _entries(_current_tab)
	var unlocked := 0
	for res in entries:
		if is_unlocked(res):
			unlocked += 1
		var t := _make_tile(res)
		_grid.add_child(t)
		_tiles.append(t)
	_count_label.text = "%d / %d descubiertos" % [unlocked, entries.size()]
	_pinned = entries[0] if not entries.is_empty() else null
	_show_detail(_pinned)


func get_tiles() -> Array[Button]:
	return _tiles


func _make_tile(res: Resource) -> Button:
	var open := is_unlocked(res)
	var b := Button.new()
	b.custom_minimum_size = Vector2(TILE, TILE)
	b.focus_mode = Control.FOCUS_NONE
	b.text = UiKit.emo(String(res.get("emoji"))) if open else "🔒"
	b.add_theme_font_size_override("font_size", 28)
	var col: Color = (_tile_color(res)) if open else UiKit.BORDER
	UiKit.style_button(b, Color(col.r * 0.14, col.g * 0.14, col.b * 0.14) + Color(0.05, 0.05, 0.06), col, UiKit.TEXT, 10, 4)
	b.tooltip_text = ("%s\n%s" % [res.display_name, String(res.description)]) if open else "???  Aún no descubierto"
	b.set_meta("entry", res)
	b.mouse_entered.connect(_show_detail.bind(res))
	b.mouse_exited.connect(func(): _show_detail(_pinned))
	b.pressed.connect(func():
		_pinned = res
		_show_detail(res))
	return b


func _show_detail(res: Resource) -> void:
	if res == null:
		_detail_icon.text = ""
		_detail_name.text = ""
		_detail_meta.text = ""
		_detail_desc.text = ""
		_detail_mods.text = ""
		return
	if not is_unlocked(res):
		_detail_icon.text = "🔒"
		_detail_name.text = "???"
		_detail_name.add_theme_color_override("font_color", UiKit.MUTED)
		_detail_meta.text = "Especialidad bloqueada" if res is SpecialtyData else "Aún no descubierto"
		_detail_desc.text = ("🔓 " + SpecialtyProgression.unlock_text(res.id)) if res is SpecialtyData else ""
		_detail_mods.text = ""
		return
	var rarity: int = _rar(res)
	_detail_icon.text = UiKit.emo(String(res.get("emoji")))
	_detail_name.text = String(res.display_name)
	_detail_name.add_theme_color_override("font_color", _tile_color(res))
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
		if s.specialty_id != "":
			var sp := GameContent.find_specialty(s.specialty_id)
			meta += "\nSolo %s" % (sp.display_name if sp else s.specialty_id)
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
		mods = "Daño %s · %.1f disp/s · alcance %d · precisión %s · cargador %s" % [
			("%d×%d" % [w.pellets, roundi(w.damage)]) if w.pellets > 1 else str(roundi(w.damage)),
			w.fire_rate, roundi(w.attack_range), UiKit.pct(w.accuracy), UiKit.magazine_text(w.magazine)]
	_detail_meta.text = meta
	# Sin repetir: los efectos solo se listan si la descripción no los dice ya
	var plain_mods := mods.strip_edges().trim_suffix(".")
	_detail_mods.text = "" if plain_mods == "" or String(res.description).to_lower().contains(plain_mods.to_lower()) else "Efecto: " + mods


static func _rar(res: Resource) -> int:
	var r = res.get("rarity")
	return int(r) if r != null else 0


static func _tile_color(res: Resource) -> Color:
	if res is SpecialtyData:
		return (res as SpecialtyData).color
	return UiKit.rarity_color(_rar(res))

