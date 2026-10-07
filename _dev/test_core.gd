extends Node
## Tests del núcleo (SPEC v2): recursos, TroopStats, LevelUpSystem, UnitFactory, GameContent y GSM.

var _fails: Array[String] = []
var _passes := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
		print("TEST PASS: ", name)
	else:
		_fails.append(name)
		print("TEST FAIL: ", name)


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	await get_tree().process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	_test_content()
	_test_recruit(rng)
	_test_stats()
	_test_level_up(rng)
	_test_mix(rng)
	_test_items_fit(rng)
	_test_requires(rng)
	_test_remove_item()
	_test_enemies(rng)
	_test_gsm()
	print("--- describe ---")
	for l in TroopStats.describe(UnitFactory.make_recruit(rng)):
		print("  ", l)
	print("TEST DONE: %d fallos (%d ok)" % [_fails.size(), _passes])
	for f in _fails:
		print("  FALLO: ", f)
	GameStateManager.reset_run()
	get_tree().quit()


func _card(weapon_id: String = "pistola") -> TroopCard:
	var c := TroopCard.new()
	c.unit_name = "Prueba"
	c.weapons.assign([GameContent.find_weapon(weapon_id)])
	return c


func _test_content() -> void:
	var ok := true
	for list in [GameContent.weapons(), GameContent.specialties(), GameContent.skills(), GameContent.items()]:
		for r in list:
			if r == null or r.id == "" or r.display_name == "" or r.description == "":
				ok = false
	_check(ok, "GameContent carga todo sin nulls ni campos vacíos")
	_check(GameContent.weapons().size() == 9 and GameContent.specialties().size() == 7, "9 armas (sin lanzagranadas) y 7 especialidades")
	# v6: especialidades nuevas
	var ids: Array = GameContent.specialties().map(func(sp): return sp.id)
	_check(ids == ["soldado", "medico", "comunicaciones", "mecanico", "infiltrado", "francotirador", "saboteador"], "v6: Soldado, Doctor, Radioperador, Mecánico, Infiltrado, Francotirador y Saboteador (%s)" % str(ids))
	_check(GameContent.find_specialty("medico").display_name == "Doctor", "v6: el Médico pasa a llamarse Doctor")
	var all_named := true
	for sid in ["mecanico", "infiltrado", "saboteador"]:
		var spn := GameContent.find_specialty(sid)
		var cn := _card("pistola")
		cn.specialty = spn
		if spn == null or spn.display_name == "" or spn.description == "" or not Effects.collect(cn).is_empty():
			all_named = false
	_check(all_named, "v6: Mecánico, Infiltrado y Saboteador existen, con descripción y sin mecánica todavía")
	_check(GameContent.find_specialty("granadero") == GameContent.find_specialty("saboteador") and GameContent.find_specialty("municionero") == GameContent.find_specialty("mecanico"), "v6: perfiles antiguos: Zapador → Saboteador, Municionero → Mecánico")
	var orphan := false
	for sk in GameContent.skills():
		if sk.specialty_id != "" and GameContent.find_specialty(sk.specialty_id) == null:
			orphan = true
		if sk.specialty_id in ["granadero", "municionero"]:
			orphan = true
	_check(not orphan, "v6: no quedan habilidades de especialidades retiradas")
	_check(GameContent.skills().size() >= 20 and GameContent.items().size() >= 8, "≥20 habilidades y ≥8 objetos")
	_check(GameContent.find_skill("comando") == null and GameContent.find_skill("piel_dura") != null and GameContent.find_item("granada") != null \
			and GameContent.find_specialty("medico") != null and GameContent.find_weapon("bazuca") != null, "find_* funciona")
	_check(GameContent.find_weapon("no_existe") == null, "find_* devuelve null si no existe")
	var old_item: ItemData = load("res://Resources/Items/chaleco_tactico.tres")
	_check(old_item is ItemData and old_item.slot == ItemData.Slot.ARMADURA and old_item.modifiers.get("health_flat", 0.0) == 25.0,
			"chaleco_tactico.tres reescrito al formato nuevo")
	# Ids únicos dentro de cada tipo
	var dup := false
	for list in [GameContent.weapons(), GameContent.skills(), GameContent.items()]:
		var seen := {}
		for r in list:
			if seen.has(r.id):
				dup = true
			seen[r.id] = true
	_check(not dup, "ids sin duplicados")


