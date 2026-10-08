extends CanvasLayer
## Ejército: único panel de tropas de la fase de planificación (abajo, centrado).
## Muestra TODAS las tropas: las del tablero y las de la reserva (más los objetos sueltos).
##  - Clic en una tarjeta: abre su submenú (ver, mejorar).
##  - Arrastrar una tarjeta de reserva al tablero: la despliega.
##  - Arrastrar una tropa del tablero a este panel (o botón del submenú): la retira a la reserva.

const TROOP_SCENE_PATH := "res://Scenes/Troops/troop.tscn" # se carga en tiempo de ejecución
const SLOTS: int = 6
const CARD_SIZE := Vector2(106, 98)
const CLICK_TOLERANCE: float = 8.0

var panel: PanelContainer
var _cards: HBoxContainer
var _title: Label
var _gold_label: Label
var _refresh_pending: bool = false

var dragging_resource: Resource = null
var drag_preview_node: Node = null
var _press_screen_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	layer = 5
	_build_ui()
	panel.add_to_group("troop_return_zone")
	
	EventBus.roster_changed.connect(_request_refresh)
	EventBus.coins_changed.connect(func(_t: int, _d: int): _request_refresh())
	EventBus.command_points_changed.connect(func(_t: int, _d: int): _request_refresh())
	EventBus.battle_fight_started.connect(_on_battle_fight_started)
	get_tree().node_added.connect(_on_tree_changed)
	get_tree().node_removed.connect(_on_tree_changed)
	
	_request_refresh()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	
	panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -370.0
	panel.offset_right = 370.0
	panel.offset_top = -162.0
	panel.offset_bottom = -8.0
	panel.add_theme_stylebox_override("panel", UiKit.style(Color(0.075, 0.085, 0.11, 0.94), Color(0.3, 0.34, 0.42, 0.9), 10, 1, 0))
	root.add_child(panel)
	
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)
	
	var header := HBoxContainer.new()
	vbox.add_child(header)
	
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 14)
	header.add_child(_title)
	
	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 13)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_gold_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_gold_label.tooltip_text = "💰 Monedas: se ganan por cada baja enemiga y al vencer. Compran equipo y reclutas en la Intendencia.\n⭐ Puntos de Mando: se ganan al vencer una ronda. Suben de nivel a tus tropas (panel de la tropa)."
	_gold_label.visible = false # recursos ya en la ficha de la izquierda (se mantiene el texto)
	header.add_child(_gold_label)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 6)
	scroll.add_child(_cards)


func _on_tree_changed(node: Node) -> void:
	if node.has_meta("is_drag_preview"):
		return
	if node.is_in_group("troops") or node is CharacterBody2D:
		_request_refresh()


func _request_refresh() -> void:
	# Agrupa varios cambios en el mismo frame y espera a que la tropa termine de configurarse
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_refresh")


func _is_troop_card(res: Resource) -> bool:
	return res is TroopCard


func _refresh() -> void:
	_refresh_pending = false
	if not is_inside_tree():
		return
	
	var gsm = get_node_or_null("/root/GameStateManager")
	_gold_label.text = "💰 %d  ⭐ %d" % [gsm.coins if gsm else 0, gsm.command_points if gsm else 0]
	
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	
	var deployed: int = 0
	var total: int = 0
	for node in get_tree().get_nodes_in_group("troops"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.team != node.Team.PLAYER or node.has_meta("is_drag_preview"):
			continue
		_cards.add_child(_make_deployed_card(node))
		deployed += 1
		total += 1
	
	var items: Array = []
	if gsm:
		for res in gsm.player_bench:
			if res is TroopCard:
				_cards.add_child(_make_reserve_card(res))
				total += 1
			elif res is ItemData or res is WeaponData:
				items.append(res)
	
	for i in range(maxi(0, SLOTS - total)):
		_cards.add_child(_make_empty_slot())
	
	for res in items:
		_cards.add_child(_make_item_card(res))
	_fit_panel_width(_cards.get_child_count())
	
	var max_deployed: int = gsm.MAX_DEPLOYED_TROOPS if gsm else SLOTS
	_title.text = "🎖️ EJÉRCITO  ·  En tablero %d/%d  ·  Reserva %d  ·  Inventario %d" % [deployed, max_deployed, total - deployed, items.size()]


## Ajusta el ancho del panel al número de tarjetas (hasta casi todo el ancho de la pantalla).
func _fit_panel_width(count: int) -> void:
	var need: float = count * (CARD_SIZE.x + 6.0) - 6.0 + 18.0
	var max_w: float = get_viewport().get_visible_rect().size.x - 24.0
	var w: float = clampf(need, 740.0, max_w)
	panel.offset_left = -w * 0.5
	panel.offset_right = w * 0.5


## Hueco libre del ejército: al pulsarlo se abre la tienda de reclutamiento.
func _make_empty_slot() -> Control:
	var slot := Button.new()
	slot.set_meta("empty_slot", true)
	slot.custom_minimum_size = CARD_SIZE
	slot.tooltip_text = "Reclutar una tropa nueva con monedas"
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.1, 0.13, 0.6)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.35, 0.35, 0.42, 0.7)
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.16, 0.2, 0.14, 0.85)
	hover.border_color = Color(1.0, 0.85, 0.2, 0.9)
	slot.add_theme_stylebox_override("normal", normal)
	slot.add_theme_stylebox_override("hover", hover)
	slot.add_theme_stylebox_override("pressed", hover)
	slot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var l := Label.new()
	l.text = "Vacío\n➕ Reclutar"
	l.modulate = Color(0.6, 0.6, 0.65)
	l.add_theme_font_size_override("font_size", 11)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(l)
	slot.pressed.connect(func(): EventBus.recruit_shop_requested.emit())
	return slot


