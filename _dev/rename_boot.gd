extends Node
## Como dev_boot (run con 3 reclutas en la planificación), más un ayudante que deja escribir con
## game_manage input_key: sus teclas llegan sin carácter (unicode 0) y el LineEdit no escribe nada;
## aquí se reenvían con el carácter puesto. Sirve para probar el renombrado de la ficha en el juego real.

class KeyTyper extends Node:
	func _input(event: InputEvent) -> void:
		var k := event as InputEventKey
		if k == null or k.unicode != 0 or not k.pressed:
			return
		if k.keycode >= KEY_A and k.keycode <= KEY_Z:
			get_viewport().set_input_as_handled()
			var e: InputEventKey = k.duplicate()
			e.unicode = k.keycode + (0 if k.shift_pressed else 32) # sin Mayús, minúscula
			Input.parse_input_event(e)


func _ready() -> void:
	get_tree().root.add_child.call_deferred(KeyTyper.new())
	GameStateManager.reset_run()
	GameStateManager.coins = 200
	GameStateManager.command_points = 20
	GameStateManager.current_stage = 1
	GameStateManager.current_node_type = "Batalla Normal"
	for i in 3:
		GameStateManager.add_troop_to_army(UnitFactory.make_recruit())
	get_tree().change_scene_to_file.call_deferred("res://Scenes/Battle/battle.tscn")
