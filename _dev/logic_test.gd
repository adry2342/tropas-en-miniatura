extends Node2D
## Prueba de lógica (SPEC v2): cuadrícula y casillas únicas, intercambio, retirada a la reserva,
## persistencia entre rondas (el mismo TroopCard), panel de ejército, tienda, mapa de calor,
## rondas infinitas, ruleta y victoria contra el jefe.

const BATTLE = preload("res://Scenes/Battle/battle.tscn")
const TROOP = preload("res://Scenes/Troops/troop.tscn")

var fails: int = 0
var passes: int = 0
var fail_msgs: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("TEST PASS: ", msg)
	else:
		fails += 1
		fail_msgs.append(msg)
		print("TEST FAIL: ", msg)


func frames(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_dev/shots/%s.png" % file)


func player_troops() -> Array:
	var out: Array = []
	for t in get_tree().get_nodes_in_group("troops"):
		if is_instance_valid(t) and not t.is_queued_for_deletion() and t.team == t.Team.PLAYER and not t.has_meta("is_drag_preview"):
			out.append(t)
	return out


func distinct_positions(troops: Array) -> bool:
	var seen := {}
	for t in troops:
		var key := "%d,%d" % [int(t.global_position.x), int(t.global_position.y)]
		if seen.has(key):
			return false
		seen[key] = true
	return true


func recruit() -> TroopCard:
	return UnitFactory.make_recruit()


## Tropa veterana: Nv. 3, soldado, 2 objetos y 1 habilidad.
func veteran() -> TroopCard:
	var c := recruit()
	c.items.clear() # v3.1: el recluta puede traer objeto de serie; el veterano lleva exactamente 2
	c.level = 3
	c.specialty = GameContent.find_specialty("soldado")
	c.add_item(GameContent.find_item("chaleco_tactico"))
	c.add_item(GameContent.find_item("granada"))
	c.skills.append(GameContent.find_skill("piel_dura"))
	return c


func spawn(card: TroopCard, pos: Vector2) -> CharacterBody2D:
	var t = TROOP.instantiate()
	add_child(t)
	t.team = t.Team.PLAYER
	t.setup(card)
	t.global_position = pos
	return t


func clear_scene(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	for t in get_tree().get_nodes_in_group("troops"):
		t.queue_free()
	await frames(3)


func find_by_script(parent: Node, suffix: String) -> Node:
	for n in parent.get_children():
		if n.get_script() and n.get_script().resource_path.ends_with(suffix):
			return n
	return null


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	GameStateManager.reset_run()
	var battle = BATTLE.instantiate()
	add_child(battle)
	await frames()
	var grid = battle.find_child("DeploymentGrid", true, false)
	check(grid != null and grid.grid_cells.size() == grid.rows * grid.columns and grid.grid_cells.size() >= 20, "cuadrícula grande (%d casillas)" % grid.grid_cells.size())
	check(grid.get_enemy_cells().size() == grid.grid_cells.size(), "la zona enemiga tiene las mismas casillas que la del jugador")
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	check(grid.get_player_rect().position.x < 60.0 and grid.get_enemy_rect().end.x > vp_size.x - 60.0, "las zonas llegan casi a los bordes laterales")
	check(not grid.get_player_rect().intersects(grid.get_enemy_rect()), "las zonas no se solapan")
	# Sin enemigos para que no interfieran con la instantánea
	for e in battle.get_enemies():
		e.queue_free()
	await frames(2)

	# 1. Tres tropas soltadas en la misma casilla -> casillas distintas
	var cell0: Vector2 = grid.grid_cells[0]
	var ta = spawn(recruit(), cell0)
	var tb = spawn(recruit(), cell0)
	var tc = spawn(recruit(), cell0)
	await frames()
	check(distinct_positions([ta, tb, tc]), "3 tropas en la misma casilla acaban en casillas distintas")
	for t in [ta, tb, tc]:
		check(grid.grid_cells.has(t.global_position), "%s está centrada en una casilla" % t.card.unit_name)

	# 2. Soltar A sobre B -> intercambio
	var a_origin: Vector2 = ta.global_position
	var b_origin: Vector2 = tb.global_position
	ta._drag_origin = a_origin
	ta.global_position = b_origin + Vector2(7, -9)
	ta._place_on_grid()
	check(ta.global_position == b_origin and tb.global_position == a_origin, "soltar sobre una casilla ocupada intercambia las tropas")
	check(distinct_positions([ta, tb, tc]), "tras el intercambio siguen sin solaparse")

	# 3. Tablero lleno -> sin casilla libre
	var filler: Array = []
	for i in range(3, grid.grid_cells.size()):
		filler.append(spawn(recruit(), grid.grid_cells[i]))
	await frames()
	check(player_troops().size() == grid.grid_cells.size() and distinct_positions(player_troops()), "tantas tropas como casillas, todas en casillas distintas")
	check(grid.get_nearest_free_position(Vector2(200, 300)) == Vector2.INF, "tablero lleno: no hay casilla libre")

	# 4. Retirar a la reserva conservando el card (nivel, especialidad, objetos, habilidades)
	var vet_card := veteran()
	var vet = filler[0]
	vet.setup(vet_card)
	var vet_cell: Vector2 = vet.global_position
	GameStateManager.return_troop_to_bench(vet)
	await frames()
	check(player_troops().size() == grid.grid_cells.size() - 1, "la tropa retirada deja el tablero")
	check(GameStateManager.get_bench_cards().size() == 1, "la reserva tiene 1 tarjeta")
	var bench_card: TroopCard = GameStateManager.get_bench_cards()[0]
	check(bench_card == vet_card and bench_card.level == 3 and bench_card.items.size() == 2 \
			and bench_card.skills.size() == 1 and bench_card.specialty != null,
			"la reserva guarda el mismo card (Nv. 3, especialidad, 2 objetos, 1 habilidad)")
	check(grid.get_nearest_free_position(Vector2(200, 300)) == vet_cell, "la casilla liberada vuelve a estar disponible")

	# 5. Redesplegar desde el card
	var back = spawn(bench_card, vet_cell)
	GameStateManager.remove_from_bench(bench_card)
	await frames()
	check(back.level == 3 and back.card.items.size() == 2 and back.card == vet_card, "al redesplegar conserva nivel y objetos")
	check(is_equal_approx(back.health, back.get_max_health()) and back.get_max_health() > 100.0 * 0.9, "al redesplegar tiene la vida al máximo (%.1f)" % back.health)
	check(GameStateManager.player_bench.is_empty(), "la reserva queda vacía")

	# 6. Instantánea al empezar el combate (incluye a las que luego mueren)
	var n_before := player_troops().size()
	EventBus.battle_fight_started.emit()
	check(GameStateManager.deployed_troops_data.size() == n_before, "al empezar el combate se guardan las %d tropas" % n_before)
	var all_cards := true
	for s in GameStateManager.deployed_troops_data:
		all_cards = all_cards and s.get("card") is TroopCard and s.has("position")
	check(all_cards, "la instantánea guarda {card, position}")
	var snapshot: Array = GameStateManager.deployed_troops_data.duplicate()
	for t in player_troops().slice(0, 4):
		if t != back:
			t.die()
	await frames(2)
	for t in player_troops():
		t.global_position += Vector2(300, 40)
	check(GameStateManager.deployed_troops_data.size() == n_before, "las tropas muertas siguen en la instantánea")

	# 7. Nueva ronda: se restauran todas en su casilla, con el mismo card
	await clear_scene([battle])
	var battle2 = BATTLE.instantiate()
	add_child(battle2)
	await frames(4)
	grid = battle2.find_child("DeploymentGrid", true, false)
	var restored := player_troops()
	check(restored.size() == n_before, "la ronda siguiente restaura las %d tropas (incluidas las muertas)" % n_before)
	check(distinct_positions(restored), "las restauradas no se solapan")
	var all_in_cells := true
	for t in restored:
		if not grid.grid_cells.has(t.global_position):
			all_in_cells = false
	check(all_in_cells, "las restauradas están centradas en casillas")
	var vet_back := restored.filter(func(t): return t.card == vet_card)
	check(vet_back.size() == 1 and vet_back[0].level == 3 and vet_back[0].card.items.size() == 2 and vet_back[0].card.specialty != null,
			"la tropa de Nv. 3 vuelve con el mismo card (nivel, especialidad y objetos)")
	check(vet_back.size() == 1 and is_equal_approx(vet_back[0].health, vet_back[0].get_max_health()), "la restaurada empieza la ronda con la vida al máximo")
	var snap_positions := {}
	for s in snapshot:
		snap_positions["%d,%d" % [int(s["position"].x), int(s["position"].y)]] = true
	var same := true
	for t in restored:
		if not snap_positions.has("%d,%d" % [int(t.global_position.x), int(t.global_position.y)]):
			same = false
	check(same, "las casillas restauradas coinciden con las del despliegue guardado")

	# 8. Submenú: retirar a la reserva y botón de combatir
	await clear_scene([battle2])
	GameStateManager.reset_run()
	var battle3 = BATTLE.instantiate()
	add_child(battle3)
	await frames(3)
	var prep = null
	for ch in battle3.get_children():
		if "start_button" in ch:
			prep = ch
	var detail = find_by_script(battle3, "troop_detail_panel.gd")
	check(prep != null and detail != null, "PrepUI y submenú presentes")
	check(prep.start_button.disabled, "sin tropas desplegadas el botón de combatir está desactivado")
	var lone_card := recruit()
	var lone = spawn(lone_card, battle3.find_child("DeploymentGrid", true, false).grid_cells[5])
	await frames(3)
	check(not prep.start_button.disabled, "con una tropa desplegada el botón de combatir se activa")
	EventBus.troop_inspect_requested.emit(lone)
	await frames(2)
	check(detail.visible and GameStateManager.ui_blocking and detail.card == lone_card, "el submenú se abre con el card de la tropa y bloquea el arrastre")
	detail._on_return_pressed()
	await frames(3)
	check(not detail.visible and not GameStateManager.ui_blocking, "al retirar, el submenú se cierra y desbloquea")
	check(GameStateManager.get_bench_cards() == [lone_card] and player_troops().is_empty(), "la tropa retirada está en la reserva con su card")
	check(prep.start_button.disabled, "sin tropas otra vez, el botón de combatir se desactiva")

	# 9. Enemigos en la cuadrícula espejo invisible
	await clear_scene([battle3])
	var configs := [[1, "Batalla Normal"], [3, "Batalla Normal"], [4, "Batalla Élite"], [6, "Batalla Élite"], [4, "Jefe Final"], [7, "Jefe Final"]]
	var all_ok := true
	var all_mirrored := true
	var all_distinct := true
	var all_have_card := true
	var total_enemies := 0
	for cfg in configs:
		for rep in range(3):
			GameStateManager.reset_run()
			GameStateManager.current_stage = cfg[0]
			GameStateManager.current_node_type = cfg[1]
			var bt = BATTLE.instantiate()
			add_child(bt)
			await frames(2)
			var pgrid = bt.find_child("DeploymentGrid", true, false)
			var mirrored := {}
			for cell in pgrid.grid_cells:
				mirrored["%d,%d" % [int(get_viewport().get_visible_rect().size.x - cell.x), int(cell.y)]] = true
			var enemies: Array = bt.get_enemies()
			total_enemies += enemies.size()
			if enemies.is_empty():
				all_ok = false
			if not distinct_positions(enemies):
				all_distinct = false
			for e in enemies:
				if not mirrored.has("%d,%d" % [int(e.global_position.x), int(e.global_position.y)]):
					all_mirrored = false
				if not (e.card is TroopCard and e.card.get_weapon() != null):
					all_have_card = false
			await clear_scene([bt])
	check(all_ok, "todas las oleadas generan enemigos (%d en total)" % total_enemies)
	check(all_mirrored, "todos los enemigos están en casillas de la cuadrícula espejo")
	check(all_distinct, "ningún enemigo comparte casilla con otro")
	check(all_have_card, "cada enemigo tiene su TroopCard con arma")

	# 10. Límite de 6 tropas y 6 huecos en la barra
	GameStateManager.reset_run()
	var bt2 = BATTLE.instantiate()
	add_child(bt2)
	await frames(3)
	var g2 = bt2.find_child("DeploymentGrid", true, false)
	var roster = find_by_script(bt2, "troop_roster_ui.gd")
	check(roster != null, "existe la barra de ejército")
	for e in bt2.get_enemies():
		e.queue_free()
	await frames(2)
	check(roster._cards.get_child_count() == 6, "0 tropas -> 6 huecos vacíos")
	for i in range(5):
		spawn(recruit(), g2.grid_cells[i])
	await frames(3)
	check(roster._cards.get_child_count() == 6 and GameStateManager.can_deploy_more(), "5 tropas -> 6 huecos y aún se puede desplegar")
	spawn(recruit(), g2.grid_cells[5])
	await frames(3)
	check(roster._cards.get_child_count() == 6 and not GameStateManager.can_deploy_more(), "6 tropas -> 6 tarjetas y límite alcanzado")
	check(not roster._cards.get_child(5).has_meta("empty_slot"), "el sexto hueco es una tarjeta, no vacío")
	await shot("logic_roster6")

	# 11. Reserva integrada en el ejército + subir de nivel en la reserva
	await clear_scene([bt2])
	GameStateManager.reset_run()
	GameStateManager.coins = 500
	GameStateManager.command_points = 5
	GameStateManager.add_troop_to_army(recruit())
	GameStateManager.add_troop_to_army(recruit())
	var bt3 = BATTLE.instantiate()
	add_child(bt3)
	await frames(3)
	var roster3 = find_by_script(bt3, "troop_roster_ui.gd")
	var detail3 = find_by_script(bt3, "troop_detail_panel.gd")
	check(bt3.find_child("TroopBenchUI", true, false) == null, "ya no existe el panel de reserva aparte")
	check(roster3._cards.get_child_count() == 6, "2 tropas en reserva -> 6 huecos")
	var reserve_btns := 0
	for rc in roster3._cards.get_children():
		if rc is Button and not rc.has_meta("empty_slot"):
			reserve_btns += 1
	check(reserve_btns == 2, "la reserva aparece como 2 tarjetas en el ejército")
	check(roster3.panel.is_in_group("troop_return_zone"), "el panel del ejército es la zona de retirada")
	var cx: float = roster3.panel.get_global_rect().get_center().x
	check(abs(cx - 576.0) < 2.0, "el panel está centrado (x=%d)" % int(cx))
	var card0: TroopCard = GameStateManager.get_bench_cards()[0]
	detail3.open_card(card0)
	await frames(2)
	check(detail3.visible and detail3.troop == null and detail3.card == card0 and not detail3._return_button.visible, "submenú de tropa de reserva abierto sin botón de retirar")
	detail3._on_level_up_pressed()
	await frames(3)
	check(GameStateManager.command_points == 4 and GameStateManager.coins == 500 and card0.level == 1 and card0.pending_offers.size() >= 2, "subir cobra 1 PM (no monedas) y deja 2 ofertas pendientes (aún Nv. 1)")
	check(card0.pending_offers.all(func(o): return o.type != "specialty"), "al ir a Nv. 2 ya no salen especialidades (v3.2: en Nv. 5)")
	check(detail3.level_up_choice.is_open(), "se abre el modal de ascenso")
	detail3.level_up_choice.choose_offer(1)
	await get_tree().create_timer(1.2).timeout
	check(card0.level == 2 and card0.specialty == null and card0.pending_offers.is_empty(), "elegir mejora sube a Nv. 2 (sigue siendo Recluta)")
	check(not detail3.level_up_choice.is_open() and detail3.visible, "el modal se cierra y el submenú sigue abierto")
	check(player_troops().is_empty(), "el submenú de reserva no crea tropas reales")
	detail3.close()
	roster3.dragging_resource = card0
	check(GameStateManager.can_deploy_more(), "se puede desplegar desde la reserva")
	roster3.dragging_resource = null

	# 12. Tienda de reclutamiento
	var shop = find_by_script(bt3, "recruit_shop.gd")
	check(shop != null and not shop.visible, "la tienda existe y empieza cerrada")
	GameStateManager.reset_run()
	GameStateManager.coins = 120
	EventBus.roster_changed.emit()
	await frames(3)
	var empty_slot = null
	for sc in roster3._cards.get_children():
		if sc.has_meta("empty_slot"):
			empty_slot = sc
			break
	check(empty_slot is Button, "los huecos vacíos son pulsables")
	empty_slot.pressed.emit()
	await frames(2)
	check(shop.visible and GameStateManager.ui_blocking, "pulsar un hueco vacío abre la Intendencia encima de la planificación")
	check(shop.current_tab() == "reclutas", "el hueco vacío abre la pestaña Reclutas")
	var offers: Array[TroopCard] = shop.get_offers()
	check(offers.size() == 3 and shop._buy_buttons.size() == 3, "la tienda ofrece 3 reclutas")
	var names := {}
	for o in offers:
		names[o.unit_name + str(o.base_health) + o.get_weapon().id] = true
		check(o.level == 1 and Economy.recruit_price(o) - Economy.recruit_extras_surcharge(o) >= Economy.RECRUIT_PRICE_MIN and Economy.recruit_price(o) - Economy.recruit_extras_surcharge(o) <= Economy.RECRUIT_PRICE_MAX,
				"oferta %s: recluta Nv. 1 a %d 💰" % [o.unit_name, Economy.recruit_price(o)])
	check(names.size() == 3, "las 3 ofertas son tropas distintas")
	var first: TroopCard = offers[0]
	var price: int = Economy.recruit_price(first)
	check(shop.buy(first), "comprar %s con 120 💰" % first.unit_name)
	await frames(3)
	check(GameStateManager.coins == 120 - price, "se descuenta el precio (monedas=%d)" % GameStateManager.coins)
	var bench_cards := GameStateManager.get_bench_cards()
	check(bench_cards.size() == 1 and bench_cards[0] == first and bench_cards[0].level == 1, "la tropa comprada está en la reserva a Nv. 1")
	check(shop.get_offers().size() == 2, "la oferta comprada desaparece")
	var cards_shown := 0
	for sc2 in roster3._cards.get_children():
		if not sc2.has_meta("empty_slot"):
			cards_shown += 1
	check(cards_shown == 1 and roster3._cards.get_child_count() == 6, "el ejército muestra la tropa nueva y 5 huecos")
	GameStateManager.coins = 1
	EventBus.roster_changed.emit()
	await frames(2)
	var all_disabled := true
	for k in shop._buy_buttons:
		if is_instance_valid(shop._buy_buttons[k]):
			all_disabled = all_disabled and shop._buy_buttons[k].disabled
	check(all_disabled, "sin monedas suficientes los botones se bloquean")
	check(not shop.buy(shop.get_offers()[0]) and GameStateManager.coins == 1, "no se puede comprar sin monedas")
	await shot("logic_tienda")
	# Ejército lleno
	GameStateManager.coins = 1000
	for i in range(4):
		GameStateManager.recruit_troop(recruit(), 10)
	await frames(2)
	check(shop.buy(shop.get_offers()[0]), "comprar la sexta tropa")
	await frames(3)
	check(GameStateManager.get_army_size() == 6 and not GameStateManager.has_free_army_slot(), "6 tropas -> ejército lleno")
	check(not shop.visible and not GameStateManager.ui_blocking, "la tienda se cierra al llenarse el ejército")
	var g_before: int = GameStateManager.coins
	check(not GameStateManager.recruit_troop(recruit(), 10) and GameStateManager.coins == g_before, "no se compra con el ejército lleno")

	# 13. Mapa de calor de enemigos en la planificación
	await clear_scene([bt3])
	GameStateManager.reset_run()
	GameStateManager.current_stage = 3
	var bt4 = BATTLE.instantiate()
	add_child(bt4)
	await frames(3)
	var enemies4: Array = bt4.get_enemies()
	var hm = bt4.find_child("EnemyHeatmap", true, false)
	check(enemies4.size() > 0, "hay enemigos (%d)" % enemies4.size())
	check(enemies4.all(func(e): return not e.visible), "en la planificación los enemigos están ocultos")
	check(hm != null and not hm.visible and hm.texture != null, "v4: sin radioperador el mapa de calor está oculto")
	var intel = bt4.find_child("IntelLabel", true, false)
	check(intel != null and intel.text.contains("Sin radioperador"), "v4: aviso 'Sin radioperador' en la zona enemiga")
	var radio_card := recruit()
	radio_card.specialty = GameContent.find_specialty("comunicaciones")
	var gn0 = bt4.find_child("DeploymentGrid", true, false)
	var radio_troop = spawn(radio_card, gn0.grid_cells[7])
	await get_tree().create_timer(0.4).timeout
	check(hm.visible and intel.text.contains("Informe de radio"), "v4: con un Radioperador desplegado se ve el mapa de calor")
	radio_troop.queue_free()
	await get_tree().create_timer(0.4).timeout
	check(not hm.visible, "v4: al retirar al Radioperador el mapa vuelve a ocultarse")
	check(enemies4.all(func(e): return hm.intensity_at(e.global_position) > 0.5), "hay calor fuerte donde están los enemigos")
	check(hm.intensity_at(Vector2(200, 300)) < 0.01, "no hay calor en la zona del jugador")
	seed(4242) # el ruido del mapa de calor usa randi(): semilla fija para que la comprobación sea determinista
	var area := Rect2(Vector2(750, 180), Vector2(320, 240))
	var c0 := Vector2(870, 300)
	var h1 = EnemyHeatmap.new(); add_child(h1); h1.build([c0] as Array[Vector2], area)
	var h2 = EnemyHeatmap.new(); add_child(h2); h2.build([c0, c0 + Vector2(0, 10)] as Array[Vector2], area)
	var sep := [Vector2(790, 260), Vector2(1030, 340)] as Array[Vector2]
	var hs = EnemyHeatmap.new(); add_child(hs); hs.build(sep, area)
	var mid: Vector2 = (sep[0] + sep[1]) * 0.5
	check(h2.intensity_at(c0) > h1.intensity_at(c0) + 0.1, "dos enemigos juntos calientan más que uno")
	check(absf(h1.intensity_at(c0 + Vector2(60, 0)) - h1.intensity_at(c0 + Vector2(0, 60))) < 0.12, "un enemigo solo -> mancha aproximadamente redonda")
	check(h1.intensity_at(c0 + Vector2(60, 0)) < h1.intensity_at(c0) and h1.intensity_at(c0 + Vector2(150, 0)) < 0.25, "la mancha se difumina hacia fuera")
	var dir: Vector2 = (sep[1] - sep[0]).normalized()
	var perp := Vector2(-dir.y, dir.x)
	check(hs.intensity_at(mid + dir * 70) > hs.intensity_at(mid + perp * 70) + 0.05, "dos enemigos separados -> mancha alargada")
	check(hs.intensity_at(mid) > 0.15, "entre dos enemigos separados también hay calor (%.2f)" % hs.intensity_at(mid))
	var img_b: Image = hm.texture.get_image()
	var border_max := 0.0
	for bx in range(img_b.get_width()):
		border_max = maxf(border_max, maxf(img_b.get_pixel(bx, 0).a, img_b.get_pixel(bx, img_b.get_height() - 1).a))
	for by in range(img_b.get_height()):
		border_max = maxf(border_max, maxf(img_b.get_pixel(0, by).a, img_b.get_pixel(img_b.get_width() - 1, by).a))
	check(border_max < 0.01, "los bordes del mapa son totalmente transparentes (alfa máx %.3f)" % border_max)
	h1.queue_free(); h2.queue_free(); hs.queue_free()
	var gn = bt4.find_child("DeploymentGrid", true, false)
	spawn(recruit(), gn.grid_cells[0])
	await frames(2)
	EventBus.battle_fight_started.emit()
	await get_tree().create_timer(0.6).timeout
	check(bt4.get_enemies().all(func(e): return e.visible and e.modulate.a > 0.9), "al combatir los enemigos aparecen")
	check(not is_instance_valid(hm), "al combatir el mapa de calor desaparece")

	# 14. Cada tropa es única y solo tiene Vida y Daño propios
	var r1 := recruit()
	var r2 := recruit()
	check(r1.base_health >= 90.0 and r1.base_health <= 110.0 and r1.base_damage >= 0.9 and r1.base_damage <= 1.1, "Vida y Daño propios con variación ±10 %")
	check(r1 != r2 and (r1.unit_name != r2.unit_name or r1.base_health != r2.base_health), "dos reclutas son tropas distintas")

	# 15. Rondas infinitas, dificultad incremental y ruleta del jefe
	await clear_scene([bt4])
	var gsm15 = GameStateManager
	gsm15.reset_run()
	check(gsm15.boss_chance == 0.0 and gsm15.roll_round_type() == "Batalla Normal", "ronda 1: 0% de jefe y batalla normal")
	for k in range(gsm15.BOSS_MIN_ROUND):
		gsm15.advance_stage()
	var r15: int = gsm15.BOSS_MIN_ROUND + 1
	check(gsm15.current_stage == r15 and absf(gsm15.boss_chance - gsm15.BOSS_CHANCE_STEP * 2) < 0.001, "%d victorias -> ronda %d y +BOSS_CHANCE_STEP por ronda desde BOSS_MIN_ROUND (%.2f)" % [r15 - 1, r15, gsm15.boss_chance])
	var first_roll: String = gsm15.roll_round_type()
	var same_roll := true
	for k in range(20):
		same_roll = same_roll and gsm15.roll_round_type() == first_roll
	check(same_roll, "la ruleta solo se gira una vez por ronda")
	var bosses := 0
	for k in range(2000):
		gsm15.rolled_round = 0
		if gsm15.roll_round_type() == "Jefe Final":
			bosses += 1
	check(absf(bosses / 2000.0 - gsm15.boss_chance) < 0.04, "con %d%% sale el jefe en esa proporción (%d/2000)" % [roundi(gsm15.boss_chance * 100.0), bosses])
	gsm15.boss_chance = 0.0
	var never := true
	for k in range(300):
		gsm15.rolled_round = 0
		never = never and gsm15.roll_round_type() != "Jefe Final"
	check(never, "con 0% nunca sale el jefe")
	var BattleScript = load("res://Scripts/Battle/battle.gd")
	var mono := true
	var prev: Dictionary = BattleScript.difficulty_for(1)
	for r in range(2, 200):
		var d: Dictionary = BattleScript.difficulty_for(r)
		mono = mono and d.hp_mult >= prev.hp_mult and d.dmg_mult >= prev.dmg_mult and d.max_enemies >= prev.max_enemies and d.max_enemies <= 8 and d.min_enemies <= d.max_enemies
		prev = d
	var d1: Dictionary = BattleScript.difficulty_for(1)
	var d2: Dictionary = BattleScript.difficulty_for(2)
	var d50: Dictionary = BattleScript.difficulty_for(50)
	check(mono, "la dificultad nunca baja y los enemigos caben en la cuadrícula")
	check(d2.hp_mult - d1.hp_mult < 0.15 and d2.dmg_mult - d1.dmg_mult < 0.1, "de una ronda a otra sube poco")
	check(d50.hp_mult > 2.5, "en la ronda 50 los enemigos son mucho más duros (x%.1f vida)" % d50.hp_mult)
	# Pantalla de ruleta
	gsm15.reset_run()
	var map_round: int = gsm15.BOSS_MIN_ROUND + 5
	for k in range(map_round - 1):
		gsm15.advance_stage()
	var map = load("res://Scenes/Map/map.tscn").instantiate()
	add_child(map)
	await frames(3)
	check(map._round_label.text == "RONDA %d" % map_round and map._chance_label.text.contains("%d%%" % roundi(gsm15.boss_chance * 100.0)), "el mapa muestra ronda %d y la probabilidad de jefe (%d%%)" % [map_round, roundi(gsm15.boss_chance * 100.0)])
	check(map._fight_button.disabled, "mientras gira la ruleta no se puede luchar")
	await get_tree().create_timer(1.0).timeout
	map.skip_spin()
	await frames(2)
	check(not map._fight_button.disabled and gsm15.rolled_round == map_round, "al acabar la ruleta se puede luchar")
	var needle_x: float = map._needle.position.x + map._needle.size.x * 0.5
	var in_boss: bool = needle_x <= map._boss_zone.position.x + map._boss_zone.size.x # la zona del jefe está a la izquierda de la barra
	check(in_boss == (gsm15.current_node_type == "Jefe Final"), "la aguja cae en la zona del jefe solo si sale el jefe")
	map.queue_free()
	gsm15.boss_chance = 1.0
	gsm15.rolled_round = 0
	var map2 = load("res://Scenes/Map/map.tscn").instantiate()
	add_child(map2)
	await frames(2)
	map2.skip_spin()
	await frames(2)
	check(gsm15.current_node_type == "Jefe Final" and map2._result_label.text.contains("JEFE"), "si sale el jefe se anuncia")
	map2.queue_free()
	var bt5 = BATTLE.instantiate()
	add_child(bt5)
	await frames(3)
	var boss_found := false
	for e in bt5.get_enemies():
		if e.name == "Jefe_Enemigo" and e.card.is_boss:
			boss_found = true
	check(boss_found, "la ronda de jefe genera al jefe (card.is_boss)")
	bt5._show_reward_screen()
	await frames(2)
	var won := false
	for ch in bt5.get_children():
		if ch.has_method("setup") and ch is CanvasLayer and "title_label" in ch and ch.title_label.text.contains("VICTORIA"):
			won = true
	check(won, "derrotar al jefe gana la partida")
	await shot("logic_victoria_jefe")
	await clear_scene([bt5])
	GameStateManager.reset_run()

	for fm in fail_msgs:
		print("FALLO: ", fm)
	print("TEST DONE: %d fallos (%d ok)" % [fails, passes])
	get_tree().quit()
