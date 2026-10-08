extends CanvasLayer
## Fin de la run. Derrota: reiniciar / Cuartel / menú.
## Victoria (Jefe Final): antes de salir eliges UNA de tus tropas (tablero + reserva, máx. 6) para guardarla
## en el Cuartel (ProfileManager). Con la bóveda llena, eliges a qué veterano sustituye, o no guardas ninguna.
## Siempre: se muestran las Medallas de mando (🏅) ganadas en la run (se ganan al derrotar cada jefe).

@export_file("*.tscn") var main_menu_scene_path: String = "res://Scenes/UI/main_menu.tscn"
const HUB_SCENE := "res://Scenes/UI/command_center.tscn" # v7: el Centro de mando sustituye al Cuartel
const CAND_W := 150.0

@onready var title_label: Label = $Control/Panel/VBoxContainer/TitleLabel
@onready var restart_button: Button = $Control/Panel/VBoxContainer/RestartButton
@onready var main_menu_button: Button = $Control/Panel/VBoxContainer/MainMenuButton
var hub_button: Button

# --- Guardar veterano (solo victoria) ---
var candidates: Array[TroopCard] = []
var selected_index: int = -1
var replace_index: int = -1
var vault_decided: bool = true # en derrota no hay nada que decidir
var stored_card: TroopCard = null
var _vault_box: VBoxContainer
var _cand_row: HBoxContainer
var _replace_title: Label
var _replace_row: HBoxContainer
var _confirm_button: Button
var _skip_button: Button
var _vault_info: Label
# --- Nombre del veterano (se escribe al guardarlo; en móvil sale el teclado del sistema) ---
const NAME_MAX_LEN := 16
var _name_layer: Control
var _name_edit: LineEdit
var _name_ok: Button

# --- Medallas de mando (meta-progresión) ---
## Medallas concedidas por esta run (se calculan y dan una sola vez en setup()).
var medals_awarded: int = 0
## Especialidades desbloqueadas en esta run (se anuncian junto a las medallas).
var unlocked_specialties: Array = []
var medals_label: Label
var _medals_given: bool = false


func _ready() -> void:
	hub_button = Button.new()
	hub_button.name = "HubButton"
	# Botones de salida en una fila: Nueva partida · Cuartel · Menú principal
	var box: VBoxContainer = $Control/Panel/VBoxContainer
	var nav := HBoxContainer.new()
	nav.name = "NavRow"
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	box.add_child(nav)
	for b in [restart_button, hub_button, main_menu_button]:
		if b.get_parent():
			b.get_parent().remove_child(b)
		nav.add_child(b)
	restart_button.pressed.connect(_on_restart_button_pressed)
	hub_button.pressed.connect(_on_hub_button_pressed)
	main_menu_button.pressed.connect(_on_main_menu_button_pressed)


func _pm() -> Node:
	return get_node_or_null("/root/ProfileManager")


func setup(is_victory: bool) -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	var round_number: int = gsm.current_stage if gsm else 1
	if is_victory:
		title_label.text = "¡VICTORIA!\nJefe derrotado en la ronda %d" % round_number
	else:
		title_label.text = "¡DERROTA!\nHas llegado a la ronda %d" % round_number
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(is_victory)
	_award_medals(is_victory, gsm)
	if is_victory:
		var pm := _pm()
		if pm:
			pm.register_final_boss_win()
		if gsm:
			candidates = gsm.get_army_cards()
		if pm and not candidates.is_empty():
			vault_decided = false
			_build_vault_picker()
	_place_medals_label()
	_update_nav()


