class_name SpecialtyTreePanel
extends Control
## Árbol de Especialidades (meta-progresión entre runs). Pantalla completa superpuesta, como el Códice.
##  - Izquierda: las 7 especialidades (emoji, nombre y rango k/4) para elegir.
##  - Derecha: la elegida y su árbol VERTICAL: el rango 0 (la especialidad) abajo y las mejoras 1..4 hacia
##    arriba, unidas por una línea. Las mejoras se compran en orden con Medallas de mando (🏅).
##  - Ratón y táctil: botones de ≥ 48 px y toda la información visible sin pasar el ratón.
## Uso: `var p := SpecialtyTreePanel.new(); add_child(p)` (se pone a pantalla completa solo).
## Se cierra con ✕ o Esc → emite `closed` y se libera.

signal closed

const PANEL_SIZE := Vector2(1000, 600)
const LIST_W := 215.0
const LIST_BTN_H := 52.0
const INFO_W := 190.0
const ACTION_W := 176.0
const CIRCLE := 44.0
const ROW_H := 66.0
const LINK_H := 14.0
const LINK_W := 6.0
const ROW_PAD := 10.0

## Especialidad mostrada a la derecha.
var selected_id: String = ""

var _list_buttons: Dictionary = {} # id -> Button
var _medals_label: Label
var _info_emoji: Label
var _info_name: Label
var _info_desc: Label
var _info_passive: Label
var _info_rank: Label
var _tree_box: VBoxContainer
var _rows: Array[Control] = []    # índice = rango (0 abajo … MAX_RANK arriba)
var _unlock_button: Button = null
var _claim_button: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	var pm := _pm()
	if pm and pm.has_signal("progress_changed"):
		pm.progress_changed.connect(refresh)
	var specs := GameContent.specialties()
	select_specialty(specs[0].id if not specs.is_empty() else "")


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


# ---------------------------------------------------------------- API

func select_specialty(id: String) -> void:
	if GameContent.find_specialty(id) == null:
		return
	selected_id = GameContent.find_specialty(id).id
	refresh()


## Compra el siguiente rango de la especialidad elegida. Devuelve true si se desbloqueó.
func unlock_selected() -> bool:
	var pm := _pm()
	if pm == null or selected_id == "":
		return false
	return pm.unlock_next(selected_id) # progress_changed → refresh()


## Filas del árbol de la especialidad elegida, de ABAJO a ARRIBA: [0] = rango 0 (la especialidad),
## [1..MAX_RANK] = mejoras. Cada fila tiene meta "rank" y "state" ("base", "unlocked", "next", "locked").
func get_node_rows() -> Array:
	return _rows.duplicate()


## Botón "Desbloquear" de la fila siguiente (null si la especialidad está al máximo).
func get_unlock_button() -> Button:
	return _unlock_button


## Botón "Desbloquear especialidad" (hito alcanzado, aún sin desbloquear). null si no aplica.
func get_claim_button() -> Button:
	return _claim_button


## Desbloquea la especialidad seleccionada si su hito ya se alcanzó. Devuelve true si se desbloqueó.
func claim_selected() -> bool:
	var pm := _pm()
	if pm == null or not pm.has_method("claim_specialty"):
		return false
	var ok: bool = pm.claim_specialty(selected_id)
	refresh()
	return ok


func refresh() -> void:
	if _tree_box == null:
		return
	var pm := _pm()
	var medals: int = int(pm.medals) if pm else 0
	_medals_label.text = "🏅 %d" % medals
	for id in _list_buttons:
		_style_list_button(_list_buttons[id], id)
	_refresh_info()
	_rebuild_tree()


