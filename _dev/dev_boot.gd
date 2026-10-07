extends Node
## Escena temporal de pruebas: prepara una run con monedas, PM y 3 reclutas únicos y salta a la batalla.

func _ready() -> void:
	GameStateManager.reset_run()
	GameStateManager.coins = 200
	GameStateManager.command_points = 20
	GameStateManager.current_stage = 1
	GameStateManager.current_node_type = "Batalla Normal"
	for i in 3:
		GameStateManager.add_troop_to_army(UnitFactory.make_recruit())
	get_tree().change_scene_to_file.call_deferred("res://Scenes/Battle/battle.tscn")