func _test_recruit(rng: RandomNumberGenerator) -> void:
	var ok := true
	var names := {}
	for i in 200:
		var c := UnitFactory.make_recruit(rng)
		names[c.unit_name] = true
		var w := c.get_weapon()
		if c.unit_name == "" or c.level != 1 or c.specialty != null:
			ok = false
		if c.base_health < 90.0 or c.base_health > 110.0 or c.base_damage < 0.9 or c.base_damage > 1.1:
			ok = false
		if w == null or not w in UnitFactory.recruit_weapon_options() or c.weapons.size() != 1:
			ok = false
		var p := UnitFactory.recruit_price(c)
		if p < 40 or p > 70:
			ok = false
	_check(ok, "reclutas: nombre, Vida/Daño ±10 %, arma común o rara (variada), precio base 40–70")
	_check(names.size() > 15, "reclutas con nombres variados (%d)" % names.size())
	var c2 := UnitFactory.make_recruit(rng)
	_check(c2.get_specialty_name() == "Recluta" and c2.get_title() == c2.unit_name + " · Recluta", "get_title Recluta")


func _test_stats() -> void:
	# Caso exacto: soldado Nv3, base 100/1.0, fusil (afín), Comando + Piel dura + balas huecas
	var c := _card("fusil_asalto")
	c.level = 3
	c.specialty = GameContent.find_specialty("soldado")
	c.skills.assign([GameContent.find_skill("piel_dura")])
	c.items.assign([GameContent.find_item("balas_huecas")])
	var s := TroopStats.compute(c)
	# vida = (100*(1+0.12*2) + 15) * 1.12 = 155.68 (+12 %/nivel)
	_check(is_equal_approx(s.max_health, (100.0 * (1.0 + TroopStats.LEVEL_HEALTH * 2) + 50.0)), "compute vida exacta (%.3f == %.3f)" % [s.max_health, (100.0 * (1.0 + TroopStats.LEVEL_HEALTH * 2) + 50.0)])
	# daño = 1.0 * (1+0.08*2) * (1 + 0.15 + 0.15) = 1.508 (+8 %/nivel)
	_check(is_equal_approx(s.damage_mult, ((1.0 + TroopStats.LEVEL_DAMAGE * 2) * 1.3)), "compute daño exacto (%.4f == %.4f)" % [s.damage_mult, ((1.0 + TroopStats.LEVEL_DAMAGE * 2) * 1.3)])
	# Entrenamiento: +6 % a vida y daño por rango
	c.training_ranks = 2
	var st := TroopStats.compute(c)
	_check(is_equal_approx(st.max_health, (100.0 * (1.0 + TroopStats.LEVEL_HEALTH * 2) + 50.0) * 1.12) and is_equal_approx(st.damage_mult, ((1.0 + TroopStats.LEVEL_DAMAGE * 2) * 1.3) * 1.12), "entrenamiento +6 %% por rango (vida y daño)")
	c.training_ranks = 0
	_check(s.affinity == true, "afinidad soldado + fusil")
	# v4: precisión = arma + 0.10 afinidad; el Soldado ya no da cadencia (su mecánica es la supresión)
	_check(is_equal_approx(s.accuracy, c.get_weapon().accuracy + 0.10), "precisión con afinidad +0.10 (%.3f)" % s.accuracy)
	_check(is_equal_approx(s.fire_rate, c.get_weapon().fire_rate) and Effects.collect(c).has("supresion"), "soldado: sin bonus de cadencia, con fuego de supresión")
	_check(is_equal_approx(s.move_speed, 90.0) and s.magazine == c.get_weapon().magazine, "movimiento base 90 y cargador del arma (%d)" % s.magazine)
	# Sin afinidad: pistola con soldado
	var c2 := _card("pistola")
	c2.specialty = GameContent.find_specialty("soldado")
	var s2 := TroopStats.compute(c2)
	_check(not s2.affinity and is_equal_approx(s2.damage_mult, 1.0) and is_equal_approx(s2.accuracy, c2.get_weapon().accuracy), "sin afinidad no hay bonus")
	# Armadura/esquiva con tope (v6: el Municionero ya no existe)
	var c3 := _card("pistola")
	c3.items.assign([GameContent.find_item("blindaje_pesado")])
	var s3 := TroopStats.compute(c3)
	_check(is_equal_approx(s3.armor, 0.2) and is_equal_approx(s3.move_speed, 90.0 * c3.get_weapon().move_speed_mult * 0.85), "blindaje: armor 0.2 y movimiento −15 %")
	var c4 := _card("cuchillo")
	_check(TroopStats.compute(c4).magazine == 0, "cargador infinito sigue infinito")
	var c6 := _card("pistola")
	c6.items.assign([GameContent.find_item("balas_incendiarias")])
	var s6 := TroopStats.compute(c6)
	_check(is_equal_approx(s6.burn_dps, 5.0) and is_equal_approx(s6.burn_duration, 3.0), "balas incendiarias: quemadura 5/s 3 s")
	_check(TroopStats.describe(c).size() > 5, "describe devuelve líneas")


