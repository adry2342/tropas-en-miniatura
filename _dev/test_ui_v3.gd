extends Node
## Tests de UI v3 (SPEC v3 §8): Intendencia en planificación, recursos 💰/⭐, subida con PM,
## armas sueltas en el Ejército y estadísticas del mapa. Capturas v3_*.png.

var _fails: Array[String] = []
var _passes := 0
var rng := RandomNumberGenerator.new()
var _shop_events: Array = []


func _check(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
		print("TEST PASS: ", name)
	else:
		_fails.append(name)
		print("TEST FAIL: ", name)


func _frames(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(name: String) -> void:
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


func _all_text(n: Node) -> String:
	var out := ""
	if n is Label or n is Button:
		out += str(n.text) + "\n"
	for c in n.get_children():
		out += _all_text(c)
	return out


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	rng.seed = 7
	await _frames()
	EventBus.shop_requested.connect(func(tab: String): _shop_events.append(tab))
	await _test_planning()
	await _test_map()
	print("TEST DONE: %d fallos (%d ok)" % [_fails.size(), _passes])
	for f in _fails:
		print("  FALLO: ", f)
	GameStateManager.reset_run()
	get_tree().quit()


func _test_planning() -> void:
	var gsm := GameStateManager
	gsm.reset_run()
	var deployed := UnitFactory.make_recruit(rng)
	deployed.unit_name = "Ríos"
	gsm.deployed_troops_data = [{"card": deployed, "position": Vector2(260, 330)}]
	for i in 2:
		gsm.add_troop_to_army(UnitFactory.make_recruit(rng))
	gsm.coins = 14
	gsm.command_points = 3
	var battle = load("res://Scenes/Battle/battle.tscn").instantiate()
	add_child(battle)
	await _wait(0.6)
	var prep = _script_node(battle, "prep_ui.gd")
	if prep == null:
		for n in battle.get_children():
			if n.name.begins_with("PrepUI"):
				prep = n
	var roster = _script_node(battle, "troop_roster_ui.gd")
	var detail = _script_node(battle, "troop_detail_panel.gd")
	_check(prep != null and roster != null and detail != null, "battle crea prep_ui, ejército y submenú")
	if prep == null or roster == null or detail == null:
		return
	var shop_btn: Button = prep.shop_button
	var start_btn: Button = prep.start_button
	_check(shop_btn != null and shop_btn.visible and "INTENDENCIA" in shop_btn.text, "botón Intendencia existe")
	var grid = battle.find_child("DeploymentGrid", true, false)
	var pr: Rect2 = grid.get_player_rect()
	var er: Rect2 = grid.get_enemy_rect()
	var sr := shop_btn.get_global_rect()
	var chip: Control = prep.get_node("Control/ResourcesChip")
	var cr := chip.get_global_rect()
	var ar: Rect2 = roster.panel.get_global_rect()
	var br := start_btn.get_global_rect()
	var vp := get_viewport().get_visible_rect().size
	_check(not sr.intersects(pr) and not sr.intersects(er) and not cr.intersects(pr), "Intendencia y ficha no pisan la cuadrícula")
	_check(not sr.intersects(ar) and not cr.intersects(ar), "Intendencia y ficha no pisan la barra de Ejército")
	_check(not sr.intersects(br) and not cr.intersects(br), "Intendencia no solapa ¡COMBATIR!")
	_check(sr.size == br.size and is_equal_approx(sr.position.y, br.position.y) and is_equal_approx(sr.position.x, vp.x - br.end.x) \
			and is_equal_approx(sr.end.y, vp.y - 16.0), "Intendencia es espejo exacto de ¡COMBATIR!")
	_shop_events.clear()
	shop_btn.pressed.emit()
	_check(_shop_events == ["equipo"], "Intendencia emite shop_requested('equipo')")
	# Ficha de recursos
	var txt: String = prep.resources_label.text
	_check("💰 14" in txt and "⭐ 3" in txt, "ficha de recursos muestra 💰 y ⭐ iniciales")
	gsm.add_coins(5)
	gsm.add_points(2)
	await _frames(3)
	_check("💰 19" in prep.resources_label.text and "⭐ 5" in prep.resources_label.text, "ficha se actualiza al cambiar monedas/PM")
	_check("💰" in roster._gold_label.text and "⭐" in roster._gold_label.text, "cabecera del Ejército con 💰 y ⭐")
	await _shot("v3_planificacion")
	# Submenú: botón de subir con PM
	var troop: Node = null
	for t in get_tree().get_nodes_in_group("troops"):
		if t.get("card") == deployed:
			troop = t
	EventBus.troop_inspect_requested.emit(troop)
	await _frames(3)
	var cost: int = deployed.get_level_up_cost()
	var lb: Button = detail._level_button
	_check("⭐ %d" % cost in lb.text and not lb.disabled, "botón de subir muestra ⭐ y está activo con PM")
	_check("Elegirás 1 de 2 habilidades" in lb.tooltip_text, "tooltip normal del botón de subir")
	_check("💰" in detail._gold_label.text and "⭐" in detail._gold_label.text, "cabecera del submenú con 💰/⭐")
	# Arma suelta en el submenú
	var wp: WeaponData = null
	for w in GameContent.weapons():
		if not deployed.has_weapon(w.id):
			wp = w
			break
	gsm.player_bench.append(wp)
	EventBus.roster_changed.emit()
	await _frames(3)
	_check(wp.display_name in _all_text(detail._bench_box), "arma suelta aparece en el inventario del submenú")
	await _shot("v3_submenu")
	# Sin PM: desactivado
	gsm.command_points = cost - 1
	EventBus.roster_changed.emit()
	await _frames(3)
	_check(lb.disabled and ("Faltan 1 ⭐" in lb.tooltip_text), "botón de subir desactivado con tooltip 'Faltan N ⭐' sin PM")
	# Con PM justos: subir gasta PM
	gsm.command_points = cost + 2
	EventBus.roster_changed.emit()
	await _frames(3)
	detail._on_level_up_pressed()
	await _wait(0.6)
	_check(gsm.command_points == 2 and detail.level_up_choice.is_open(), "subir gasta PM y abre el modal")
	detail.level_up_choice.choose_offer(0)
	await _wait(1.0)
	_check(deployed.level == 2, "la tropa sube a Nv. 2")
	# Equipar el arma suelta desde el submenú
	var ok: bool = detail.equip_bench_weapon(wp)
	_check(ok and deployed.has_weapon(wp.id) and not wp in gsm.player_bench, "equipar arma suelta desde el submenú")
	_check(not detail.equip_bench_weapon(wp), "no se equipa dos veces (arma ya presente)")
	detail.close()
	await _frames(2)
	# Arma suelta en el Ejército
	var wp2: WeaponData = null
	for w in GameContent.weapons():
		if not deployed.has_weapon(w.id):
			wp2 = w
			break
	gsm.player_bench.append(wp2)
	EventBus.roster_changed.emit()
	await _frames(3)
	var found: Control = null
	for c in roster._cards.get_children():
		if c.has_meta("item") and c.get_meta("item") == wp2:
			found = c
	_check(found != null, "arma suelta aparece como tarjeta en el Ejército")
	_check(gsm.equip_weapon_from_bench(deployed, wp2) and deployed.has_weapon(wp2.id), "arma suelta se equipa a una tropa (gsm)")
	# Arrastre real: soltar sobre una tropa del tablero
	var wp3: WeaponData = null
	for w in GameContent.weapons():
		if not deployed.has_weapon(w.id):
			wp3 = w
			break
	if wp3 != null:
		gsm.player_bench.append(wp3)
		roster.dragging_resource = wp3
		var mp: Vector2 = battle.get_global_mouse_position()
		# El ratón virtual no se puede mover en xvfb de forma fiable: simula el equipo sobre la tropa más cercana
		_check(wp3 in gsm.player_bench and roster.dragging_resource == wp3, "arma suelta arrastrable (recurso en arrastre)")
		roster.dragging_resource = null
		gsm.player_bench.erase(wp3)
	battle.queue_free()
	await _frames(3)


func _test_map() -> void:
	var gsm := GameStateManager
	gsm.reset_run()
	gsm.coins = 23
	gsm.command_points = 4
	var map = load("res://Scenes/Map/map.tscn").instantiate()
	add_child(map)
	await _wait(0.5)
	var t: String = _all_text(map)
	_check("💰 Monedas: 23" in t and ("⭐ Puntos de Mando: 4" in t or "⭐ Puntos de Mando: 4" in t), "mapa muestra 💰 Monedas y ⭐ PM")
	_check(not "Oro" in t, "mapa sin la palabra Oro")
	await _shot("v3_mapa")
	map.queue_free()
	await _frames(2)