# ---------------------------------------------------------------- construcción

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UiKit.panel(UiKit.BG, UiKit.GOLD, 14, 2, 16)
	panel.name = "Panel"
	panel.custom_minimum_size = PANEL_SIZE
	center.add_child(panel)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 8)
	panel.add_child(main)

	# Cabecera
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	main.add_child(header)
	var title := UiKit.label("🎖️ ESPECIALIDADES", 26, UiKit.GOLD)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var mbox := UiKit.panel(Color(0.22, 0.17, 0.05), UiKit.GOLD, 10, 1, 8)
	mbox.name = "MedalsBox"
	mbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(mbox)
	_medals_label = UiKit.label("🏅 0", 22, UiKit.GOLD)
	_medals_label.name = "MedalsLabel"
	mbox.add_child(_medals_label)
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(52, 48)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 20)
	UiKit.style_button(close_btn, UiKit.PANEL_2, UiKit.BORDER, UiKit.TEXT, 8)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	main.add_child(UiKit.label("Gana 🏅 Medallas de mando al terminar cada partida y gástalas en mejoras permanentes para tus tropas de cada especialidad.", 13, Color("#C8C8B8")))

	# Cuerpo
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	main.add_child(body)

	var list := VBoxContainer.new()
	list.name = "SpecialtyList"
	list.custom_minimum_size.x = LIST_W
	list.add_theme_constant_override("separation", 6)
	body.add_child(list)
	for sp in GameContent.specialties():
		var b := _make_list_button(sp)
		list.add_child(b)
		_list_buttons[sp.id] = b

	var detail := UiKit.panel(UiKit.PANEL, UiKit.BORDER, 12, 1, 14)
	detail.name = "Detail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 12)
	detail.add_child(dh)

	var info := VBoxContainer.new()
	info.name = "Info"
	info.custom_minimum_size.x = INFO_W
	info.add_theme_constant_override("separation", 6)
	dh.add_child(info)
	_info_emoji = UiKit.label("", 44)
	_info_emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_info_emoji)
	_info_name = UiKit.label("", 22)
	_info_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_info_name)
	_info_rank = UiKit.label("", 14, UiKit.MUTED)
	_info_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_info_rank)
	info.add_child(HSeparator.new())
	_info_desc = UiKit.wrap_label("", 13, UiKit.TEXT, INFO_W)
	info.add_child(_info_desc)
	_info_passive = UiKit.wrap_label("", 13, UiKit.UP, INFO_W)
	info.add_child(_info_passive)

	var vsep := VSeparator.new()
	dh.add_child(vsep)

	_tree_box = VBoxContainer.new()
	_tree_box.name = "Tree"
	_tree_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_box.alignment = BoxContainer.ALIGNMENT_END # el rango 0 queda pegado abajo
	_tree_box.add_theme_constant_override("separation", 0)
	dh.add_child(_tree_box)