func _test_level_up(rng: RandomNumberGenerator) -> void:
	GameStateManager.reset_run()
	var c := UnitFactory.make_recruit(rng)
	_check(c.can_level_up() and c.get_level_up_cost() == 1 and c.get_level_up_cost() == Economy.level_cost(1), "coste Nv1→2 = 1 PM")
	GameStateManager.coins = 500 # las monedas no sirven para subir de nivel
	GameStateManager.command_points = 0
	_check(not LevelUpSystem.begin_level_up(c, rng) and GameStateManager.command_points == 0 and GameStateManager.coins == 500 \
			and c.pending_offers.is_empty(), "sin PM no se puede subir (aunque haya monedas)")
	# v3.2: Nv1→2 ya no da especialidad, solo habilidades
	GameStateManager.command_points = 10
	var c0 := UnitFactory.make_recruit(rng)
	LevelUpSystem.begin_level_up(c0, rng)
	_check(not c0.pending_offers.is_empty() and c0.pending_offers.all(func(o): return o.type != "specialty"), "Nv1→2: ya no hay especialidades (llegan en Nv. %d)" % TroopCard.SPECIALTY_LEVEL)
	c.level = TroopCard.SPECIALTY_LEVEL - 1
	var spec_cost := Economy.level_cost(c.level)
	GameStateManager.command_points = 10
	var got_signal := [false]
	var cb := func(card): got_signal[0] = card == c
	EventBus.level_up_offers_ready.connect(cb)
	var ok := LevelUpSystem.begin_level_up(c, rng)
	EventBus.level_up_offers_ready.disconnect(cb)
	_check(ok and GameStateManager.command_points == 10 - spec_cost and GameStateManager.coins == 500, "begin_level_up cobra %d PM y no toca las monedas" % spec_cost)
	_check(got_signal[0], "emite level_up_offers_ready")
	_check(c.level == TroopCard.SPECIALTY_LEVEL - 1, "begin_level_up aún no sube de nivel")
	_check(c.pending_offers.size() >= 2 and c.pending_offers[0].type == "specialty" and c.pending_offers[1].type == "specialty"
			and c.pending_offers[0].resource != c.pending_offers[1].resource, "Nv4→5: 2 especialidades distintas")
	_check(not c.can_level_up(), "can_level_up false con ofertas pendientes")
	_check(not LevelUpSystem.begin_level_up(c, rng) and GameStateManager.command_points == 10 - spec_cost, "no cobra dos veces con ofertas pendientes")
	var chosen: SpecialtyData = c.pending_offers[1].resource
	var leveled := [false]
	var cb2 := func(card): leveled[0] = card == c
	EventBus.troop_leveled.connect(cb2)
	LevelUpSystem.choose(c, 1)
	EventBus.troop_leveled.disconnect(cb2)
	_check(c.specialty == chosen and c.level == TroopCard.SPECIALTY_LEVEL and c.pending_offers.is_empty(), "choose aplica especialidad y sube a Nv5")
	_check(leveled[0], "emite troop_leveled")
	_check(c.get_specialty_name() == chosen.display_name, "get_specialty_name tras especializar")
	# Hasta Nv10 y luego bloqueado
	var items_before := c.items.size() # v3.1: el recluta puede traer un objeto de serie
	var pm_before := 100000
	GameStateManager.command_points = pm_before
	var expected_cost := 0
	var lv_tbl_sum := 0
	for l in range(TroopCard.SPECIALTY_LEVEL, TroopCard.MAX_LEVEL):
		lv_tbl_sum += Economy.LEVEL_COST[l]
	while c.level < TroopCard.MAX_LEVEL:
		expected_cost += Economy.level_cost(c.level)
		if not LevelUpSystem.begin_level_up(c, rng):
			break
		LevelUpSystem.choose(c, 0)
	_check(c.level == 10, "se puede llegar a Nv10")
	_check(pm_before - GameStateManager.command_points == expected_cost and expected_cost == lv_tbl_sum, "Nv5→10 cuesta la suma de LEVEL_COST (%d PM)" % expected_cost)
	_check(c.items.size() == items_before and c.weapons.size() == 1, "subir de nivel nunca da objetos ni armas (solo habilidades/entrenamiento)")
	_check(not c.can_level_up() and not LevelUpSystem.begin_level_up(c, rng), "can_level_up false en Nv10")
	_check(c.items.size() <= TroopCard.MAX_ITEM_SLOTS, "nunca más de 3 objetos")
	# Arma ofrecida: choose con equip_weapon la equipa
	var c2 := _card("pistola")
	c2.level = 3
	c2.specialty = GameContent.find_specialty("soldado")
	c2.pending_offers = [{"type": "weapon", "resource": GameContent.find_weapon("escopeta")},
			{"type": "skill", "resource": GameContent.find_skill("piel_dura")}]
	LevelUpSystem.choose(c2, 0, true)
	_check(c2.weapons.size() == 2 and c2.get_weapon().id == "escopeta" and c2.level == 4, "choose arma: se añade y se equipa si se pide")
	GameStateManager.reset_run()


