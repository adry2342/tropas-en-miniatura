extends Node
## Vista de la ficha de tropa en varios estados (captura a PNG en _dev/art_tmp/detail_*.png):
## especialista equipado, recluta recién reclutado, tarjeta flotante abierta y veterano del Cuartel.

var panel


func _ready() -> void:
	GameStateManager.reset_run()
	GameStateManager.coins = 140
	GameStateManager.command_points = 6
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.26, 0.18)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	panel = preload("res://Scripts/UI/troop_detail_panel.gd").new()
	add_child(panel)
	await get_tree().process_frame

	# 1) Especialista bien equipado
	var c: TroopCard = UnitFactory.make_recruit()
	c.unit_name = "Kaya"
	c.level = 6
	c.specialty = GameContent.find_specialty("soldado")
	c.weapons = [GameContent.find_weapon("fusil_asalto"), GameContent.find_weapon("pistola")]
	c.weapon_levels = {"fusil_asalto": 2}
	c.add_item(GameContent.find_item("balas_venenosas"))
	c.add_item(GameContent.find_item("chaleco_tactico"))
	c.add_item(GameContent.find_item("granada"))
	for id in ["ojo_certero", "esquiva", "recarga_rapida", "ojo_certero", "velocista"]:
		var sk := GameContent.find_skill(id)
		if sk:
			c.skills.append(sk)
	GameStateManager.add_troop_to_army(c)
	GameStateManager.add_item(GameContent.find_item("balas_aturdidoras"))
	GameStateManager.add_item(GameContent.find_item("botiquin"))
	GameStateManager.add_item(GameContent.find_weapon("escopeta"))
	panel.open_card(c)
	await _shot("detail_1_especialista")

	# 2) Tarjeta flotante: munición
	panel._tap_ammo(panel._ammo_slot.get_child(0))
	await _shot("detail_2_municion")
	panel.close_popover()
	panel._tap_weapon(panel._arsenal.get_child(0), 0)
	await _shot("detail_3_arma")
	panel.close_popover()
	var st: Control = panel._stats_grid.get_child(4)
	st.gui_input.emit(_click())
	await _shot("detail_3b_estadistica")
	panel.close_popover()

	# 3) Recluta recién llegado
	var r: TroopCard = UnitFactory.make_recruit(null, false, true)
	r.unit_name = "Bruno"
	panel.open_card(r)
	await _shot("detail_4_recluta")

	# 4) Veterano del Cuartel
	panel.close()
	var v := c.duplicate_card()
	v.unit_name = "Sargento Ríos"
	v.specialty = GameContent.find_specialty("vigia")
	v.weapons = [GameContent.find_weapon("rifle_francotirador")]
	panel.open_vault_card(v)
	await _shot("detail_5_cuartel")
	print("DETAIL_SAVED")


func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	return e


func _shot(file: String) -> void:
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://_dev/art_tmp/%s.png" % file)
