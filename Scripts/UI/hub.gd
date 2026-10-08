extends Control
## Cuartel general: escena entre el menú principal y las partidas.
##  - ▶ Run normal (la partida roguelite de siempre).
##  - 📖 Códice.
##  - Bóveda de veteranos: hasta 5 tropas guardadas fuera de las runs (ProfileManager). Solo se consiguen
##    venciendo al Jefe Final. Clic en una → su ficha (el mismo panel de la planificación, en modo Cuartel).
##  - Modo nuevo: bloqueado hasta reunir los 5 veteranos (el modo aún no existe).

const DETAIL_PANEL_SCRIPT = preload("res://Scripts/UI/troop_detail_panel.gd")
const MAIN_MENU_SCENE := "res://Scenes/UI/main_menu.tscn"
const RUN_START_SCENE := "res://Scenes/UI/troop_selection_screen.tscn"
const NEW_MODE_NAME := "Modo Veteranos"
const SLOT_W := 196.0

var change_scene_enabled: bool = true # los tests lo desactivan
var detail_panel: CanvasLayer
var codex: CodexPanel = null

var run_button: Button
var codex_button: Button
var new_mode_button: Button
var back_button: Button
var _slots_box: HBoxContainer
var _vault_title: Label
var _stats_label: Label
var _toast: Label


func _ready() -> void:
	_build()
	detail_panel = DETAIL_PANEL_SCRIPT.new()
	detail_panel.name = "TroopDetailPanel"
	add_child(detail_panel)
	detail_panel.vault_card_changed.connect(_on_vault_card_changed)
	detail_panel.vault_remove_confirmed.connect(_on_vault_remove_confirmed)
	var pm := _pm()
	if pm:
		pm.vault_changed.connect(refresh)
	refresh()