## Muestra las Medallas de mando ganadas en la run. Ya se sumaron al perfil al caer cada jefe
## (GameStateManager.apply_victory_rewards); aquí solo se resumen.
func _award_medals(_is_victory: bool, gsm) -> void:
	if _medals_given:
		return
	_medals_given = true
	medals_awarded = int(gsm.run_medals) if gsm and "run_medals" in gsm else 0
	var pm := _pm()
	medals_label = UiKit.label("", 18, UiKit.GOLD)
	medals_label.name = "MedalsLabel"
	medals_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	medals_label.mouse_filter = Control.MOUSE_FILTER_PASS # para el tooltip
	medals_label.add_theme_constant_override("outline_size", 4)
	medals_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	var total: int = int(pm.medals) if pm else medals_awarded
	medals_label.text = "🏅 +%d Medallas de mando en esta partida (total %d)" % [medals_awarded, total]
	medals_label.tooltip_text = SpecialtyProgression.medals_hint() + "\nSe gastan en el árbol de Especialidades."


func _place_medals_label() -> void:
	if medals_label == null:
		return
	var box: VBoxContainer = $Control/Panel/VBoxContainer
	if medals_label.get_parent() == null:
		box.add_child(medals_label)
	# v7.1: especialidades desbloqueadas en esta run
	var pm := _pm()
	if pm and pm.has_method("take_recent_unlocks"):
		var unlocked: Array = pm.take_recent_unlocks()
		if not unlocked.is_empty():
			var names: Array[String] = []
			for sp in unlocked:
				names.append(sp.display_name)
			medals_label.text += "   ·   🔓 Listas en el Centro de mando: %s" % ", ".join(names)
			unlocked_specialties = unlocked
	box.move_child(medals_label, title_label.get_index() + 1)


## Estilo común (UiKit): panel opaco con borde dorado (victoria) o rojo (derrota) y botones claros.
func _style(is_victory: bool) -> void:
	var accent: Color = UiKit.GOLD if is_victory else UiKit.DOWN
	var dim: ColorRect = $Control/ColorRect
	dim.color = Color(0.02, 0.025, 0.04, 0.9)
	var panel: Panel = $Control/Panel
	var sz := Vector2(780, 290) # +40 por la línea de Medallas de mando
	panel.custom_minimum_size = sz
	panel.offset_left = -sz.x / 2
	panel.offset_right = sz.x / 2
	panel.offset_top = -sz.y / 2
	panel.offset_bottom = sz.y / 2
	panel.add_theme_stylebox_override("panel", UiKit.style(UiKit.BG, accent, 12, 2, 0))
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", UiKit.UP if is_victory else UiKit.DOWN)
	title_label.add_theme_constant_override("outline_size", 6)
	title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	for b in [restart_button, hub_button, main_menu_button]:
		b.custom_minimum_size = Vector2(230, 46)
		b.add_theme_font_size_override("font_size", 17)
	restart_button.text = "↻  Nueva partida" if is_victory else "↻  Reiniciar run"
	hub_button.text = "🏛  Centro de mando"
	main_menu_button.text = "Menú principal"
	UiKit.style_button(restart_button, Color(0.18, 0.32, 0.18), UiKit.UP, Color.WHITE, 8)
	UiKit.style_button(hub_button, Color(0.3, 0.22, 0.08), UiKit.GOLD, Color(1.0, 0.92, 0.6), 8)
	UiKit.style_button(main_menu_button, UiKit.PANEL_2, UiKit.BORDER, UiKit.TEXT, 8)


func _resize_panel(sz: Vector2) -> void:
	var panel: Panel = $Control/Panel
	panel.custom_minimum_size = sz
	panel.offset_left = -sz.x / 2
	panel.offset_right = sz.x / 2
	panel.offset_top = -sz.y / 2
	panel.offset_bottom = sz.y / 2


# ---------------------------------------------------------------- guardar veterano

