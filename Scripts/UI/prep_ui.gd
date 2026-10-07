extends CanvasLayer
## Cabecera de la fase de planificación: banner y botón de combate.
## La gestión del ejército vive en troop_roster_ui.gd y troop_detail_panel.gd.

@onready var start_button: Button = $Control/StartButton

@onready var shop_button: Button = $Control/ShopButton
@onready var resources_label: Label = $Control/ResourcesChip/Label

var _refresh_pending: bool = false


func _ready() -> void:
	_apply_style()
	start_button.pressed.connect(_on_start_button_pressed)
	shop_button.pressed.connect(_on_shop_pressed)
	shop_button.tooltip_text = "Compra equipo y tropas, renueva ofertas y vende objetos"
	
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.battle_fight_started.connect(_on_battle_fight_started)
		bus.roster_changed.connect(_request_update)
		bus.roster_changed.connect(_update_resources)
		bus.coins_changed.connect(_on_resources_changed)
		bus.command_points_changed.connect(_on_resources_changed)
	
	get_tree().node_added.connect(_on_tree_changed)
	get_tree().node_removed.connect(_on_tree_changed)
	_request_update()
	_update_resources()


## Cabecera compacta (no tapa la cuadrícula) y botón de combate destacado abajo a la derecha.
func _apply_style() -> void:
	var banner: Control = get_node_or_null("Control/Banner")
	if banner:
		banner.add_theme_stylebox_override("panel", UiKit.style(Color(0.075, 0.085, 0.11, 0.86), Color(0.78, 0.7, 0.44, 0.6), 15, 1, 4))
		var title: Label = banner.get_node_or_null("Label")
		if title:
			title.add_theme_color_override("font_color", Color(0.96, 0.88, 0.6))
	var base := Color(0.72, 0.2, 0.13)
	var states := {
		"normal": UiKit.style(base, Color(1.0, 0.72, 0.4, 0.9), 10, 2, 8),
		"hover": UiKit.style(base.lightened(0.15), Color(1.0, 0.85, 0.55), 10, 2, 8),
		"pressed": UiKit.style(base.darkened(0.2), Color(1.0, 0.72, 0.4, 0.9), 10, 2, 8),
		"disabled": UiKit.style(Color(0.2, 0.21, 0.24, 0.92), Color(0.35, 0.37, 0.42, 0.8), 10, 2, 8),
		"focus": UiKit.style(Color(0, 0, 0, 0), Color(1.0, 0.85, 0.55, 0.6), 10, 1, 8),
	}
	for k in states:
		start_button.add_theme_stylebox_override(k, states[k])
	start_button.add_theme_color_override("font_color", Color(1, 0.97, 0.9))
	start_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	start_button.add_theme_color_override("font_disabled_color", Color(0.55, 0.57, 0.62))


	# Intendencia: espejo de ¡COMBATIR! en tono dorado/ocre militar
	var ocre := Color(0.52, 0.38, 0.1)
	var shop_states := {
		"normal": UiKit.style(ocre, Color(0.95, 0.8, 0.4, 0.9), 10, 2, 8),
		"hover": UiKit.style(ocre.lightened(0.15), Color(1.0, 0.9, 0.55), 10, 2, 8),
		"pressed": UiKit.style(ocre.darkened(0.2), Color(0.95, 0.8, 0.4, 0.9), 10, 2, 8),
		"disabled": UiKit.style(Color(0.2, 0.21, 0.24, 0.92), Color(0.35, 0.37, 0.42, 0.8), 10, 2, 8),
		"focus": UiKit.style(Color(0, 0, 0, 0), Color(1.0, 0.9, 0.55, 0.6), 10, 1, 8),
	}
	for k in shop_states:
		shop_button.add_theme_stylebox_override(k, shop_states[k])
	shop_button.add_theme_color_override("font_color", Color(1, 0.96, 0.8))
	shop_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	var chip: Control = get_node_or_null("Control/ResourcesChip")
	if chip:
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.tooltip_text = "💰 Monedas: se ganan por cada baja enemiga y al vencer. Compran equipo y reclutas en la Intendencia.\n⭐ Puntos de Mando: se ganan al vencer una ronda. Suben de nivel a tus tropas (panel de la tropa)."
		chip.add_theme_stylebox_override("panel", UiKit.style(Color(0.075, 0.085, 0.11, 0.86), Color(0.78, 0.7, 0.44, 0.6), 10, 1, 4))
	resources_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))


func _on_resources_changed(_total: int, _delta: int) -> void:
	_update_resources()


## Ficha compacta con monedas y Puntos de Mando.
func _update_resources() -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	resources_label.text = "💰 %d   ⭐ %d" % [gsm.coins if gsm else 0, gsm.command_points if gsm else 0]


func _on_shop_pressed() -> void:
	if _choice_pending():
		return
	EventBus.shop_requested.emit("equipo")


func _on_tree_changed(node: Node) -> void:
	if node.is_in_group("troops") or node is CharacterBody2D:
		_request_update()


func _request_update() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_update_start_button")


func _update_start_button() -> void:
	_refresh_pending = false
	# La llamada diferida puede llegar cuando la escena de batalla ya ha salido del árbol (cambio de escena)
	if not is_inside_tree():
		return
	var deployed: int = 0
	for troop in get_tree().get_nodes_in_group("troops"):
		if is_instance_valid(troop) and not troop.is_queued_for_deletion() \
				and troop.team == troop.Team.PLAYER and not troop.has_meta("is_drag_preview"):
			deployed += 1
	start_button.disabled = (deployed == 0)
	start_button.tooltip_text = "" if deployed > 0 else "Despliega al menos una tropa para combatir"


func _on_battle_fight_started() -> void:
	hide()
	queue_free()


## true si hay una elección de mejora abierta (no se puede combatir ni abrir la Intendencia mientras tanto).
func _choice_pending() -> bool:
	for m in get_tree().get_nodes_in_group("level_up_modal"):
		if is_instance_valid(m) and m.is_open():
			return true
	return false


func _on_start_button_pressed() -> void:
	if _choice_pending():
		return
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.battle_fight_started.emit()