## Construye una tarjeta de tropa (tablero o reserva) a partir de su TroopCard.
func _make_troop_card(c: TroopCard, texture: Texture2D, deployed: bool) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = CARD_SIZE
	var border: Color = Color(0.45, 0.9, 0.5, 0.85) if deployed else Color(1.0, 0.8, 0.35, 0.7)
	UiKit.style_button(btn, Color(0.13, 0.145, 0.185), border, UiKit.TEXT, 8, 4)
	var w: WeaponData = c.get_weapon() if c else null
	if c:
		btn.tooltip_text = "%s · Nv. %d\n%s\nObjetos %d/%d · Habilidades %d" % [c.get_title(), c.level,
				w.display_name if w else "Sin arma", c.items.size(), TroopCard.MAX_ITEM_SLOTS, c.skills.size()]

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 4
	vbox.offset_right = -4
	vbox.offset_top = 3
	vbox.offset_bottom = -3
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", -1)
	btn.add_child(vbox)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 4)
	vbox.add_child(top)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = texture if texture else UiKit.troop_texture(c)
	top.add_child(icon)
	if w:
		top.add_child(UiKit.icon_rect(w.get_icon(), 28))
	else:
		var we := _small_label("✊", 18, Color.WHITE)
		we.clip_text = false
		we.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		we.custom_minimum_size = Vector2(26, 0)
		top.add_child(we)

	vbox.add_child(_small_label(c.unit_name if c else "Tropa", 12, Color.WHITE))
	vbox.add_child(_small_label(c.get_specialty_name() if c else "Recluta", 10, UiKit.specialty_color(c)))
	vbox.add_child(_small_label("Nv. %d  %s" % [c.level if c else 1, UiKit.slots_text(c) if c else "○○○"], 10, Color(1.0, 0.75, 0.4)))
	vbox.add_child(_small_label("● Tablero" if deployed else "📦 Reserva", 13, border))
	return btn


func _small_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_deployed_card(troop: CharacterBody2D) -> Control:
	var c = troop.get("card")
	var card := _make_troop_card(c if c is TroopCard else null, null, true)
	card.set_meta("card", c)
	card.pressed.connect(func(): EventBus.troop_inspect_requested.emit(troop))
	return card


func _make_reserve_card(res: TroopCard) -> Control:
	var card := _make_troop_card(res, null, false)
	card.set_meta("card", res)
	card.gui_input.connect(func(event): _on_card_gui_input(event, res))
	return card


func _make_item_card(res: Resource) -> Control:
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.set_meta("item", res)
	UiKit.style_button(card, Color(0.2, 0.15, 0.08), Color(1.0, 0.58, 0.18, 0.7), UiKit.TEXT, 8, 4)
	var is_weapon: bool = res is WeaponData
	var kind: String = "Arma" if is_weapon else "Objeto"
	var slot_txt: String = res.get_family_name() if is_weapon else res.get_slot_name()
	card.tooltip_text = "%s (%s)\n%s\nArrástralo sobre una tropa del tablero o equípalo desde su submenú." % [res.display_name, slot_txt, res.description]
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 4
	vbox.offset_right = -4
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 0)
	card.add_child(vbox)
	vbox.add_child(_small_label(UiKit.emo(res.emoji), 24, Color.WHITE))
	var nl := _small_label(res.display_name, 11, UiKit.rarity_color(res.rarity).lerp(Color.WHITE, 0.3))
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	nl.clip_text = false
	nl.custom_minimum_size = Vector2(CARD_SIZE.x - 10.0, 0)
	vbox.add_child(nl)
	vbox.add_child(_small_label("%s · %s" % [kind, slot_txt], 9, Color(1.0, 0.7, 0.35)))
	card.gui_input.connect(func(event): _on_card_gui_input(event, res))
	return card


# ---------- Arrastre desde la reserva ----------

func _on_card_gui_input(event: InputEvent, res: Resource) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if GameStateManager.ui_blocking:
				return
			dragging_resource = res
			_press_screen_pos = get_viewport().get_mouse_position()
			_create_drag_preview(res)
		elif dragging_resource:
			_drop_resource()


