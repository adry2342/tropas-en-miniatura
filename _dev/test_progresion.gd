extends Node
## Tests de progresión v3: PM, ofertas de habilidades/entrenamiento, estadísticas, enemigos y modal.

var _fails: Array[String] = []
var _passes := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
		print("TEST PASS: ", name)
	else:
		_fails.append(name)
		print("TEST FAIL: ", name)


func _card(weapon_id: String = "pistola") -> TroopCard:
	var c := TroopCard.new()
	c.unit_name = "Prueba"
	c.weapons.assign([GameContent.find_weapon(weapon_id)])
	return c


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	await get_tree().process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	_test_cost()
	_test_offers(rng)
	_test_rarity(rng)
	_test_training_fallback(rng)
	_test_to_level_10(rng)
	_test_stats()
	_test_enemies(rng)
	await _test_modal()
	print("TEST DONE: %d fallos (%d ok)" % [_fails.size(), _passes])
	for f in _fails:
		print("  FALLO: ", f)
	GameStateManager.reset_run()
	get_tree().quit()


func _test_cost() -> void:
	var gsm := GameStateManager
	gsm.reset_run()
	var c := _card()
	var table: Array = Economy.LEVEL_COST
	var ok := true
	for lv in range(1, 10):
		c.level = lv
		if c.get_level_up_cost() != table[lv]:
			ok = false
	c.level = 10
	_check(ok and c.get_level_up_cost() == 0, "coste en PM según tabla (Nv.10 = 0)")
	c.level = TroopCard.SPECIALTY_LEVEL - 1 # v3.2: especialidad en Nv. 5
	gsm.command_points = 0
	_check(not LevelUpSystem.begin_level_up(c) and c.pending_offers.is_empty(), "sin PM no sube")
	gsm.command_points = Economy.level_cost(c.level)
	_check(LevelUpSystem.begin_level_up(c) and gsm.command_points == 0, "con PM cobra el coste")
	_check(c.pending_offers.size() >= 2 and c.pending_offers.all(func(o): return o.type == "specialty"),
			"Nv.5 ofrece 2 especialidades")
	gsm.command_points = 5
	_check(not LevelUpSystem.begin_level_up(c) and gsm.command_points == 5, "no cobra dos veces con ofertas pendientes")
	LevelUpSystem.choose(c, 0)
	_check(c.level == TroopCard.SPECIALTY_LEVEL and c.specialty != null, "elegir sube de nivel y da especialidad")
	gsm.command_points = 0
	gsm.reset_run()


func _test_offers(rng: RandomNumberGenerator) -> void:
	var c := _card()
	c.level = 2
	c.specialty = GameContent.specialties()[0]
	var ok := true
	var distinct := true
	for i in 500:
		c.level = 2 + (i % 7)
		var offers := LevelUpSystem.roll_offers(c, rng)
		if offers.size() < 2 or offers.size() > 3: # 3 = mejora extra por suerte (v3.1)
			ok = false
		for o in offers:
			if o.type == "skill":
				if not (o.resource is SkillData and LevelUpSystem._skill_ok(c, o.resource)):
					ok = false
			elif o.type != "training":
				ok = false
		if offers.size() == 2 and offers[0].resource != null and offers[0].resource == offers[1].resource:
			distinct = false
	_check(ok, "500 tiradas: nunca item/weapon; solo skills válidas o training")
	_check(distinct, "las 2 habilidades ofertadas son distintas")


func _rare_share(rng: RandomNumberGenerator, level_from: int, n: int) -> float:
	var c := _card()
	c.specialty = GameContent.specialties()[0]
	c.level = level_from
	var rare := 0
	var total := 0
	for i in n:
		for o in LevelUpSystem.roll_offers(c, rng):
			if o.type == "skill":
				total += 1
				if o.resource.rarity >= 2:
					rare += 1
	return float(rare) / maxf(1.0, total)


func _test_rarity(rng: RandomNumberGenerator) -> void:
	var low := _rare_share(rng, 2, 2000)  # sube a Nv.3
	var high := _rare_share(rng, 7, 2000) # sube a Nv.8
	print("  raras+ Nv.3: %.3f  Nv.8: %.3f" % [low, high])
	_check(high > low, "Nv.8 da más habilidades raras+ que Nv.3 (2000 tiradas)")


