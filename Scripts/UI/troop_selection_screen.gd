extends Control
## Selección inicial (SPEC v2 §9): 3 reclutas aleatorios gratis con la misma ficha que la tienda.
## "Comenzar" reinicia la partida, añade el elegido a la reserva y va al mapa.

const OFFER_COUNT := 3
const CARD_W := 238.0

var offers: Array[TroopCard] = []
var selected_card: TroopCard = null
var change_scene_on_start: bool = true # el test lo desactiva

var _cards_box: HBoxContainer
var _start_button: Button
var _panels: Array[PanelContainer] = []


func _ready() -> void:
	_build_ui()
	generate_offers()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.095)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)

	var title := UiKit.label("ELIGE TU PRIMER RECLUTA", 30, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UiKit.label("Elige UNO. Todos empiezan con la misma Vida y sin objeto: cambian el nombre, el Daño y el arma. Al subir a Nv. %d elegirá especialidad." % TroopCard.SPECIALTY_LEVEL, 14, UiKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	_cards_box = HBoxContainer.new()
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_box.add_theme_constant_override("separation", 20)
	v.add_child(_cards_box)

	_start_button = Button.new()
	_start_button.name = "StartButton"
	_start_button.text = "Elige un recluta"
	_start_button.custom_minimum_size = Vector2(260, 48)
	_start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start_button.add_theme_font_size_override("font_size", 18)
	UiKit.style_button(_start_button, Color(0.18, 0.32, 0.18), UiKit.UP, Color.WHITE, 8)
	_start_button.disabled = true
	_start_button.pressed.connect(_on_start_button_pressed)
	v.add_child(_start_button)


func generate_offers() -> void:
	offers.clear()
	selected_card = null
	_panels.clear()
	for c in _cards_box.get_children():
		_cards_box.remove_child(c)
		c.queue_free()
	for i in OFFER_COUNT:
		var card := UnitFactory.make_recruit(null, false, true)
		offers.append(card)
		var pc := UiKit.make_recruit_card(card, CARD_W, false)
		var box: VBoxContainer = pc.get_meta("box")
		var btn := Button.new()
		btn.text = "Elegir"
		btn.custom_minimum_size = Vector2(0, 40)
		btn.add_theme_font_size_override("font_size", 15)
		UiKit.style_button(btn, UiKit.PANEL_2, UiKit.BORDER)
		btn.pressed.connect(select.bind(i))
		box.add_child(btn)
		pc.set_meta("button", btn)
		_cards_box.add_child(pc)
		_panels.append(pc)
	_start_button.disabled = true
	_start_button.text = "Elige un recluta"


func select(index: int) -> void:
	if index < 0 or index >= offers.size():
		return
	selected_card = offers[index]
	for i in _panels.size():
		var pc := _panels[i]
		var on := i == index
		pc.add_theme_stylebox_override("panel", UiKit.style(UiKit.PANEL if not on else Color(0.13, 0.17, 0.13), UiKit.UP if on else UiKit.BORDER, 10, 3 if on else 2, 12))
		pc.modulate = Color.WHITE if on else Color(0.72, 0.72, 0.75)
		var b: Button = pc.get_meta("button")
		b.text = "✔ Elegido" if on else "Elegir"
	_start_button.disabled = false
	_start_button.text = "Comenzar con %s ▶" % selected_card.unit_name


## Reinicia la partida y añade el recluta elegido. Devuelve true si había selección.
func confirm_selection() -> bool:
	if selected_card == null:
		return false
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm:
		gsm.reset_run()
		gsm.add_coins(Economy.STARTING_COINS, "inicio de partida")
		gsm.add_points(Economy.STARTING_POINTS, "inicio de partida")
		gsm.add_troop_to_army(selected_card)
	return true


func _on_start_button_pressed() -> void:
	if not confirm_selection():
		return
	if change_scene_on_start:
		get_tree().change_scene_to_file("res://Scenes/Map/map.tscn")
