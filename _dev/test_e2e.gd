extends Node
## Prueba de punta a punta (QA): recorre el juego con las escenas reales simulando al jugador
## (pulsa botones y llama a los handlers de la UI como haría un clic).
## Menú → selección → mapa → batalla (desplegar, submenú, ascensos, tienda) → combate →
## recompensas → mapa ronda 2 → batalla ronda 2 (persistencia).
## Capturas en res://_dev/shots/e2e_*.png. Un Logger cuenta errores y avisos en tiempo de ejecución.

const FIGHT_TIMEOUT := 90.0

class ErrorCounter extends Logger:
	var mutex := Mutex.new()
	var entries: Array[String] = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if file.contains("godot_ai"):
			return
		mutex.lock()
		entries.append("[%s] %s:%d %s %s %s" % [["ERROR", "WARNING", "SCRIPT", "SHADER"][clampi(error_type, 0, 3)], file, line, function, code, rationale])
		mutex.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass

var fails: Array[String] = []
var passes := 0
var logger := ErrorCounter.new()


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("TEST PASS: ", msg)
	else:
		fails.append(msg)
		print("TEST FAIL: ", msg)


func frames(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_dev/shots/%s.png" % file)
	print("CAPTURA: %s (%dx%d)" % [file, img.get_width(), img.get_height()])


## Espera a que la escena actual sea `path` (con límite de tiempo).
func wait_scene(path: String, timeout: float = 5.0) -> Node:
	var t := 0.0
	while t < timeout:
		var cs := get_tree().current_scene
		if cs and cs.scene_file_path == path and cs.is_node_ready():
			await frames(3)
			return cs
		await get_tree().process_frame
		t += get_process_delta_time()
	return null


func find_by_script(parent: Node, suffix: String) -> Node:
	for n in parent.get_children():
		if n.get_script() and n.get_script().resource_path.ends_with(suffix):
			return n
	return null


func player_troops() -> Array:
	var out: Array = []
	for t in get_tree().get_nodes_in_group("troops"):
		if is_instance_valid(t) and not t.is_queued_for_deletion() and t.team == t.Team.PLAYER and not t.has_meta("is_drag_preview"):
			out.append(t)
	return out


func texts_of(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	elif n is Button:
		out += (n as Button).text + "\n"
	for c in n.get_children():
		out += texts_of(c)
	return out


## ¿Algún texto dice "oro" como palabra suelta? (los textos de la v3 hablan de monedas 💰)
func has_oro(text: String) -> bool:
	var rx := RegEx.new()
	rx.compile("(?i)\\boro\\b")
	return rx.search(text) != null


func click_event(pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = get_viewport().get_mouse_position()
	ev.global_position = ev.position
	return ev


## Arrastra la tarjeta de reserva de `card` desde el panel de Ejército hasta `cell` (como el jugador).
func drag_from_roster(roster: Node, card: TroopCard, cell: Vector2) -> void:
	var btn: Control = null
	for c in roster._cards.get_children():
		if c.has_meta("card") and c.get_meta("card") == card:
			btn = c
	if btn == null:
		check(false, "tarjeta de reserva de %s en el Ejército" % card.unit_name)
		return
	get_viewport().warp_mouse(btn.get_global_rect().get_center())
	roster._on_card_gui_input(click_event(true), card)
	await frames(2)
	get_viewport().warp_mouse(cell)
	await frames(2)
	roster._on_card_gui_input(click_event(false), card)
	await frames(3)


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	OS.add_logger(logger)
	# Autocomprobación: el Logger debe capturar avisos de script (si no, el control de errores no sirve)
	push_warning("E2E_AUTOCOMPROBACION_LOGGER")
	await frames(1)
	logger.mutex.lock()
	var captured := logger.entries.any(func(e): return e.contains("E2E_AUTOCOMPROBACION_LOGGER"))
	logger.entries.clear()
	logger.mutex.unlock()
	check(captured, "el Logger captura avisos de script (autocomprobación)")
	# Este nodo sobrevive a los cambios de escena: la escena "actual" pasa a ser un nodo vacío.
	var dummy := Node.new()
	get_tree().root.add_child.call_deferred(dummy)
	await frames(1)
	get_tree().current_scene = dummy
	seed(20261003) # semilla fija (battle.gd y reward_screen vuelven a llamar a randomize(), por eso además hay ventaja explícita)
	await run()
	await boss_victory_flow()
	OS.remove_logger(logger)
	print("--- Errores/avisos capturados en tiempo de ejecución: %d ---" % logger.entries.size())
	for e in logger.entries:
		print("  ", e)
	check(logger.entries.is_empty(), "ningún error ni aviso de script en tiempo de ejecución (%d)" % logger.entries.size())
	for f in fails:
		print("FALLO: ", f)
	print("TEST DONE: %d fallos (%d ok)" % [fails.size(), passes])
	get_tree().quit()


func run() -> void:
	# ---------- Menú principal ----------
	# ---------- Menú principal → Centro de mando (v7.1) ----------
	get_tree().change_scene_to_file("res://Scenes/UI/main_menu.tscn")
	var menu0 := await wait_scene("res://Scenes/UI/main_menu.tscn")
	check(menu0 != null, "carga el menú principal")
	await shot("e2e_menu")
	menu0.play_button.pressed.emit()
	var cc := await wait_scene("res://Scenes/UI/command_center.tscn")
	check(cc != null, "Jugar abre el Centro de mando")
	await shot("e2e_centro_mando")
	cc.hotspots.war_table.pressed.emit()
	await frames(2)
	check(cc.is_confirm_open(), "la Mesa táctica pide confirmación")
	cc._confirm_yes.pressed.emit()

	# ---------- Selección inicial ----------
	var sel := await wait_scene("res://Scenes/UI/troop_selection_screen.tscn")
	check(sel != null and sel.offers.size() == 3, "selección: 3 reclutas")
	sel.select(1)
	await wait(0.2)
	await shot("e2e_seleccion")
	var chosen: TroopCard = sel.selected_card
	check(chosen != null and chosen.level == 1 and chosen.specialty == null, "elegido %s (Recluta Nv. 1, %s)" % [chosen.unit_name, chosen.get_weapon().display_name])
	sel._start_button.pressed.emit()

	# ---------- Mapa (ronda 1) ----------
	var map := await wait_scene("res://Scenes/Map/map.tscn")
	check(map != null, "carga el mapa")
	check(GameStateManager.get_bench_cards() == [chosen], "el recluta elegido está en la reserva")
	check(map._round_label.text == "RONDA 1", "mapa: ronda 1")
	map.skip_spin()
	await wait(0.3)
	check(not map._fight_button.disabled, "botón Luchar activo")
	await shot("e2e_mapa")
	map._fight_button.pressed.emit()

	# ---------- Batalla ronda 1: planificación ----------
	var battle := await wait_scene("res://Scenes/Battle/battle.tscn")
	check(battle != null, "carga la batalla")
	var roster = find_by_script(battle, "troop_roster_ui.gd")
	var detail = find_by_script(battle, "troop_detail_panel.gd")
	var shop = find_by_script(battle, "recruit_shop.gd")
	var prep = null
	for ch in battle.get_children():
		if "start_button" in ch:
			prep = ch
	var grid = battle.find_child("DeploymentGrid", true, false)
	check(roster and detail and shop and prep and grid, "planificación: ejército, submenú, tienda, botón y cuadrícula")
	check(prep.start_button.disabled, "sin desplegar no se puede combatir")
	print("Monedas/PM al empezar la ronda 1: %d / %d" % [GameStateManager.coins, GameStateManager.command_points])
	check(GameStateManager.coins == Economy.STARTING_COINS and GameStateManager.command_points == Economy.STARTING_POINTS,
			"se empieza con %d 💰 y %d ⭐ (Economy.STARTING_*)" % [Economy.STARTING_COINS, Economy.STARTING_POINTS])
	check(texts_of(prep).contains("💰") and texts_of(prep).contains("⭐") and not has_oro(texts_of(prep)), "la planificación muestra 💰/⭐ (sin 'oro')")
	await drag_from_roster(roster, chosen, grid.grid_cells[4])
	var deployed := player_troops()
	check(deployed.size() == 1 and deployed[0].card == chosen, "arrastrar la tarjeta al tablero despliega la tropa")
	check(GameStateManager.get_bench_cards().is_empty(), "la reserva queda vacía")
	await frames(3)
	check(not prep.start_button.disabled, "con una tropa se puede combatir")
	var hm = battle.find_child("EnemyHeatmap", true, false)
	check(hm != null and not hm.visible and battle.find_child("IntelLabel", true, false) != null, "v4: sin radioperador no hay mapa de calor (aviso en la zona enemiga)")
	await shot("e2e_planificacion")

	# Ventaja EXPLÍCITA del test: monedas y PM extra para subir a Nv. 3, comprar equipo y 2 reclutas más.
	# Lo que se verifica es el flujo, no la suerte; si aun así se pierde, se recorre el camino de derrota.
	GameStateManager.add_coins(60, "ventaja del test")
	GameStateManager.add_points(5, "ventaja del test")
	var pm0 := GameStateManager.command_points
	var troop1 = deployed[0]
	# Clic en la tarjeta del tablero en el Ejército → submenú
	var tcard: Button = null
	for c in roster._cards.get_children():
		if c.has_meta("card") and c.get_meta("card") == chosen:
			tcard = c
	check(tcard != null, "la tropa desplegada tiene tarjeta en el Ejército")
	tcard.pressed.emit()
	await wait(0.3)
	check(detail.visible and detail.card == chosen and detail.troop == troop1, "el submenú se abre con la tropa")
	check(detail._level_button.text.contains("Nv. 2") and detail._level_button.text.contains("⭐") and not detail._level_button.disabled, "botón 'Subir a Nv. 2 (⭐ 1)' activo (%s)" % detail._level_button.text)
	await shot("e2e_submenu")
	detail._level_button.pressed.emit()
	await wait(0.6)
	var modal = detail.level_up_choice
	check(modal.is_open() and chosen.pending_offers.size() >= 2, "modal de ascenso con 2 ofertas")
	check(chosen.pending_offers.all(func(o): return o.type != "specialty"), "Nv. 2: sin especialidades (llegan en Nv. 5)")
	await shot("e2e_modal")
	# Botón 👁: mantener pulsado oculta las cartas y deja ver la ficha; soltar las devuelve
	var eye_pos: Vector2 = modal._eye_button.get_global_rect().get_center()
	get_viewport().warp_mouse(eye_pos)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = eye_pos
	down.global_position = eye_pos
	Input.parse_input_event(down)
	await wait(0.3)
	check(modal.is_peeking() and not modal._center.visible and modal._peek_blocker.visible and modal.is_open(), "👁 pulsado: cartas ocultas, la elección sigue abierta y nada se puede tocar")
	await shot("e2e_modal_ojo")
	var up := down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await wait(0.2)
	check(not modal.is_peeking() and modal._center.visible and not modal._peek_blocker.visible, "👁 soltado: vuelven las cartas")
	modal._on_card_input(click_event(true), modal._cards[0])
	await wait(1.2)
	check(chosen.level == 2 and chosen.specialty == null and not modal.is_open(), "elige mejora: %s Nv. 2 (sigue Recluta)" % chosen.unit_name)
	check(GameStateManager.command_points == pm0 - Economy.level_cost(1), "subir a Nv. 2 cobró %d ⭐ (PM %d → %d)" % [Economy.level_cost(1), pm0, GameStateManager.command_points])
	check(troop1.get_node("NameLabel").text.contains("Nv.2"), "la etiqueta de la tropa muestra Nv.2")
	# Segunda subida
	detail._level_button.pressed.emit()
	await wait(0.6)
	check(modal.is_open() and chosen.pending_offers.size() >= 2 and chosen.pending_offers.all(func(o): return o.type != "specialty"),
			"Nv. 3: solo habilidades/entrenamiento (%s)" % str(chosen.pending_offers.map(func(o): return o.type)))
	check(chosen.pending_offers.all(func(o): return o.type == "skill" or o.type == "training"), "Nv. 3: nunca objetos ni armas")
	check(GameStateManager.command_points == pm0 - Economy.level_cost(1) - Economy.level_cost(2), "subir a Nv. 3 cobró %d ⭐" % Economy.level_cost(2))
	await shot("e2e_modal2")
	var off: Dictionary = chosen.pending_offers[1]
	var items_before_choice: int = chosen.items.size() # el recluta puede traer un objeto de serie (v3.1)
	modal._on_card_input(click_event(true), modal._cards[1])
	await wait(1.2)
	check(chosen.level == 3 and chosen.pending_offers.is_empty(), "elige %s: Nv. 3" % (off.resource.display_name if off.resource else "Entrenamiento"))
	match String(off.type):
		"skill": check(chosen.skills.has(off.resource) and chosen.items.size() == items_before_choice, "habilidad añadida (no ocupa hueco: %d/3)" % chosen.items.size())
		"training": check(chosen.training_ranks == 1, "entrenamiento aplicado (rangos %d)" % chosen.training_ranks)
	await wait(0.2)
	await shot("e2e_submenu_nv3")
	detail.close()
	await frames(2)
	check(not GameStateManager.ui_blocking, "cerrar el submenú desbloquea")

	# ---------- Intendencia: equipo ----------
	EventBus.shop_requested.emit("equipo")
	await wait(0.3)
	check(shop.visible and shop.current_tab() == "equipo", "shop_requested('equipo') abre la Intendencia en la pestaña Equipo")
	var st := texts_of(shop)
	check(st.contains("INTENDENCIA") and st.contains("💰") and st.contains("⭐") and not has_oro(st), "Intendencia: título, 💰/⭐ y sin 'oro'")
	var eq_offers: Array = GameStateManager.equipment_offers
	check(eq_offers.size() == Economy.EQUIPMENT_OFFERS, "la Intendencia ofrece %d objetos/armas" % Economy.EQUIPMENT_OFFERS)
	await shot("e2e_intendencia")
	var buy_idx := -1
	# v3.1: el recluta puede traer un objeto de serie; se le quita para que quepa cualquier compra
	chosen.items.clear()
	for i in eq_offers.size():
		if eq_offers[i] is ItemData and Economy.price_of(eq_offers[i]) <= GameStateManager.coins and chosen.can_add_item(eq_offers[i]):
			buy_idx = i
			break
	check(buy_idx >= 0, "hay un objeto asequible en la Intendencia")
	var bought: ItemData = null
	if buy_idx >= 0:
		bought = eq_offers[buy_idx]
		var coins_b := GameStateManager.coins
		shop._equip_buttons[buy_idx].pressed.emit()
		await wait(0.2)
		check(GameStateManager.coins == coins_b - Economy.price_of(bought) and bought in GameStateManager.player_bench and GameStateManager.equipment_offers[buy_idx] == null,
				"comprar %s por %d 💰: cobra, va al inventario y la oferta queda vendida" % [bought.display_name, Economy.price_of(bought)])
		check(texts_of(shop).contains("Vender +%d 💰" % Economy.sell_price(bought)), "el inventario de la Intendencia ofrece venderlo (+%d 💰)" % Economy.sell_price(bought))
		check(GameStateManager.equip_item_from_bench(chosen, bought) and chosen.has_item(bought.id) and not bought in GameStateManager.player_bench, "equiparlo a %s (equip_item_from_bench)" % chosen.unit_name)
	shop.close()
	await frames(3)
	if bought:
		for c in roster._cards.get_children():
			if c.has_meta("card") and c.get_meta("card") == chosen:
				tcard = c
		tcard.pressed.emit()
		await wait(0.3)
		check(detail.visible and detail.card == chosen and texts_of(detail).contains(bought.display_name), "el objeto comprado aparece en la card de %s" % chosen.unit_name)
		await shot("e2e_objeto_equipado")
		detail.close()
		await frames(2)

	# ---------- Intendencia: reclutas ----------
	var empty_slot: Button = null
	for c in roster._cards.get_children():
		if c.has_meta("empty_slot"):
			empty_slot = c
			break
	empty_slot.pressed.emit()
	await wait(0.3)
	check(shop.visible and shop.current_tab() == "reclutas", "pulsar un hueco vacío abre la Intendencia en Reclutas")
	var offer: TroopCard = shop.get_offers()[0]
	var gold_before := GameStateManager.coins
	check(gold_before >= Economy.recruit_price(offer), "hay monedas para reclutar (%d 💰 ≥ %d)" % [gold_before, Economy.recruit_price(offer)])
	await shot("e2e_tienda")
	shop._buy_buttons[offer].pressed.emit()
	await wait(0.2)
	check(GameStateManager.coins == gold_before - Economy.recruit_price(offer) and GameStateManager.get_bench_cards().has(offer),
			"comprar %s por %d 💰" % [offer.unit_name, Economy.recruit_price(offer)])
	# Segundo recluta comprado (parte de la ventaja explícita)
	var offer2: TroopCard = null
	for o in shop.get_offers():
		if GameStateManager.coins >= Economy.recruit_price(o):
			offer2 = o
			break
	if offer2:
		shop._buy_buttons[offer2].pressed.emit()
		await wait(0.2)
	shop.close()
	await frames(3)
	await drag_from_roster(roster, offer, grid.grid_cells[6])
	check(player_troops().size() == 2 and player_troops().any(func(t): return t.card == offer), "el recluta comprado se despliega")
	if offer2:
		await drag_from_roster(roster, offer2, grid.grid_cells[7])
		check(player_troops().size() == 3, "el segundo recluta comprado también se despliega")
	await wait(0.3)
	await shot("e2e_planificacion2")
	var positions := {}
	for t in player_troops():
		positions[t.card] = t.global_position

	# ---------- Combate ----------
	var coins_fight := GameStateManager.coins
	var pm_fight := GameStateManager.command_points
	prep.start_button.pressed.emit()
	await wait(1.6)
	await shot("e2e_combate_1")
	await wait(1.6)
	await shot("e2e_combate_2")
	var t_fight := 3.2
	var reward = null
	var over = null
	while t_fight < FIGHT_TIMEOUT:
		await wait(0.25)
		t_fight += 0.25
		if not is_instance_valid(battle):
			break
		for ch in battle.get_children():
			if ch.get_script() and ch.get_script().resource_path.ends_with("reward_screen.gd"):
				reward = ch
			if ch.get_script() and ch.get_script().resource_path.ends_with("game_over_panel.gd"):
				over = ch
		if reward or over:
			break
	print("Combate ronda 1 terminado en %.1f s" % t_fight)
	check(t_fight < FIGHT_TIMEOUT, "el combate termina solo (%.1f s)" % t_fight)
	check(reward != null or over != null, "el combate acaba en recompensas o en fin de partida")
	if reward == null:
		# Derrota por azar pese a la ventaja: no es un fallo, se recorre el camino de derrota.
		print("AVISO: derrota en la ronda 1 (azar); se recorre el camino de derrota y se omite la ronda 2")
		await defeat_flow(over)
		return
	await wait(0.4)
	await shot("e2e_recompensas")
	var sm: Dictionary = GameStateManager.last_round_summary
	print("Resumen ronda 1: ", sm)
	check(int(sm.get("kills", 0)) > 0 and int(sm.get("kill_coins", 0)) >= int(sm.get("kills", 0)) * Economy.COINS_PER_KILL, "la ronda 1 registró bajas y monedas por baja (%d bajas → +%d 💰)" % [sm.get("kills", 0), sm.get("kill_coins", 0)])
	check(int(sm.get("win_coins", 0)) == Economy.WIN_BONUS_COINS and int(sm.get("points", 0)) >= Economy.POINTS_PER_WIN, "bonus de victoria (+%d 💰) y PM (+%d ⭐)" % [sm.get("win_coins", 0), sm.get("points", 0)])
	check(GameStateManager.coins - coins_fight == int(sm.kill_coins) + int(sm.win_coins) + int(sm.interest), "monedas tras ganar = antes + bajas + bonus + interés (%d → %d)" % [coins_fight, GameStateManager.coins])
	check(GameStateManager.command_points - pm_fight == int(sm.points), "PM tras ganar = antes + %d" % int(sm.points))
	check(int(sm.coins_total) == GameStateManager.coins and int(sm.points_total) == GameStateManager.command_points, "el resumen refleja los totales")
	var rt := texts_of(reward)
	check(rt.contains("Bajas") and rt.contains("💰") and rt.contains("⭐") and not has_oro(rt), "pantalla de recompensa: Bajas, 💰 y ⭐, sin 'oro'")
	await shot("e2e_recompensa_v3")
	reward.next_battle_button.pressed.emit()

	# ---------- Mapa ronda 2 ----------
	var map2 := await wait_scene("res://Scenes/Map/map.tscn")
	check(map2 != null and map2._round_label.text == "RONDA 2", "mapa de la ronda 2")
	await wait(0.6)
	await shot("e2e_mapa2_girando")
	map2.skip_spin()
	await wait(0.3)
	await shot("e2e_mapa2")
	map2._fight_button.pressed.emit()

	# ---------- Batalla ronda 2 ----------
	var battle2 := await wait_scene("res://Scenes/Battle/battle.tscn")
	check(battle2 != null, "carga la batalla de la ronda 2")
	await wait(0.4)
	var r2 := player_troops()
	check(r2.size() == positions.size(), "las %d tropas persisten en la ronda 2" % positions.size())
	var same_cards := true
	for t in r2:
		same_cards = same_cards and positions.has(t.card) and positions[t.card] == t.global_position
		same_cards = same_cards and is_equal_approx(t.health, t.get_max_health())
	check(same_cards, "mismo card, misma casilla y vida al máximo")
	var vet_ok := r2.any(func(t): return t.card == chosen and t.level == 3 and t.get_node("NameLabel").text.contains("Nv.3"))
	check(vet_ok, "%s sigue en Nv. 3 con sus mejoras" % chosen.unit_name)
	await shot("e2e_ronda2")
	# Abrir el submenú en la ronda 2 para ver que todo sigue ahí
	var detail2 = find_by_script(battle2, "troop_detail_panel.gd")
	for t in r2:
		if t.card == chosen:
			EventBus.troop_inspect_requested.emit(t)
	await wait(0.3)
	check(detail2.visible and detail2.card == chosen, "el submenú de la ronda 2 muestra la tropa")
	# Subida de nivel con PM ganados en la ronda 1
	var pm_r2 := GameStateManager.command_points
	var cost_r2 := Economy.level_cost(chosen.level)
	check(pm_r2 >= cost_r2 and not detail2._level_button.disabled, "con los PM ganados se puede subir a Nv. 4 (⭐ %d, hay %d)" % [cost_r2, pm_r2])
	detail2._level_button.pressed.emit()
	await wait(0.6)
	var modal2 = detail2.level_up_choice
	check(modal2.is_open() and chosen.pending_offers.all(func(o): return o.type == "skill" or o.type == "training"), "Nv. 4: solo habilidades/entrenamiento")
	modal2._on_card_input(click_event(true), modal2._cards[0])
	await wait(1.2)
	check(chosen.level == 4 and GameStateManager.command_points == pm_r2 - cost_r2, "subir a Nv. 4 cobra %d ⭐ (quedan %d)" % [cost_r2, GameStateManager.command_points])
	# Objetos sueltos (truco de test) equipados desde la lista de la reserva del submenú
	for id in ["granada", "chaleco_tactico", "botiquin", "balas_incendiarias"]:
		var it: ItemData = GameContent.find_item(id)
		if not chosen.has_item(id):
			GameStateManager.add_item(it)
	await frames(2)
	var skip := 0 # botones que no se pueden equipar (regla de huecos): se prueba el siguiente
	for k in 10:
		if chosen.items.size() >= TroopCard.MAX_ITEM_SLOTS:
			break
		var btn: Button = null
		var idx := 0
		for b in detail2._bench_box.get_children():
			if is_instance_valid(b) and not b.is_queued_for_deletion() and b is Button:
				if idx == skip:
					btn = b
					break
				idx += 1
		if btn == null:
			break
		var before := chosen.items.size()
		btn.pressed.emit() # el submenú se reconstruye: se vuelve a buscar el botón
		await frames(2)
		if chosen.items.size() == before:
			skip += 1
	check(chosen.items.size() == TroopCard.MAX_ITEM_SLOTS, "equipar objetos desde el submenú hasta llenar los 3 huecos")
	var desc_ok := true
	for row in detail2._slots_box.get_children():
		var texts: Array[String] = []
		for l in row.find_children("*", "Label", true, false):
			texts.append(l.text)
		var joined := " | ".join(texts)
		desc_ok = desc_ok and not joined.contains("efecto especial")
	check(desc_ok, "los huecos muestran la descripción real del objeto")
	check(detail2._status_label.text.contains("máx. 3"), "pie: 'cada objeto ocupa 1 hueco (máx. 3)'")
	await wait(0.2)
	await shot("e2e_ronda2_submenu")
	detail2.close()
	await frames(2)
	await shot("e2e_ronda2_etiquetas")

	# ---------- Derrota (forzada y explícita, para recorrer ese camino de forma determinista) ----------
	var prep2 = null
	for ch in battle2.get_children():
		if "start_button" in ch:
			prep2 = ch
	prep2.start_button.pressed.emit()
	await wait(0.8)
	for t in player_troops():
		t.die() # derrota forzada por el test
	var over2 = null
	for k in 40:
		await wait(0.1)
		for ch in battle2.get_children():
			if ch.get_script() and ch.get_script().resource_path.ends_with("game_over_panel.gd"):
				over2 = ch
		if over2:
			break
	check(over2 != null, "sin tropas vivas → panel de fin de partida")
	await defeat_flow(over2)


## Panel de derrota: título, captura y "Reiniciar run" → vuelve a la selección inicial.
func defeat_flow(over: Node) -> void:
	if over == null:
		return
	await wait(0.4)
	check(over.title_label.text.contains("DERROTA"), "el panel anuncia la derrota (%s)" % over.title_label.text.replace("\n", " / "))
	await shot("e2e_derrota")
	over.restart_button.pressed.emit()
	var sel := await wait_scene("res://Scenes/UI/troop_selection_screen.tscn")
	check(sel != null and sel.offers.size() == 3, "Reiniciar run vuelve a la selección inicial")
	check(GameStateManager.current_stage == 1 and GameStateManager.get_army_size() == 0, "la partida se reinicia (ronda 1, ejército vacío)")


## Victoria contra el jefe: panel de victoria, captura y "Menú principal".
func boss_victory_flow() -> void:
	ProfileManager.persist = false # no tocar el perfil real del jugador
	GameStateManager.reset_run()
	GameStateManager.current_stage = 12
	GameStateManager.current_node_type = GameStateManager.BOSS_TYPE
	GameStateManager.rolled_round = 12
	get_tree().change_scene_to_file("res://Scenes/Battle/battle.tscn")
	var bt := await wait_scene("res://Scenes/Battle/battle.tscn")
	check(bt != null, "batalla contra el jefe")
	if bt == null:
		return
	bt._show_reward_screen() # el jefe ha caído: derrotarlo gana la partida
	await wait(0.4)
	var panel = null
	for ch in bt.get_children():
		if ch.get_script() and ch.get_script().resource_path.ends_with("game_over_panel.gd"):
			panel = ch
	check(panel != null and panel.title_label.text.contains("VICTORIA"), "derrotar al jefe muestra el panel de victoria")
	await shot("e2e_victoria_jefe")
	if panel:
		if not panel.vault_decided:
			panel.select_candidate(0)
			if ProfileManager.is_vault_full():
				panel.select_replace(0)
			check(panel.confirm_store(), "guarda un veterano en el Cuartel")
		panel.main_menu_button.pressed.emit()
		var menu := await wait_scene("res://Scenes/UI/main_menu.tscn")
		check(menu != null, "Menú principal vuelve al menú")
	ProfileManager.persist = true
	ProfileManager.load_profile()