func _test_mix(rng: RandomNumberGenerator) -> void:
	var counts := {"skill": 0, "item": 0, "weapon": 0, "specialty": 0, "training": 0}
	var distinct := true
	for i in 500:
		var c := UnitFactory.make_recruit(rng)
		c.level = 2 + (i % 7)
		c.specialty = GameContent.specialties()[i % 5]
		var offers := LevelUpSystem.roll_offers(c, rng)
		if offers.size() < 2 or offers.size() > 3:
			distinct = false
		for a_i in offers.size():
			for b_i in range(a_i + 1, offers.size()):
				if offers[a_i].resource != null and offers[a_i].resource == offers[b_i].resource:
					distinct = false
		for o in offers:
			counts[o.type] += 1
	print("  mezcla de 1000 ofertas: ", counts)
	_check(distinct, "siempre 2 ofertas distintas (3 si sale la mejora extra)")
	_check(counts.skill > 0 and counts.item == 0 and counts.weapon == 0 and counts.specialty == 0, "las subidas posteriores ofrecen solo habilidades (nunca objeto/arma/especialidad)")
	_check(counts.skill > counts.training, "las habilidades son mayoría sobre el entrenamiento")
	# Habilidades de otra especialidad nunca salen
	var bad := false
	for i in 300:
		var c := _card("pistola")
		c.level = 4
		c.specialty = GameContent.find_specialty("medico")
		for o in LevelUpSystem.roll_offers(c, rng):
			if o.type == "skill" and o.resource.specialty_id != "" and o.resource.specialty_id != "medico":
				bad = true
			if o.type == "weapon" or o.type == "item":
				bad = true
	_check(not bad, "no ofrece habilidades de otra especialidad ni armas/objetos")