func _pm() -> Node:
	return get_node_or_null("/root/ProfileManager")


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not detail_panel.visible and codex == null:
		_go_main_menu()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- construcción

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "←  Menú principal"
	back_button.custom_minimum_size = Vector2(200, 40)
	back_button.position = Vector2(20, 18)
	back_button.add_theme_font_size_override("font_size", 15)
	UiKit.style_button(back_button, UiKit.PANEL_2, UiKit.BORDER, UiKit.TEXT, 8)
	back_button.pressed.connect(_go_main_menu)
	add_child(back_button)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE # la columna es muy ancha y tapaba parte del botón ←
	center.add_child(v)

	var title := UiKit.label("CUARTEL GENERAL", 40, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	v.add_child(title)
	var sub := UiKit.label("Prepara tu próxima operación", 15, UiKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	# Acciones principales
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 18)
	v.add_child(actions)
	run_button = _big_button("RunButton", "▶  Run normal", "Partida roguelite: recluta, mejora y aguanta hasta el Jefe Final.",
		Color(0.18, 0.32, 0.18), UiKit.UP, Color.WHITE)
	run_button.pressed.connect(start_normal_run)
	actions.add_child(run_button)
	codex_button = _big_button("CodexButton", "📖  Códice", "Todas las habilidades, objetos, armas y especialidades del juego",
		Color(0.3, 0.22, 0.08), UiKit.GOLD, Color(1.0, 0.92, 0.6))
	codex_button.pressed.connect(open_codex)
	actions.add_child(codex_button)

	# Bóveda de veteranos
	var vault_panel := UiKit.panel(UiKit.PANEL, UiKit.BORDER, 12, 1, 16)
	v.add_child(vault_panel)
	var vv := VBoxContainer.new()
	vv.add_theme_constant_override("separation", 8)
	vault_panel.add_child(vv)
	_vault_title = UiKit.label("", 18, UiKit.TEXT)
	vv.add_child(_vault_title)
	vv.add_child(UiKit.label("Cada vez que vences al Jefe Final eliges una de tus tropas para traerla aquí. Clic en un veterano para ver su ficha.", 13, UiKit.MUTED))
	_slots_box = HBoxContainer.new()
	_slots_box.name = "VaultSlots"
	_slots_box.add_theme_constant_override("separation", 12)
	_slots_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vv.add_child(_slots_box)
	_stats_label = UiKit.label("", 12, UiKit.MUTED)
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vv.add_child(_stats_label)

	# Modo nuevo (bloqueado)
	new_mode_button = Button.new()
	new_mode_button.name = "NewModeButton"
	new_mode_button.custom_minimum_size = Vector2(0, 54)
	new_mode_button.add_theme_font_size_override("font_size", 19)
	new_mode_button.pressed.connect(_on_new_mode_pressed)
	v.add_child(new_mode_button)

	_toast = UiKit.label("", 16, UiKit.GOLD)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = 24
	_toast.offset_bottom = 54
	# El botón ← va encima de todo: si no, la columna central (añadida después) se come los clics
	# de su mitad derecha.
	move_child(back_button, -1)


func _gap(h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size.y = h
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _big_button(node_name: String, text: String, tip: String, bg: Color, border: Color, font: Color) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(300, 64)
	b.add_theme_font_size_override("font_size", 22)
	UiKit.style_button(b, bg, border, font, 10)
	return b


# ---------------------------------------------------------------- refresco

func refresh() -> void:
	var pm := _pm()
	var vault: Array = pm.vault if pm else []
	var n_slots: int = ProfileManager.VAULT_SIZE
	_vault_title.text = "🏛  VETERANOS  ·  %d/%d" % [vault.size(), n_slots]
	for c in _slots_box.get_children():
		_slots_box.remove_child(c)
		c.queue_free()
	for i in n_slots:
		_slots_box.add_child(_make_slot(vault[i] if i < vault.size() else null, i))
	var wins: int = pm.final_boss_wins if pm else 0
	_stats_label.text = "Jefes Finales derrotados: %d" % wins

	var unlocked: bool = pm != null and pm.is_new_mode_unlocked()
	if unlocked:
		new_mode_button.text = "⚔  %s" % NEW_MODE_NAME
		new_mode_button.tooltip_text = "Desbloqueado con tus 5 veteranos. ¡Próximamente!"
		UiKit.style_button(new_mode_button, Color(0.28, 0.12, 0.32), Color(0.8, 0.5, 1.0), Color.WHITE, 10)
	else:
		new_mode_button.text = "🔒  %s  ·  reúne %d veteranos (%d/%d)" % [NEW_MODE_NAME, n_slots, vault.size(), n_slots]
		new_mode_button.tooltip_text = "Bloqueado: vence al Jefe Final %d veces y guarda una tropa cada vez." % n_slots
		UiKit.style_button(new_mode_button, Color(0.1, 0.105, 0.13), Color(0.3, 0.32, 0.38), Color(0.5, 0.53, 0.6), 10)
	new_mode_button.disabled = not unlocked


func _make_slot(card: TroopCard, index: int) -> Control:
	if card == null:
		var empty := UiKit.panel(Color(0.085, 0.095, 0.12), Color(0.3, 0.33, 0.4, 0.6), 10, 1, 10)
		empty.name = "Slot%d" % index
		empty.custom_minimum_size = Vector2(SLOT_W, 230)
		var ev := VBoxContainer.new()
		ev.alignment = BoxContainer.ALIGNMENT_CENTER
		ev.add_theme_constant_override("separation", 6)
		empty.add_child(ev)
		var lock := UiKit.label("🔒", 34, Color(0.45, 0.48, 0.55))
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ev.add_child(lock)
		var t := UiKit.label("Hueco libre", 15, Color(0.55, 0.58, 0.65))
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ev.add_child(t)
		var h := UiKit.wrap_label("Vence al Jefe Final para traer un veterano", 12, Color(0.45, 0.48, 0.55), SLOT_W - 24)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ev.add_child(h)
		return empty

	var s := TroopStats.compute(card)
	var b := Button.new()
	b.name = "Slot%d" % index
	b.custom_minimum_size = Vector2(SLOT_W, 230)
	b.tooltip_text = "%s · Nv. %d\nClic para ver su ficha" % [card.get_title(), card.level]
	var spc := UiKit.specialty_color(card)
	UiKit.style_button(b, UiKit.PANEL_2, Color(spc, 0.75), UiKit.TEXT, 10)
	b.pressed.connect(open_vault_troop.bind(index))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -10
	box.offset_top = 10
	box.offset_bottom = -10
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(0, 78)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UiKit.troop_texture(card)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var lines: Array = [
		[card.unit_name, 18, UiKit.TEXT],
		["%s · Nv. %d" % [UiKit.specialty_text(card), card.level], 12, spc],
		["❤ %s   💥 %s" % [UiKit.health_text(s), UiKit.damage_text(s)], 13, UiKit.TEXT],
		[s.weapon.display_name, 13, UiKit.rarity_color(s.weapon.rarity), s.weapon.get_icon()],
		[_items_text(card), 13, UiKit.MUTED],
		["⭐ %d habilidades" % card.skills.size(), 12, Color(0.75, 0.85, 1.0)],
	]
	for ln in lines:
		if ln.size() > 3:
			box.add_child(UiKit.icon_label(ln[3], ln[0], ln[1], ln[2], true))
			continue
		var l := UiKit.label(ln[0], ln[1], ln[2])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	return b


func _items_text(card: TroopCard) -> String:
	var parts: Array[String] = []
	for it in card.items:
		if it:
			parts.append(UiKit.emo(it.emoji))
	for i in TroopCard.MAX_ITEM_SLOTS - parts.size():
		parts.append("○")
	return "🎒 " + " ".join(parts)


# ---------------------------------------------------------------- acciones

func open_vault_troop(index: int) -> void:
	var pm := _pm()
	if pm == null or index < 0 or index >= pm.vault.size():
		return
	detail_panel.open_vault_card(pm.vault[index])


func _on_vault_card_changed(_card: TroopCard) -> void:
	var pm := _pm()
	if pm:
		pm.notify_changed() # guarda y refresca las fichas


func _on_vault_remove_confirmed(card: TroopCard) -> void:
	var pm := _pm()
	if pm and pm.remove_troop(card): # guarda y refresca las fichas
		_show_toast("🗑 %s ya no está en el Cuartel" % card.unit_name)


func start_normal_run() -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm:
		gsm.reset_run()
	if change_scene_enabled:
		get_tree().change_scene_to_file(RUN_START_SCENE)


func open_codex() -> CodexPanel:
	if codex and is_instance_valid(codex):
		return codex
	codex = CodexPanel.new()
	codex.name = "Codex"
	codex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	codex.closed.connect(func(): codex = null)
	add_child(codex)
	return codex


func _on_new_mode_pressed() -> void:
	_show_toast("⚔ %s: ¡próximamente!" % NEW_MODE_NAME)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := _toast.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _go_main_menu() -> void:
	if change_scene_enabled:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