func _test_training_fallback(rng: RandomNumberGenerator) -> void:
	var c := _card()
	c.level = 3
	c.specialty = GameContent.specialties()[0]
	# Agotar habilidades: añadir todas las válidas no apilables
	for s in GameContent.skills():
		if LevelUpSystem._skill_ok(c, s) and not s.stackable:
			c.skills.append(s)
	var offers := LevelUpSystem.roll_offers(c, rng)
	var ok := offers.size() >= 1 # v4.2: sin Comando (acumulable) puede quedar solo la carta de entrenamiento
	var trainings := 0
	for o in offers:
		if o.type == "training":
			trainings += 1
		elif o.type != "skill":
			ok = false
	_check(ok and trainings >= 1, "training cuando se agotan las habilidades (%d training)" % trainings)
	var before := c.training_ranks
	LevelUpSystem.apply_offer(c, {"type": "training", "resource": null})
	_check(c.training_ranks == before + 1, "apply_offer training suma un rango")


func _test_to_level_10(rng: RandomNumberGenerator) -> void:
	var gsm := GameStateManager
	gsm.reset_run()
	var c := _card()
	var spent := 0
	var guard := 0
	while c.level < TroopCard.MAX_LEVEL and guard < 20:
		guard += 1
		var cost := c.get_level_up_cost()
		gsm.command_points = cost
		if not LevelUpSystem.begin_level_up(c, rng):
			break
		spent += cost
		LevelUpSystem.choose(c, rng.randi_range(0, c.pending_offers.size() - 1))
	_check(c.level == 10 and c.specialty != null, "tropa llega a Nv.10 con especialidad")
	_check(c.skills.size() + c.training_ranks == 8, "Nv.10 con 8 mejoras (habilidades+entrenamiento = %d)" % (c.skills.size() + c.training_ranks))
	var expected_pm := 0
	for l in range(1, TroopCard.MAX_LEVEL):
		expected_pm += Economy.LEVEL_COST[l]
	_check(spent == expected_pm, "PM totales gastados hasta Nv.10 = %d (%d)" % [expected_pm, spent])
	gsm.command_points = 10
	_check(not LevelUpSystem.begin_level_up(c) and gsm.command_points == 10, "Nv.10 no sube más ni cobra")
	gsm.reset_run()


func _test_stats() -> void:
	var c := _card()
	var s1 := TroopStats.compute(c)
	c.level = 6
	var s6 := TroopStats.compute(c)
	_check(is_equal_approx(s6.max_health / s1.max_health, 1.0 + TroopStats.LEVEL_HEALTH * 5), "vida +%d %% por nivel" % roundi(TroopStats.LEVEL_HEALTH * 100.0))
	_check(is_equal_approx(s6.damage_mult / s1.damage_mult, 1.0 + TroopStats.LEVEL_DAMAGE * 5), "daño +%d %% por nivel" % roundi(TroopStats.LEVEL_DAMAGE * 100.0))
	c.level = 1
	c.training_ranks = 2
	var st := TroopStats.compute(c)
	_check(is_equal_approx(st.max_health / s1.max_health, 1.12) and is_equal_approx(st.damage_mult / s1.damage_mult, 1.12),
			"training +6 % por rango a vida y daño")
	_check(c.duplicate_card().training_ranks == 2, "duplicate_card copia training_ranks")


func _test_enemies(rng: RandomNumberGenerator) -> void:
	var with_extra := 0
	var no_training := true
	for i in 50:
		var e := UnitFactory.make_enemy(12, false, false, rng)
		if e.items.size() > 0 or e.weapons.size() > 1:
			with_extra += 1
		if e.training_ranks > 0:
			no_training = false
	_check(with_extra > 0, "enemigos ronda 12 siguen recibiendo objetos/armas (%d/50)" % with_extra)
	_check(no_training, "enemigos no reciben training")


func _test_modal() -> void:
	var modal: CanvasLayer = load("res://Scripts/UI/level_up_choice.gd").new()
	add_child(modal)
	await get_tree().process_frame
	var c := _card()
	c.level = 4
	c.specialty = GameContent.specialties()[0]
	c.pending_offers.append({"type": "training", "resource": null})
	c.pending_offers.append({"type": "skill", "resource": GameContent.skills()[0]})
	modal.open(c)
	await get_tree().create_timer(1.0).timeout
	_check(modal.is_open(), "modal abre con oferta training sin errores")
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_dev/shots/prog_training.png")
	_check(modal.choose_offer(0) and c.training_ranks == 1 and c.level == 5, "elegir training desde el modal sube nivel y rango")
	await get_tree().create_timer(1.0).timeout
	modal.queue_free()
