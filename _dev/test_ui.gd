extends Node
## Tests de la interfaz (SPEC v2 §9): submenú de tropa, modal de ascenso, roster, tienda,
## selección inicial y prueba integrada con battle.tscn. Hace capturas en res://_dev/shots/ui_*.png.

const DETAIL_SCRIPT = preload("res://Scripts/UI/troop_detail_panel.gd")
const ROSTER_SCRIPT = preload("res://Scripts/UI/troop_roster_ui.gd")
const SHOP_SCENE = preload("res://Scenes/UI/recruit_shop.tscn")
const SELECTION_SCENE = preload("res://Scenes/UI/troop_selection_screen.tscn")

var _fails: Array[String] = []
var _passes := 0
var rng := RandomNumberGenerator.new()
var detail
var roster
var shop
var _bg: CanvasLayer


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


func _press_esc() -> void:
	var k := InputEventKey.new()
	k.keycode = KEY_ESCAPE
	k.physical_keycode = KEY_ESCAPE
	k.pressed = true
	Input.parse_input_event(k)
	var k2 := k.duplicate()
	k2.pressed = false
	Input.parse_input_event(k2)


func _set_coins(g: int) -> void:
	GameStateManager.coins = g
	EventBus.roster_changed.emit()


func _set_points(p: int) -> void:
	GameStateManager.command_points = p
	EventBus.roster_changed.emit()


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	rng.seed = 777
	print("Viewport: ", get_viewport().get_visible_rect().size)
	GameStateManager.reset_run()
	_bg = CanvasLayer.new()
	_bg.layer = -1
	var cr := ColorRect.new()
	cr.color = Color(0.2, 0.27, 0.2)
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.add_child(cr)
	add_child(_bg)

	roster = ROSTER_SCRIPT.new()
	add_child(roster)
	detail = DETAIL_SCRIPT.new()
	add_child(detail)
	shop = SHOP_SCENE.instantiate()
	add_child(shop)
	await _frames()

	await _test_recruit_detail()
	await _test_level_up_flow()
	await _test_items_and_weapons()
	await _test_offer_screens()
	await _test_roster()
	await _test_shop()
	await _test_selection()
	for n in [roster, detail, shop]:
		if is_instance_valid(n):
			n.queue_free()
	await _frames(3)
	await _test_battle_integration()

	print("TEST DONE: %d fallos (%d ok)" % [_fails.size(), _passes])
	for f in _fails:
		print("  FALLO: ", f)
	GameStateManager.reset_run()
	get_tree().quit()


func _find_tile(c: TroopCard) -> Control:
	for t in roster._cards.get_children():
		if t.has_meta("card") and t.get_meta("card") == c:
			return t
	return null