func _test_items_fit(rng: RandomNumberGenerator) -> void:
	var c := _card("pistola")
	c.level = 4
	c.specialty = GameContent.find_specialty("soldado")
	_check(c.add_item(GameContent.find_item("balas_huecas")), "añade munición")
	_check(not c.can_add_item(GameContent.find_item("balas_incendiarias")), "regla: solo 1 MUNICION")
	_check(c.add_item(GameContent.find_item("chaleco_tactico")), "añade armadura")
	_check(not c.can_add_item(GameContent.find_item("blindaje_pesado")), "regla: solo 1 ARMADURA")
	_check(not c.can_add_item(GameContent.find_item("balas_huecas")), "sin duplicados")
	# Con munición y armadura puestas solo pueden salir objetos de UTILIDAD
	var bad := false
	for i in 300:
		for o in LevelUpSystem.roll_offers(c, rng, 0, true): # ruta de enemigos: conserva las reglas de hueco
			if o.type == "item" and o.resource.slot != ItemData.Slot.UTILIDAD:
				bad = true
	_check(not bad, "(enemigos) no ofrece munición/armadura si ya lleva")
	_check(c.add_item(GameContent.find_item("granada")), "añade utilidad (3/3)")
	_check(not c.can_add_item(GameContent.find_item("botiquin")), "no cabe un 4.º objeto")
	var item_offered := false
	for i in 500:
		for o in LevelUpSystem.roll_offers(c, rng, 0, true) + LevelUpSystem.roll_offers(c, rng):
			if o.type == "item":
				item_offered = true
	_check(not item_offered, "con 3 huecos llenos nunca ofrece objetos (enemigos ni jugador)")


func _test_requires(rng: RandomNumberGenerator) -> void:
	var sangre := GameContent.find_skill("sangre_fria")
	var c := _card("pistola")
	c.level = 4
	c.specialty = GameContent.find_specialty("soldado")
	var seen := false
	for i in 1500:
		for o in LevelUpSystem.roll_offers(c, rng):
			if o.resource == sangre:
				seen = true
	_check(not seen, "requires: sin Ojo certero no sale Sangre fría")
	c.skills.append(GameContent.find_skill("ojo_certero"))
	for i in 1500:
		for o in LevelUpSystem.roll_offers(c, rng):
			if o.resource == sangre:
				seen = true
	_check(seen, "requires: con Ojo certero sí puede salir Sangre fría")
	# Las no acumulables que ya tiene no se repiten; las acumulables sí
	var repeat := false
	c.skills.append(GameContent.find_skill("piel_dura"))
	for i in 1500:
		for o in LevelUpSystem.roll_offers(c, rng):
			if o.resource == GameContent.find_skill("ojo_certero"):
				repeat = true
	_check(not repeat, "no repite habilidades no acumulables")
	_check(not GameContent.skills().any(func(sk): return sk.stackable), "v4.2: ya no hay habilidades acumulables (Comando retirada)")


func _test_remove_item() -> void:
	GameStateManager.reset_run()
	var c := _card("pistola")
	var item := GameContent.find_item("botiquin")
	c.add_item(item)
	var ok := c.remove_item(item)
	_check(ok and c.items.is_empty() and item in GameStateManager.player_bench, "remove_item devuelve el objeto a la reserva")
	_check(GameStateManager.equip_item_from_bench(c, item) and c.has_item("botiquin") and not item in GameStateManager.player_bench,
			"equip_item_from_bench lo equipa y lo saca de la reserva")
	_check(not c.remove_item(GameContent.find_item("granada")), "remove_item de algo que no lleva = false")
	# duplicate_card copia arrays sin compartirlos
	var d := c.duplicate_card()
	d.items.clear()
	d.base_health = 1.0
	_check(c.items.size() == 1 and c.base_health == 100.0 and d.get_weapon() == c.get_weapon(), "duplicate_card es copia profunda segura")
	GameStateManager.reset_run()