func _make_list_button(sp: SpecialtyData) -> Button:
	var b := Button.new()
	b.name = "Spec_%s" % sp.id
	b.custom_minimum_size = Vector2(LIST_W, LIST_BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.pressed.connect(select_specialty.bind(sp.id))
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var n := UiKit.label("%s %s" % [UiKit.emo(sp.emoji), sp.display_name], 17, sp.color)
	n.name = "NameLabel"
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(n)
	var r := UiKit.label("", 15, UiKit.MUTED)
	r.name = "RankLabel"
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(r)
	return b


func _style_list_button(b: Button, id: String) -> void:
	var sp := GameContent.find_specialty(id)
	var on := id == selected_id
	var rank := _rank(id)
	b.set_pressed_no_signal(on)
	var bg: Color = Color(sp.color.r * 0.28, sp.color.g * 0.28, sp.color.b * 0.28) if on else UiKit.PANEL_2
	UiKit.style_button(b, bg, sp.color if on else Color(sp.color, 0.35), UiKit.TEXT, 8)
	var rl: Label = b.find_child("RankLabel", true, false)
	var open := SpecialtyProgression.is_unlocked(id)
	var nl: Label = b.find_child("NameLabel", true, false)
	nl.text = "%s %s" % ["🔒" if not open else UiKit.emo(sp.emoji), sp.display_name]
	nl.add_theme_color_override("font_color", sp.color if open else Color(UiKit.MUTED, 0.8))
	b.tooltip_text = "" if open else "Bloqueada: " + SpecialtyProgression.unlock_text(id)
	if not open:
		var pmc := _pm()
		var ready: bool = pmc != null and pmc.has_method("is_specialty_claimable") and pmc.is_specialty_claimable(id)
		rl.text = "¡Lista!" if ready else "🔒"
		rl.add_theme_color_override("font_color", UiKit.GOLD if ready else UiKit.MUTED)
		if ready:
			nl.text = "🔓 %s" % sp.display_name
			b.tooltip_text = "Hito conseguido: pulsa para desbloquearla"
		return
	rl.text = "%d/%d" % [rank, SpecialtyProgression.MAX_RANK]
	rl.add_theme_color_override("font_color", UiKit.GOLD if rank >= SpecialtyProgression.MAX_RANK else (UiKit.TEXT if rank > 0 else UiKit.MUTED))


func _rank(id: String) -> int:
	var pm := _pm()
	return int(pm.get_rank(id)) if pm else 0


func _refresh_info() -> void:
	var sp := GameContent.find_specialty(selected_id)
	if sp == null:
		return
	_info_emoji.text = UiKit.emo(sp.emoji)
	_info_name.text = sp.display_name
	_info_name.add_theme_color_override("font_color", sp.color)
	var rank := _rank(sp.id)
	_info_rank.text = "Rango %d / %d%s" % [rank, SpecialtyProgression.MAX_RANK, "  ·  ¡completo!" if rank >= SpecialtyProgression.MAX_RANK else ""]
	if not SpecialtyProgression.is_unlocked(sp.id):
		var pmc := _pm()
		if pmc and pmc.has_method("is_specialty_claimable") and pmc.is_specialty_claimable(sp.id):
			_info_rank.text = "✨ ¡Lista para desbloquear!\n%s ✓" % SpecialtyProgression.unlock_text(sp.id)
		else:
			_info_rank.text = "🔒 Bloqueada\n%s" % SpecialtyProgression.unlock_text(sp.id)
	_info_desc.text = sp.description
	_info_passive.text = "✦ Pasiva: %s" % sp.passive_name


# ---------------------------------------------------------------- árbol

func _rebuild_tree() -> void:
	for c in _tree_box.get_children():
		_tree_box.remove_child(c)
		c.queue_free()
	_rows.clear()
	_unlock_button = null
	_claim_button = null
	var sp := GameContent.find_specialty(selected_id)
	if sp == null:
		return
	var rank := _rank(sp.id)
	var rows_top_down: Array[Control] = []
	for r in range(SpecialtyProgression.MAX_RANK, -1, -1):
		var state := "base" if r == 0 else ("unlocked" if r <= rank else ("next" if r == rank + 1 else "locked"))
		if not SpecialtyProgression.is_unlocked(sp.id): # especialidad aún sin desbloquear
			state = "sealed" if r == 0 else "locked"
			var pmc := _pm()
			if r == 0 and pmc and pmc.has_method("is_specialty_claimable") and pmc.is_specialty_claimable(sp.id):
				state = "claimable"
		var row := _make_row(sp, r, state)
		_tree_box.add_child(row)
		rows_top_down.append(row)
		if r > 0:
			# Tramo de línea entre este nodo y el de abajo: encendido si este nodo está desbloqueado
			_tree_box.add_child(_make_link(sp.color if r <= rank else UiKit.BORDER, r <= rank))
	rows_top_down.reverse()
	_rows.assign(rows_top_down)


func _make_link(col: Color, lit: bool) -> Control:
	var m := MarginContainer.new()
	m.name = "Link"
	m.add_theme_constant_override("margin_left", int(ROW_PAD + CIRCLE / 2.0 - LINK_W / 2.0))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(LINK_W, LINK_H)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	line.color = col if lit else Color(col, 0.6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(line)
	return m


func _make_row(sp: SpecialtyData, r: int, state: String) -> Control:
	var lit := state == "base" or state == "unlocked"
	var col := sp.color
	var bg: Color
	var border: Color
	match state:
		"base", "unlocked":
			bg = Color(col.r * 0.2, col.g * 0.2, col.b * 0.2) + Color(0.03, 0.03, 0.04)
			border = col
		"next":
			bg = UiKit.PANEL_2
			border = UiKit.GOLD
		_:
			bg = Color(0.1, 0.11, 0.14)
			border = Color(UiKit.BORDER, 0.6)
	var row := UiKit.panel(bg, border, 10, 2, ROW_PAD)
	row.name = "Rank%d" % r
	row.custom_minimum_size.y = ROW_H
	row.set_meta("rank", r)
	row.set_meta("state", state)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)

	# Círculo del nodo
	var circle := UiKit.panel(col if lit else Color(0.16, 0.17, 0.21), col if not state in ["locked", "sealed", "claimable"] else UiKit.BORDER, int(CIRCLE / 2.0), 2, 0)
	circle.custom_minimum_size = Vector2(CIRCLE, CIRCLE)
	circle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(circle)
	var ctext := "✓" if lit else ("🔓" if state == "claimable" else ("🔒" if state in ["locked", "sealed"] else str(r)))
	if state == "base":
		ctext = UiKit.emo(sp.emoji)
	var cl := UiKit.label(ctext, 20 if state != "base" else 18, Color(0.05, 0.06, 0.08) if lit and state != "base" else UiKit.TEXT)
	cl.name = "CircleLabel"
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	circle.add_child(cl)

	# Texto
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_theme_constant_override("separation", 0)
	h.add_child(tv)
	var title_text: String
	var desc_text: String
	if state == "base":
		title_text = "Especialidad desbloqueada ✓"
		desc_text = "%s · %s" % [sp.display_name, sp.passive_name]
	elif state == "sealed":
		title_text = "Especialidad bloqueada"
		desc_text = "🔓 " + SpecialtyProgression.unlock_text(sp.id)
	elif state == "claimable":
		title_text = "¡Hito conseguido!"
		desc_text = "✓ " + SpecialtyProgression.unlock_text(sp.id)
	else:
		var n := SpecialtyProgression.node(sp.id, r)
		title_text = str(n.get("name", "Mejora"))
		desc_text = str(n.get("description", ""))
		var mods: Dictionary = n.get("modifiers", {})
		if not mods.is_empty():
			var md := TroopStats.describe_modifiers(mods)
			if not desc_text.to_lower().contains(md.to_lower()):
				desc_text = md if desc_text == "" or desc_text == SpecialtyProgression.PENDING_TEXT else "%s (%s)" % [desc_text, md]
	var tl := UiKit.label(title_text, 16, col if lit else (UiKit.TEXT if state == "next" else UiKit.MUTED))
	tl.name = "NameLabel"
	tl.clip_text = true
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(tl)
	var dl := UiKit.wrap_label(desc_text, 12, UiKit.MUTED if state != "locked" else Color(UiKit.MUTED, 0.6))
	dl.name = "DescLabel"
	dl.max_lines_visible = 2
	tv.add_child(dl)

	# Estado / acción (derecha)
	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_constant_override("separation", 2)
	right.custom_minimum_size.x = ACTION_W
	h.add_child(right)
	match state:
		"base":
			var s := UiKit.label("Base", 14, col)
			s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			right.add_child(s)
		"unlocked":
			var s2 := UiKit.label("✓ Desbloqueada", 15, col)
			s2.name = "StatusLabel"
			s2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			right.add_child(s2)
		"next":
			var cost := SpecialtyProgression.cost(sp.id, r)
			var pm := _pm()
			var medals: int = int(pm.medals) if pm else 0
			var b := Button.new()
			b.name = "UnlockButton"
			b.text = "Desbloquear (🏅 %d)" % cost
			b.custom_minimum_size = Vector2(ACTION_W, 48)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 15)
			UiKit.style_button(b, Color(0.3, 0.22, 0.08), UiKit.GOLD, Color(1.0, 0.92, 0.6), 8)
			b.disabled = pm == null or not pm.can_unlock_next(sp.id)
			b.pressed.connect(unlock_selected)
			right.add_child(b)
			_unlock_button = b
			if b.disabled:
				var why := UiKit.label("Te faltan %d 🏅" % maxi(0, cost - medals), 12, UiKit.DOWN)
				why.name = "ReasonLabel"
				why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				right.add_child(why)
				row.custom_minimum_size.y = ROW_H + 10
		"claimable":
			var cb := Button.new()
			cb.name = "ClaimButton"
			cb.text = "🔓 Desbloquear"
			cb.custom_minimum_size = Vector2(ACTION_W, 48)
			cb.focus_mode = Control.FOCUS_NONE
			cb.add_theme_font_size_override("font_size", 15)
			UiKit.style_button(cb, Color(0.18, 0.32, 0.18), UiKit.UP, Color.WHITE, 8)
			cb.pressed.connect(claim_selected)
			right.add_child(cb)
			_claim_button = cb
		"sealed":
			var s5 := UiKit.label("🔒 Bloqueada", 15, UiKit.MUTED)
			s5.name = "StatusLabel"
			s5.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			right.add_child(s5)
		_:
			var s3 := UiKit.label("🔒 🏅 %d" % SpecialtyProgression.cost(sp.id, r), 15, UiKit.MUTED)
			s3.name = "StatusLabel"
			s3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			right.add_child(s3)
			var s4 := UiKit.label("Antes: rango %d" % (r - 1), 11, Color(UiKit.MUTED, 0.7))
			s4.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			right.add_child(s4)
	return row
