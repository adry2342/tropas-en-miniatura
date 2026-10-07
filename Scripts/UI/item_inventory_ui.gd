extends CanvasLayer

@onready var inventory_container: VBoxContainer = $Control/Panel/VBoxContainer

var items_pool: Array = []
var dragging_item: Resource = null
var dragging_button: Button = null
var drag_preview_label: Label = null


func _ready() -> void:
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.battle_fight_started.connect(_on_battle_fight_started)
	
	_load_items()


func _load_items() -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm:
		items_pool = gsm.get_bench_items()
	
	_update_inventory_ui()


func _update_inventory_ui() -> void:
	for child in inventory_container.get_children():
		child.queue_free()
	
	for item in items_pool:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(140, 50)
		btn.text = "🎁 %s\n(Arrastrar a Tropa)" % item.display_name
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		
		btn.gui_input.connect(func(event): _on_item_gui_input(event, item, btn))
		inventory_container.add_child(btn)


func _on_item_gui_input(event: InputEvent, item: Resource, button: Button) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging_item = item
			dragging_button = button
			_create_item_drag_preview(item)
		else:
			if dragging_item:
				_drop_item_on_troop()


func _create_item_drag_preview(item: Resource) -> void:
	_cleanup_preview()
	drag_preview_label = Label.new()
	drag_preview_label.text = "🎁 " + item.display_name
	drag_preview_label.modulate = Color(1.0, 0.85, 0.2)
	add_child(drag_preview_label)
	drag_preview_label.global_position = drag_preview_label.get_global_mouse_position()


func _input(event: InputEvent) -> void:
	if drag_preview_label and event is InputEventMouseMotion:
		drag_preview_label.global_position = drag_preview_label.get_global_mouse_position()
	elif drag_preview_label and event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drop_item_on_troop()


func _drop_item_on_troop() -> void:
	if not dragging_item:
		_cleanup_preview()
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var closest_troop: CharacterBody2D = null
	var min_dist: float = 60.0
	
	for troop in get_tree().get_nodes_in_group("troops"):
		if troop.team == troop.Team.PLAYER:
			var dist = mouse_pos.distance_to(troop.global_position)
			if dist < min_dist:
				min_dist = dist
				closest_troop = troop
	
	var gsm = get_node_or_null("/root/GameStateManager")
	if closest_troop and gsm and closest_troop.get("card") is TroopCard \
			and gsm.equip_item_from_bench(closest_troop.card, dragging_item):
		if is_instance_valid(dragging_button):
			dragging_button.queue_free()
		print("Objeto %s equipado con éxito a %s" % [dragging_item.display_name, closest_troop.name])
	
	dragging_item = null
	dragging_button = null
	_cleanup_preview()


func _cleanup_preview() -> void:
	if is_instance_valid(drag_preview_label):
		drag_preview_label.queue_free()
		drag_preview_label = null


func _on_battle_fight_started() -> void:
	_cleanup_preview()
	hide()