func _test_enemies(rng: RandomNumberGenerator) -> void:
	var hp1 := 0.0
	var hp12 := 0.0
	var ok := true
	for i in 40:
		var e1 := UnitFactory.make_enemy(1, false, false, rng)
		var e12 := UnitFactory.make_enemy(12, false, false, rng)
		hp1 += TroopStats.compute(e1).max_health
		hp12 += TroopStats.compute(e12).max_health
		if e1.level != 1 or e12.level != UnitFactory.enemy_level(12) or e12.specialty == null or e12.get_weapon() == null:
			ok = false
		for w in e12.weapons:
			if w.min_round > 12:
				ok = false
		var e3 := UnitFactory.make_enemy(3, false, false, rng)
		for w in e3.weapons:
			if w.min_round > 3:
				ok = false
	_check(ok, "make_enemy: nivel por ronda, especialidad y armas con min_round válido")
	_check(hp12 > hp1 * 1.15, "make_enemy escala con la ronda (vida media %.0f → %.0f)" % [hp1 / 40.0, hp12 / 40.0])
	var b := UnitFactory.make_enemy(60, true, true, rng)
	_check(b.is_boss and b.level == UnitFactory.enemy_level(60, true, true) and b.level == TroopCard.MAX_LEVEL,
			"jefe: is_boss y nivel con tope %d (según UnitFactory.enemy_level)" % TroopCard.MAX_LEVEL)
	var el := UnitFactory.make_enemy(6, true, false, rng)
	_check(el.level == 3, "élite: +1 nivel")


func _test_gsm() -> void:
	GameStateManager.reset_run()
	GameStateManager.coins = 30
	var c := UnitFactory.make_recruit()
	var price := Economy.recruit_price(c)
	var base_price := price - Economy.recruit_extras_surcharge(c) # v3.1: suplemento si trae objeto
	_check(base_price >= Economy.RECRUIT_PRICE_MIN and base_price <= Economy.RECRUIT_PRICE_MAX, "Economy.recruit_price dentro de [MIN, MAX] 💰 (%d)" % price)
	_check(GameStateManager.recruit_troop(c, price) and GameStateManager.coins == 30 - price and c in GameStateManager.player_bench,
			"recruit_troop cobra monedas y añade a la reserva")
	_check(GameStateManager.gold == GameStateManager.coins, "gold sigue siendo alias de coins")
	GameStateManager.coins = 3
	_check(not GameStateManager.recruit_troop(UnitFactory.make_recruit(), Economy.RECRUIT_PRICE_MIN) and GameStateManager.coins == 3, "recruit_troop sin monedas falla")
	GameStateManager.add_coins(4)
	GameStateManager.add_points(2)
	_check(GameStateManager.coins == 7 and GameStateManager.command_points == 2 and GameStateManager.spend_points(2) \
			and not GameStateManager.spend_points(1) and GameStateManager.spend_coins(7) and not GameStateManager.spend_coins(1), "add/spend de monedas y PM")
	GameStateManager.add_item(GameContent.find_item("granada"))
	_check(GameStateManager.get_army_size() == 1 and GameStateManager.get_bench_cards().size() == 1
			and GameStateManager.get_bench_items().size() == 1, "reserva distingue TroopCard / ItemData")
	GameStateManager.shop_offers = [1, 2, 3]
	GameStateManager.advance_stage()
	_check(GameStateManager.shop_offers.is_empty(), "advance_stage limpia shop_offers")
	GameStateManager.shop_offers = [1]
	GameStateManager.reset_run()
	_check(GameStateManager.shop_offers.is_empty() and GameStateManager.player_bench.is_empty(), "reset_run limpia shop_offers")
