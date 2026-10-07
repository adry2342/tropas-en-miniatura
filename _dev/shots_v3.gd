extends Node
## Genera las capturas de revisión de UX (v3) en res://_dev/shots/ux_*.png y termina.

var rng := RandomNumberGenerator.new()


func _frames(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_dev/shots/%s.png" % name)
	print("CAPTURA: %s (%dx%d)" % [name, img.get_width(), img.get_height()])


func _script_node(parent: Node, suffix: String) -> Node:
	for n in parent.get_children():
		var sc = n.get_script()
		if sc and sc.resource_path.ends_with(suffix):
			return n
	return null


func _ready() -> void:
	rng.seed = 11
	await _frames()
	await _battle_shots()
	await _reward_shot()
	await _map_shot()
	get_tree().quit()


func _battle_shots() -> void:
	var gsm := GameStateManager
	gsm.reset_run()
	var deployed := UnitFactory.make_recruit(rng)
	deployed.unit_name = "Ríos"
	gsm.deployed_troops_data = [{"card": deployed, "position": Vector2(260, 330)}]
	gsm.add_troop_to_army(UnitFactory.make_recruit(rng))
	gsm.coins = 38
	gsm.command_points = 4
	var battle = load("res://Scenes/Battle/battle.tscn").instantiate()
	add_child(battle)
	await get_tree().create_timer(0.7).timeout
	var shop = _script_node(battle, "recruit_shop.gd")
	var detail = _script_node(battle, "troop_detail_panel.gd")
	await _shot("ux_planificacion")

	EventBus.shop_requested.emit("equipo")
	await _frames(4)
	await _shot("ux_intendencia_equipo")
	# Inventario con objetos sueltos
	for w in GameContent.weapons():
		if not deployed.has_weapon(w.id):
			gsm.player_bench.append(w)
			break
	var items = GameContent.items()
	if items.size() > 0:
		gsm.player_bench.append(items[0])
	EventBus.roster_changed.emit()
	await _frames(4)
	await _shot("ux_intendencia_inventario")
	EventBus.shop_requested.emit("reclutas")
	await _frames(4)
	await _shot("ux_intendencia_reclutas")
	shop.close()
	await _frames(3)

	var troop: Node = null
	for t in get_tree().get_nodes_in_group("troops"):
		if t.get("card") == deployed:
			troop = t
	EventBus.troop_inspect_requested.emit(troop)
	await _frames(4)
	await _shot("ux_submenu")
	detail._on_level_up_pressed()
	await get_tree().create_timer(0.9).timeout
	await _shot("ux_levelup")
	detail.level_up_choice.choose_offer(0)
	await get_tree().create_timer(1.0).timeout
	detail.close()
	battle.queue_free()
	await _frames(3)


func _reward_shot() -> void:
	var gsm := GameStateManager
	gsm.reset_run()
	gsm.round_kills = 7
	gsm.round_kill_coins = 14
	gsm.coins = 20
	gsm.apply_victory_rewards("Batalla Normal")
	var rs = load("res://Scenes/UI/reward_screen.tscn").instantiate()
	add_child(rs)
	await get_tree().create_timer(0.4).timeout
	await _shot("ux_recompensa")
	rs.queue_free()
	await _frames(2)


func _map_shot() -> void:
	var gsm := GameStateManager
	gsm.reset_run()
	gsm.coins = 23
	gsm.command_points = 4
	gsm.current_stage = 7
	gsm.boss_chance = 0.10
	gsm.rolled_round = 7
	var map = load("res://Scenes/Map/map.tscn").instantiate()
	add_child(map)
	await get_tree().create_timer(0.5).timeout
	await _shot("ux_mapa")
	map.queue_free()
	await _frames(2)
	gsm.current_stage = 3
	gsm.boss_chance = 0.0
	gsm.rolled_round = 3
	map = load("res://Scenes/Map/map.tscn").instantiate()
	add_child(map)
	await get_tree().create_timer(0.5).timeout
	await _shot("ux_mapa_sinriesgo")
	map.queue_free()
	await _frames(2)