func _create_drag_preview(res: Resource) -> void:
	_cleanup_preview()
	var battle_scene = get_tree().current_scene
	if _is_troop_card(res) and battle_scene:
		drag_preview_node = load(TROOP_SCENE_PATH).instantiate()
		drag_preview_node.set_meta("is_drag_preview", true) # Ni el ejército ni la cuadrícula lo cuentan
		battle_scene.add_child(drag_preview_node)
		drag_preview_node.team = drag_preview_node.Team.PLAYER
		drag_preview_node.setup(res)
		drag_preview_node.modulate.a = 0.6
		drag_preview_node.set_physics_process(false)
		drag_preview_node.global_position = drag_preview_node.get_global_mouse_position()
	elif res is WeaponData:
		var row := UiKit.icon_label(res.get_icon(), res.display_name, 16, Color(1.0, 0.85, 0.2))
		add_child(row)
		drag_preview_node = row
		row.global_position = row.get_global_mouse_position()
	else:
		var label := Label.new()
		label.text = "%s %s" % [UiKit.emo(String(res.get("emoji"))) if res.get("emoji") else "🎁", res.display_name]
		label.modulate = Color(1.0, 0.85, 0.2)
		add_child(label)
		drag_preview_node = label
		label.global_position = label.get_global_mouse_position()


func _input(event: InputEvent) -> void:
	if not drag_preview_node:
		return
	if event is InputEventMouseMotion:
		drag_preview_node.global_position = drag_preview_node.get_global_mouse_position()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drop_resource()


func _is_over_panel() -> bool:
	return panel.get_global_rect().has_point(get_viewport().get_mouse_position())


func _drop_resource() -> void:
	if not dragging_resource:
		_cleanup_preview()
		return
	
	var res: Resource = dragging_resource
	dragging_resource = null
	_cleanup_preview()
	
	# Soltar sobre este mismo panel: si apenas se movió es un clic (abre el submenú); si no, cancela
	if _is_over_panel():
		var moved: float = get_viewport().get_mouse_position().distance_to(_press_screen_pos)
		if moved < CLICK_TOLERANCE and _is_troop_card(res):
			EventBus.troop_card_inspect_requested.emit(res)
		return
	
	var battle_scene = get_tree().current_scene
	if not battle_scene:
		return
	var mouse_pos: Vector2 = battle_scene.get_global_mouse_position()
	var gsm = get_node_or_null("/root/GameStateManager")
	
	if _is_troop_card(res):
		if gsm and not gsm.can_deploy_more():
			_show_toast("Máximo %d tropas en el tablero. Retira una a la reserva." % gsm.MAX_DEPLOYED_TROOPS)
			return
		var grid = battle_scene.find_child("DeploymentGrid", true, false)
		var final_pos: Vector2 = mouse_pos
		if grid and grid.has_method("get_nearest_free_position"):
			final_pos = grid.get_nearest_free_position(mouse_pos)
			if final_pos == Vector2.INF:
				_show_toast("¡El tablero está lleno! Retira una tropa a la reserva.")
				return
		
		var deployed_troop = load(TROOP_SCENE_PATH).instantiate()
		battle_scene.add_child(deployed_troop)
		deployed_troop.team = deployed_troop.Team.PLAYER
		deployed_troop.setup(res)
		deployed_troop.global_position = final_pos
		if gsm:
			gsm.remove_from_bench(res)
		print("Tropa desplegada desde la reserva: ", res.display_name)
	else:
		# Objeto: equipar a la tropa del tablero más cercana
		var closest_troop: CharacterBody2D = null
		var min_dist: float = 60.0
		for troop in get_tree().get_nodes_in_group("troops"):
			if troop.team == troop.Team.PLAYER and not troop.has_meta("is_drag_preview"):
				var dist: float = mouse_pos.distance_to(troop.global_position)
				if dist < min_dist:
					min_dist = dist
					closest_troop = troop
		if closest_troop and res is WeaponData and gsm:
			var wcard = closest_troop.get("card")
			if wcard is TroopCard:
				if gsm.equip_weapon_from_bench(wcard, res):
					print("Arma equipada a ", wcard.unit_name)
				else:
					_show_toast("%s ya tiene %s." % [wcard.unit_name, res.display_name])
		elif closest_troop and res is ItemData and gsm:
			var target_card = closest_troop.get("card")
			if target_card is TroopCard and gsm.equip_item_from_bench(target_card, res):
				print("Objeto equipado a ", target_card.unit_name)
			elif target_card is TroopCard:
				if target_card.items.size() >= TroopCard.MAX_ITEM_SLOTS:
					_show_toast("%s ya tiene los %d huecos ocupados." % [target_card.unit_name, TroopCard.MAX_ITEM_SLOTS])
				else:
					_show_toast("%s no puede llevar %s (solo 1 de munición y 1 de armadura, sin repetir)." % [target_card.unit_name, res.display_name])


func _show_toast(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(get_viewport().get_visible_rect().size.x, 0)
	label.position = Vector2(0, 90)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	
	var tween := label.create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func _cleanup_preview() -> void:
	if is_instance_valid(drag_preview_node):
		drag_preview_node.queue_free()
	drag_preview_node = null


func _on_battle_fight_started() -> void:
	_cleanup_preview()
	hide()
	queue_free()