func _texts(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	elif n is Button:
		out += (n as Button).text + "\n"
	for c in n.get_children():
		out += _texts(c)
	return out


# ------------------------------------------------------------------------------------------

func _test_recruit_detail() -> void:
	var c := UnitFactory.make_recruit(rng)
	c.items.clear() # v3.1: algunos reclutas traen objeto; aquí se prueba con la tropa sin objetos
	GameStateManager.add_troop_to_army(c)
	_set_coins(500) # las monedas no cuentan para subir de nivel
	_set_points(0)
	detail.open_card(c)
	await _frames(3)
	_check(detail.visible and detail.card == c, "submenú abierto con un TroopCard de la reserva")
	_check(GameStateManager.ui_blocking, "el submenú activa ui_blocking")
	var txt := _texts(detail)
	_check(txt.contains(c.unit_name) and txt.contains("Recluta") and txt.contains("Nv. 1"), "cabecera: nombre, Recluta y Nv. 1")
	var s := TroopStats.compute(c)
	_check(txt.contains(str(roundi(s.max_health))) and txt.contains("%d %%" % roundi(s.damage_mult * 100.0)), "Vida y Daño de TroopStats visibles")
	_check(detail._level_button.disabled, "sin PM el botón de subir está desactivado (aunque haya monedas)")
	_check(detail._level_button.text.contains("Nv. 2") and detail._level_button.text.contains("⭐ 1") and not detail._level_button.text.contains("💰"), "botón 'Subir a Nv. 2 (⭐ 1)'")
	_check(detail._level_button.tooltip_text.contains("Faltan 1 ⭐"), "tooltip 'Faltan 1 ⭐' sin PM")
	_check(not detail._return_button.visible, "tropa de reserva: sin botón de retirar")
	await _wait(0.3)
	await _shot("ui_detail_recluta")
	detail.close()
	_check(not detail.visible and not GameStateManager.ui_blocking, "cerrar el submenú libera ui_blocking")
	set_meta("c1", c)


func _test_level_up_flow() -> void:
	var c: TroopCard = get_meta("c1")
	c.level = TroopCard.SPECIALTY_LEVEL - 1 # v3.2: la especialidad se elige al subir a Nv. 5
	var spec_cost := Economy.level_cost(c.level)
	_set_coins(100)
	_set_points(5)
	detail.open_card(c)
	await _frames()
	_check(not detail._level_button.disabled, "con PM el botón está activo")
	detail._on_level_up_pressed()
	await _frames()
	_check(GameStateManager.command_points == 5 - spec_cost and GameStateManager.coins == 100, "subir a Nv. 5 cobra %d PM y no monedas (PM %d)" % [spec_cost, GameStateManager.command_points])
	_check(c.pending_offers.size() >= 2, "hay 2 ofertas pendientes")
	var all_spec := true
	for o in c.pending_offers:
		if o.type != "specialty":
			all_spec = false
	_check(all_spec, "Nv. 4 → 5 ofrece 2 especialidades")
	var modal = detail.level_up_choice
	_check(modal.is_open(), "el modal de ascenso se abre")
	_check(modal.layer == 30, "el modal está en la capa 30")
	await _wait(0.7)
	await _shot("ui_levelup_especialidades")

	# No se puede cerrar sin elegir
	_check(not modal.try_close(), "try_close() sin elegir se rechaza")
	_press_esc()
	await _frames(3)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	modal._on_dim_input(click)
	await _frames(2)
	_check(modal.is_open() and detail.visible, "Esc y clic en el fondo no cierran el modal ni el submenú")

	# Cerrar el submenú por otro motivo y reabrir: el modal vuelve a salir
	modal.visible = false
	detail.close()
	detail.open_card(c)
	await _frames()
	_check(modal.is_open(), "al reabrir con ofertas pendientes el modal sale directamente")

	var spec: SpecialtyData = c.pending_offers[0].resource
	_check(modal.choose_offer(0), "elegir la primera oferta")
	_check(c.specialty == spec and c.level == TroopCard.SPECIALTY_LEVEL and c.pending_offers.is_empty(), "la tropa tiene la especialidad elegida y es Nv. 5")
	await _wait(1.0)
	_check(not modal.visible, "el modal se cierra tras la animación")
	_check(GameStateManager.ui_blocking, "el submenú sigue bloqueando al cerrar el modal")
	_check(_texts(detail).contains(spec.display_name), "el submenú muestra la especialidad nueva")

	# Siguientes ascensos: ofertas mezcladas, nunca especialidades
	_set_points(5000)
	var types := {}
	var spec_again := false
	var ok_levels := true
	for i in TroopCard.MAX_LEVEL - c.level:
		var lv := c.level
		var g := GameStateManager.command_points
		detail._on_level_up_pressed()
		await _frames()
		if GameStateManager.command_points != g - Economy.level_cost(lv):
			ok_levels = false
		for o in c.pending_offers:
			types[o.type] = true
			if o.type == "specialty":
				spec_again = true
		modal.choose_offer(rng.randi_range(0, c.pending_offers.size() - 1))
		for _w in 40: # espera a que termine la animación (más robusto que un tiempo fijo)
			if not modal.is_open():
				break
			await _wait(0.1)
		await _wait(0.1)
		if c.level != lv + 1:
			ok_levels = false
	_check(ok_levels, "cada ascenso cobra Economy.LEVEL_COST[nivel] PM y sube 1 nivel (ahora Nv. %d)" % c.level)
	_check(not spec_again, "después de Nv. 5 no se ofrecen especialidades")
	_check(types.has("skill") and not types.has("item") and not types.has("weapon"), "ascensos posteriores: solo habilidades/entrenamiento: %s" % str(types.keys()))
	c.level = TroopCard.MAX_LEVEL
	EventBus.roster_changed.emit()
	await _frames()
	_check(detail._level_button.disabled and detail._level_button.text.contains("máximo"), "en Nv. 10 el botón está desactivado")
	detail.close()


func _test_items_and_weapons() -> void:
	var c := UnitFactory.make_recruit(rng)
	c.items.clear() # v3.1: algunos reclutas traen objeto; aquí se prueba con la tropa sin objetos
	c.unit_name = "Kowalski"
	c.specialty = GameContent.find_specialty("soldado")
	c.level = 6
	c.weapons.assign([GameContent.find_weapon("fusil_asalto"), GameContent.find_weapon("escopeta"), GameContent.find_weapon("cuchillo")])
	c.equipped_weapon = 0
	for id in ["piel_dura", "pulso_firme", "ojo_certero", "oficial"]:
		c.skills.append(GameContent.find_skill(id))
	GameStateManager.add_troop_to_army(c)
	var ids := ["balas_huecas", "chaleco_tactico", "granada", "botiquin", "balas_incendiarias"]
	var items: Array[ItemData] = []
	for id in ids:
		var it := GameContent.find_item(id)
		items.append(it)
		GameStateManager.add_item(it)
	_set_coins(400)
	detail.open_card(c)
	await _frames()
	_check(detail._bench_box.get_child_count() == 5, "lista de objetos sueltos que caben (5)")
	_check(detail.equip_bench_item(items[0]) and detail.equip_bench_item(items[1]) and detail.equip_bench_item(items[2]), "equipar 3 objetos desde la reserva")
	_check(c.items.size() == 3 and not items[0] in GameStateManager.player_bench, "3 huecos ocupados y salen de la reserva")
	_check(not detail.equip_bench_item(items[3]) and c.items.size() == 3 and items[3] in GameStateManager.player_bench, "no se puede equipar un 4.º objeto")
	await _frames()
	_check(_texts(detail).contains("Huecos llenos"), "con 3 objetos el submenú avisa de huecos llenos")
	_check(detail.remove_item(items[2]) and c.items.size() == 2 and items[2] in GameStateManager.player_bench, "Quitar devuelve el objeto a la reserva")
	await _frames()
	var listed := false
	for b in detail._bench_box.get_children():
		if b is Button and (b as Button).text.contains(items[2].display_name):
			listed = true
	_check(listed, "el objeto quitado vuelve a la lista de la reserva")
	_check(not detail.equip_bench_item(items[4]), "no caben 2 de munición")
	detail.equip_bench_item(items[2])
	await _frames()
	_check(_texts(detail).contains("3/3"), "el submenú muestra 3/3 huecos")

	# Cambiar de arma
	detail.equip_weapon(1)
	await _frames()
	_check(c.equipped_weapon == 1 and TroopStats.compute(c).weapon.id == "escopeta", "cambiar de arma desde el arsenal")
	_check(_texts(detail).contains("EQUIPADA"), "el arsenal marca el arma equipada")
	detail.equip_weapon(0)
	await _frames()
	var txt := _texts(detail)
	_check(txt.contains("Piel dura") and txt.contains("no ocupan hueco"), "habilidades como chips y aviso de que no ocupan hueco")
	_check(txt.contains(GameContent.find_specialty("soldado").passive_name), "se muestra la mecánica de la especialidad (Fuego de supresión)")
	await _wait(0.3)
	await _shot("ui_detail_completo")
	detail.close()
	set_meta("c2", c)


func _test_offer_screens() -> void:
	var c: TroopCard = get_meta("c2")
	var removed: ItemData = c.items[2]
	c.remove_item(removed) # deja un hueco libre para que la oferta de objeto sea realista
	var lv := c.level
	c.pending_offers = [
		{"type": "skill", "resource": GameContent.find_skill("sangre_fria")},
		{"type": "training", "resource": null},
	]
	detail.open_card(c)
	await _wait(0.7)
	_check(detail.level_up_choice.is_open(), "modal abierto con habilidad / entrenamiento")
	var mt := _texts(detail.level_up_choice)
	_check(mt.contains("HABILIDAD") and mt.contains("No ocupa hueco") and mt.contains("ENTRENAMIENTO") and mt.contains("6"), "etiquetas de tipo, aclaración de huecos y +6 % de entrenamiento")
	await _shot("ui_levelup_habilidad_objeto")
	detail.level_up_choice.choose_offer(0)
	await _wait(1.0)
	_check(c.has_skill("sangre_fria") and c.level == lv + 1, "elegir habilidad la añade y sube de nivel")
	var ranks := c.training_ranks
	c.pending_offers = [
		{"type": "training", "resource": null},
		{"type": "skill", "resource": GameContent.find_skill("piel_dura")},
	]
	detail._on_level_up_pressed()
	await _wait(0.7)
	detail.level_up_choice.choose_offer(0)
	await _wait(1.0)
	_check(c.training_ranks == ranks + 1 and c.level == lv + 2, "elegir entrenamiento suma 1 rango y sube de nivel")

	var cur_items := c.items.size()
	c.pending_offers = [
		{"type": "weapon", "resource": GameContent.find_weapon("rifle_francotirador")},
		{"type": "item", "resource": GameContent.find_item("botiquin")},
	]
	detail._on_level_up_pressed() # con ofertas pendientes abre el modal
	await _wait(0.7)
	var mt2 := _texts(detail.level_up_choice)
	_check(mt2.contains("ARMA") and (mt2.contains("↑") or mt2.contains("↓")), "carta de arma con comparación ↑↓")
	await _shot("ui_levelup_arma")
	var nweap := c.weapons.size()
	detail.level_up_choice.choose_offer(0)
	await _wait(1.0)
	_check(c.weapons.size() == nweap + 1 and c.equipped_weapon == 0 and c.items.size() == cur_items, "elegir arma la añade al arsenal sin cambiar la equipada")
	detail.close()
	GameStateManager.equip_item_from_bench(c, removed)


func _test_roster() -> void:
	await _frames(3)
	var c1: TroopCard = get_meta("c1")
	var c2: TroopCard = get_meta("c2")
	var t1 := _find_tile(c1)
	var t2 := _find_tile(c2)
	_check(t1 != null and t2 != null, "el roster tiene una tarjeta por tropa de la reserva")
	if t1 and t2:
		var x1 := _texts(t1)
		var x2 := _texts(t2)
		_check(x1.contains(c1.unit_name) and x1.contains(c1.get_specialty_name()) and x1.contains("Nv. %d" % c1.level), "tarjeta: nombre, especialidad y nivel")
		_check(x2.contains("●●●") and x2.contains(UiKit.emo(c2.get_weapon().emoji)), "tarjeta: huecos ●●● y emoji del arma")
	var c3 := UnitFactory.make_recruit(rng)
	c3.items.clear()
	GameStateManager.add_troop_to_army(c3)
	await _frames(3)
	var t3 := _find_tile(c3)
	_check(t3 != null and _texts(t3).contains("Recluta") and _texts(t3).contains("○○○"), "tarjeta de recluta: Recluta y ○○○")
	var empties := 0
	var item_tiles := 0
	for t in roster._cards.get_children():
		if t.has_meta("empty_slot"):
			empties += 1
		if t.has_meta("item"):
			item_tiles += 1
	_check(empties == 3, "3 tropas → 3 huecos vacíos (6 en total)")
	_check(item_tiles == GameStateManager.get_bench_items().size(), "los objetos sueltos se muestran en el roster")
	_check(roster.panel.is_in_group("troop_return_zone"), "el roster sigue siendo zona de retirada")
	await _wait(0.2)
	await _shot("ui_roster")


func _test_shop() -> void:
	GameStateManager.shop_offers.clear()
	_set_coins(200)
	EventBus.recruit_shop_requested.emit()
	await _frames(3)
	_check(shop.visible and GameStateManager.ui_blocking, "la Intendencia se abre desde un hueco vacío y bloquea")
	_check(shop.current_tab() == "reclutas", "recruit_shop_requested abre la pestaña Reclutas")
	_check(shop.get_offers().size() == 3 and GameStateManager.shop_offers.size() == 3, "la tienda tiene 3 ofertas guardadas en shop_offers")
	var txt := _texts(shop)
	var o0: TroopCard = shop.get_offers()[0]
	_check(txt.contains(o0.unit_name) and txt.contains(o0.get_weapon().display_name) and txt.contains("VIDA") and txt.contains("DAÑO"), "ficha: nombre, arma, Vida y Daño")
	_check(txt.contains("%d 💰" % Economy.recruit_price(o0)), "ficha: precio de Economy.recruit_price en 💰")
	await _wait(0.2)
	await _shot("ui_tienda")
	var price := Economy.recruit_price(o0)
	var army := GameStateManager.get_army_size()
	_check(shop.buy(o0), "comprar un recluta")
	_check(GameStateManager.coins == 200 - price, "comprar cobra el precio (%d 💰)" % price)
	_check(not o0 in shop.get_offers() and shop.get_offers().size() == 2, "comprar quita la oferta")
	_check(o0 in GameStateManager.player_bench and GameStateManager.get_army_size() == army + 1, "el recluta llega a la reserva")
	shop.close()
	EventBus.recruit_shop_requested.emit()
	await _frames()
	_check(shop.get_offers().size() == 2, "reabrir la tienda en la misma ronda no regenera ofertas")
	_set_coins(0)
	await _frames()
	_check(_texts(shop).contains("Faltan") and _texts(shop).contains("💰"), "sin monedas: 'Faltan X 💰'")
	while GameStateManager.has_free_army_slot():
		GameStateManager.add_troop_to_army(UnitFactory.make_recruit(rng))
	_set_coins(500)
	await _frames()
	_check(_texts(shop).contains("Ejército lleno"), "ejército completo: 'Ejército lleno'")
	_press_esc()
	await _frames(3)
	_check(not shop.visible and not GameStateManager.ui_blocking, "Esc cierra la tienda")
	EventBus.recruit_shop_requested.emit()
	await _frames()
	EventBus.battle_fight_started.emit()
	await _frames()
	_check(not shop.visible, "iniciar combate cierra la tienda")
	GameStateManager.advance_stage()
	_check(GameStateManager.shop_offers.is_empty(), "advance_stage vacía las ofertas")


func _test_selection() -> void:
	# El roster se elimina al empezar combate (señal emitida antes); lo recreamos no hace falta.
	var sel = SELECTION_SCENE.instantiate()
	sel.change_scene_on_start = false
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	layer.add_child(sel)
	await _frames(3)
	_check(sel.offers.size() == 3, "la selección inicial ofrece 3 reclutas")
	var names_ok := true
	for o in sel.offers:
		if not (o is TroopCard) or o.level != 1 or o.specialty != null or o.weapons.is_empty():
			names_ok = false
	_check(names_ok, "los 3 son reclutas Nv. 1 con arma")
	_check(sel._start_button.disabled, "Comenzar desactivado sin elegir")
	sel.select(1)
	await _wait(0.2)
	await _shot("ui_seleccion")
	var chosen: TroopCard = sel.offers[1]
	GameStateManager.coins = 99
	GameStateManager.command_points = 77
	_check(sel.confirm_selection(), "Comenzar con selección")
	_check(GameStateManager.player_bench.size() == 1 and GameStateManager.player_bench[0] == chosen \
			and GameStateManager.coins == Economy.STARTING_COINS and GameStateManager.command_points == Economy.STARTING_POINTS,
			"Comenzar reinicia la partida (monedas y PM iniciales) y añade el elegido")
	layer.queue_free()
	await _frames()


func _test_battle_integration() -> void:
	if not ResourceLoader.exists("res://Scenes/Battle/battle.tscn"):
		_check(false, "battle.tscn existe")
		return
	GameStateManager.reset_run()
	var deployed := UnitFactory.make_recruit(rng)
	deployed.unit_name = "Ríos"
	GameStateManager.deployed_troops_data = [{"card": deployed, "position": Vector2(260, 330)}]
	for i in 2:
		GameStateManager.add_troop_to_army(UnitFactory.make_recruit(rng))
	var reserve_lv := UnitFactory.make_recruit(rng)
	reserve_lv.specialty = GameContent.find_specialty("medico")
	reserve_lv.level = 4
	reserve_lv.items.append(GameContent.find_item("botiquin"))
	GameStateManager.add_troop_to_army(reserve_lv)
	GameStateManager.add_item(GameContent.find_item("granada"))
	GameStateManager.coins = 120
	GameStateManager.command_points = 5
	_bg.visible = false
	var battle = load("res://Scenes/Battle/battle.tscn").instantiate()
	add_child(battle)
	await _wait(0.5)
	var troop: Node = null
	for t in get_tree().get_nodes_in_group("troops"):
		if t.get("card") == deployed:
			troop = t
	_check(troop != null, "battle.tscn restaura la tropa desplegada con su card")
	var bdetail = null
	var broster = null
	for n in battle.get_children():
		var sc = n.get_script()
		if sc and sc.resource_path.ends_with("troop_detail_panel.gd"):
			bdetail = n
		if sc and sc.resource_path.ends_with("troop_roster_ui.gd"):
			broster = n
	_check(bdetail != null and broster != null, "battle.tscn crea el submenú y el roster")
	if troop == null or bdetail == null:
		return
	await _shot("ui_batalla_roster")
	EventBus.troop_inspect_requested.emit(troop)
	await _frames(3)
	_check(bdetail.visible and bdetail.card == deployed and bdetail._return_button.visible, "submenú de una tropa del tablero (con botón de retirar)")
	var hp_before: float = troop.get_max_health()
	bdetail._on_level_up_pressed()
	await _wait(0.7)
	_check(bdetail.level_up_choice.is_open() and GameStateManager.command_points == 4 and GameStateManager.coins == 120, "subir desde el tablero cobra 1 PM y abre el modal")
	await _shot("ui_batalla_modal")
	bdetail.level_up_choice.choose_offer(1)
	await _wait(1.0)
	_check(deployed.level == 2 and deployed.specialty == null, "la tropa del tablero sube a Nv. 2 (la especialidad llega en Nv. 5)")
	_check(troop.level == 2 and troop.get_max_health() > hp_before, "el nodo tropa se refresca (Nv. y vida)")
	GameStateManager.equip_item_from_bench(deployed, GameContent.find_item("granada"))
	await _frames(3)
	_check(deployed.has_item("granada") and _texts(bdetail).contains("Granada"), "equipar desde la reserva en una tropa del tablero")
	await _shot("ui_batalla_detalle")
	bdetail._on_return_pressed()
	await _frames(3)
	_check(not bdetail.visible and deployed in GameStateManager.player_bench, "retirar a la reserva desde el submenú")
	battle.queue_free()
	await _frames(3)