func _build_vault_picker() -> void:
	var pm := _pm()
	var box: VBoxContainer = $Control/Panel/VBoxContainer
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	_vault_box = VBoxContainer.new()
	_vault_box.name = "VaultPicker"
	_vault_box.add_theme_constant_override("separation", 8)
	box.add_child(_vault_box)
	box.move_child(_vault_box, title_label.get_index() + 1)

	var head := UiKit.label("🏛  Elige un soldado para el Cuartel  ·  veteranos %d/%d" % [pm.vault.size(), ProfileManager.VAULT_SIZE], 17, UiKit.GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vault_box.add_child(head)
	var hint := UiKit.label("Se guarda fuera de las runs. Con %d veteranos se desbloquea un modo de juego nuevo." % ProfileManager.VAULT_SIZE, 12, UiKit.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vault_box.add_child(hint)

	_cand_row = HBoxContainer.new()
	_cand_row.name = "Candidates"
	_cand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cand_row.add_theme_constant_override("separation", 8)
	_vault_box.add_child(_cand_row)
	for i in candidates.size():
		_cand_row.add_child(_candidate_button(candidates[i], i))

	_replace_title = UiKit.label("Cuartel lleno: ¿a quién sustituye?", 14, UiKit.DOWN)
	_replace_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_replace_title.visible = false
	_vault_box.add_child(_replace_title)
	_replace_row = HBoxContainer.new()
	_replace_row.name = "ReplaceRow"
	_replace_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_replace_row.add_theme_constant_override("separation", 8)
	_replace_row.visible = false
	_vault_box.add_child(_replace_row)
	if pm.is_vault_full():
		for i in pm.vault.size():
			var v: TroopCard = pm.vault[i]
			var rb := _small_card_button(v, "Sustituir")
			rb.name = "Replace%d" % i
			rb.pressed.connect(select_replace.bind(i))
			_replace_row.add_child(rb)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	_vault_box.add_child(actions)
	_confirm_button = Button.new()
	_confirm_button.name = "ConfirmStoreButton"
	_confirm_button.custom_minimum_size = Vector2(280, 42)
	_confirm_button.add_theme_font_size_override("font_size", 16)
	UiKit.style_button(_confirm_button, Color(0.3, 0.22, 0.08), UiKit.GOLD, Color(1.0, 0.92, 0.6), 8)
	_confirm_button.pressed.connect(request_store)
	actions.add_child(_confirm_button)
	_skip_button = Button.new()
	_skip_button.name = "SkipStoreButton"
	_skip_button.text = "No guardar ninguno"
	_skip_button.custom_minimum_size = Vector2(180, 42)
	_skip_button.add_theme_font_size_override("font_size", 14)
	UiKit.style_button(_skip_button, UiKit.PANEL_2, UiKit.BORDER, UiKit.MUTED, 8)
	_skip_button.pressed.connect(skip_store)
	_skip_button.visible = pm.is_vault_full() # con huecos libres siempre se guarda uno
	actions.add_child(_skip_button)
	_vault_info = UiKit.label("", 15, UiKit.UP)
	_vault_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vault_info.visible = false
	_vault_box.add_child(_vault_info)

	title_label.add_theme_font_size_override("font_size", 26)
	_resize_panel(Vector2(maxf(1000.0, candidates.size() * (CAND_W + 8) + 80), 636 if pm.is_vault_full() else 500))
	_refresh_picker()


func _small_card_button(card: TroopCard, action: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CAND_W, 110)
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	var s := TroopStats.compute(card)
	b.tooltip_text = "%s · Nv. %d\n%s · %d habilidades\n%s" % [card.get_title(), card.level, s.weapon.display_name, card.skills.size(), action]
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -6
	v.offset_top = 6
	v.offset_bottom = -6
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(0, 46)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UiKit.troop_texture(card)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon)
	for ln in [[card.unit_name, 15, UiKit.TEXT],
			["%s · Nv. %d" % [UiKit.specialty_text(card), card.level], 11, UiKit.specialty_color(card)],
			["❤ %s  💥 %s" % [UiKit.health_text(s), UiKit.damage_text(s)], 11, UiKit.MUTED, s.weapon.get_icon()]]:
		if ln.size() > 3:
			var row := UiKit.icon_label(ln[3], ln[0], ln[1], ln[2], true)
			v.add_child(row)
			continue
		var l := UiKit.label(ln[0], ln[1], ln[2])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	return b


func _candidate_button(card: TroopCard, i: int) -> Button:
	var b := _small_card_button(card, "Clic para elegirlo")
	b.name = "Candidate%d" % i
	b.pressed.connect(select_candidate.bind(i))
	return b


func select_candidate(i: int) -> void:
	if vault_decided or i < 0 or i >= candidates.size():
		return
	selected_index = i
	_refresh_picker()


func select_replace(i: int) -> void:
	var pm := _pm()
	if vault_decided or pm == null or i < 0 or i >= pm.vault.size():
		return
	replace_index = i
	_refresh_picker()


## Botón "Guardar": antes de guardarlo pide el nombre del veterano.
func request_store() -> void:
	var pm := _pm()
	if vault_decided or pm == null or selected_index < 0:
		return
	if pm.is_vault_full() and replace_index < 0:
		return
	_open_name_dialog(candidates[selected_index].unit_name)


func is_name_dialog_open() -> bool:
	return _name_layer != null and _name_layer.visible


func _build_name_dialog() -> void:
	_name_layer = Control.new()
	_name_layer.name = "NameDialog"
	_name_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	$Control.add_child(_name_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_layer.add_child(center)
	var pc := UiKit.panel(UiKit.PANEL, UiKit.GOLD, 12, 2, 18)
	center.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	var t := UiKit.label("🏛  ¿Cómo se llamará este veterano?", 20, UiKit.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var hint := UiKit.label("Así aparecerá en su tubo criogénico. Máximo %d letras." % NAME_MAX_LEN, 13, UiKit.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.max_length = NAME_MAX_LEN
	_name_edit.placeholder_text = "Nombre del soldado"
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.custom_minimum_size = Vector2(360, 48)
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.virtual_keyboard_enabled = true   # móvil: abre el teclado del sistema
	_name_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_name_edit.select_all_on_focus = true
	_name_edit.text_changed.connect(func(_t): _validate_name())
	_name_edit.text_submitted.connect(func(_t): _accept_name())
	v.add_child(_name_edit)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.custom_minimum_size = Vector2(150, 42)
	UiKit.style_button(cancel, UiKit.PANEL_2, UiKit.BORDER, UiKit.MUTED, 8)
	cancel.pressed.connect(_close_name_dialog)
	row.add_child(cancel)
	_name_ok = Button.new()
	_name_ok.name = "NameOkButton"
	_name_ok.text = "🏛  Guardar"
	_name_ok.custom_minimum_size = Vector2(190, 42)
	_name_ok.add_theme_font_size_override("font_size", 16)
	UiKit.style_button(_name_ok, Color(0.3, 0.22, 0.08), UiKit.GOLD, Color(1.0, 0.92, 0.6), 8)
	_name_ok.pressed.connect(_accept_name)
	row.add_child(_name_ok)


func _open_name_dialog(current: String) -> void:
	if _name_layer == null:
		_build_name_dialog()
	_name_edit.text = current
	_validate_name()
	_name_layer.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()
	if _name_edit.has_method("edit"):
		_name_edit.call("edit") # muestra el teclado virtual en móvil


func _close_name_dialog() -> void:
	if _name_layer:
		_name_layer.visible = false
		_name_edit.release_focus()


func _clean_name(t: String) -> String:
	return t.strip_edges().substr(0, NAME_MAX_LEN)


func _validate_name() -> void:
	if _name_ok:
		_name_ok.disabled = _clean_name(_name_edit.text) == ""


func _accept_name() -> void:
	var n := _clean_name(_name_edit.text)
	if n == "":
		return
	_close_name_dialog()
	confirm_store(n)


func _unhandled_key_input(event: InputEvent) -> void:
	if is_name_dialog_open() and event.is_action_pressed("ui_cancel"):
		_close_name_dialog()
		get_viewport().set_input_as_handled()


## Guarda la tropa elegida en el Cuartel (con el nombre escrito, si se da). Devuelve true si se guardó.
func confirm_store(new_name: String = "") -> bool:
	var pm := _pm()
	if vault_decided or pm == null or selected_index < 0:
		return false
	var full: bool = pm.is_vault_full()
	if full and replace_index < 0:
		return false
	var card := candidates[selected_index]
	if _clean_name(new_name) != "":
		card.unit_name = _clean_name(new_name)
	if not pm.store_troop(card, replace_index if full else -1):
		return false
	stored_card = card
	vault_decided = true
	_vault_info.text = "✔ %s se une al Cuartel  ·  veteranos %d/%d%s" % [card.unit_name, pm.vault.size(), ProfileManager.VAULT_SIZE,
		"  ·  ¡modo nuevo desbloqueado!" if pm.is_new_mode_unlocked() else ""]
	_vault_info.visible = true
	_refresh_picker()
	_update_nav()
	return true


func skip_store() -> void:
	if vault_decided:
		return
	vault_decided = true
	_vault_info.text = "No has guardado a nadie: tus veteranos siguen igual."
	_vault_info.add_theme_color_override("font_color", UiKit.MUTED)
	_vault_info.visible = true
	_refresh_picker()
	_update_nav()


func _refresh_picker() -> void:
	if _cand_row == null:
		return
	var pm := _pm()
	var full: bool = pm != null and pm.is_vault_full() and stored_card == null
	for i in _cand_row.get_child_count():
		var b := _cand_row.get_child(i) as Button
		b.set_pressed_no_signal(i == selected_index)
		b.disabled = vault_decided and i != selected_index
		var sel := i == selected_index
		UiKit.style_button(b, Color(0.3, 0.24, 0.08) if sel else UiKit.PANEL_2, UiKit.GOLD if sel else UiKit.BORDER, UiKit.TEXT, 8)
	_replace_title.visible = full and selected_index >= 0 and not vault_decided
	_replace_row.visible = _replace_title.visible
	for i in _replace_row.get_child_count():
		var rb := _replace_row.get_child(i) as Button
		rb.set_pressed_no_signal(i == replace_index)
		var on := i == replace_index
		UiKit.style_button(rb, Color(0.32, 0.1, 0.08) if on else UiKit.PANEL_2, UiKit.DOWN if on else UiKit.BORDER, UiKit.TEXT, 8)
	if vault_decided:
		_confirm_button.visible = false
		_skip_button.visible = false
		return
	if selected_index < 0:
		_confirm_button.text = "Elige un soldado"
		_confirm_button.disabled = true
	elif full and replace_index < 0:
		_confirm_button.text = "Elige a quién sustituye"
		_confirm_button.disabled = true
	else:
		_confirm_button.text = "🏛  Guardar a %s" % candidates[selected_index].unit_name
		_confirm_button.disabled = false


## Los botones de salida esperan a que se decida el veterano (así no se pierde por un clic).
func _update_nav() -> void:
	for b in [restart_button, hub_button, main_menu_button]:
		b.disabled = not vault_decided
		b.tooltip_text = "" if vault_decided else "Primero elige qué soldado va al Cuartel"


# ---------------------------------------------------------------- navegación

func _on_restart_button_pressed() -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm:
		gsm.reset_run()
	get_tree().change_scene_to_file("res://Scenes/UI/troop_selection_screen.tscn")


func _on_hub_button_pressed() -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm:
		gsm.reset_run()
	get_tree().change_scene_to_file(HUB_SCENE)


func _on_main_menu_button_pressed() -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm:
		gsm.reset_run()
	if not main_menu_scene_path.is_empty():
		get_tree().change_scene_to_file(main_menu_scene_path)
	else:
		push_error("Main menu scene path not set!")
