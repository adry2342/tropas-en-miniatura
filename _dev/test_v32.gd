extends Node2D
## Pruebas v3.2: objeto/especialidad visibles en las fichas de recluta, especialidad en Nv. 5,
## reclutas de la Intendencia con especialidad, botón 👀 del menú de mejora (y bloqueo),
## jefes más suaves, francotirador más lento, "¡Fallo!" de la escopeta, balas desviadas y fuego amigo.

const TROOP := preload("res://Scenes/Troops/troop.tscn")
const BULLET := preload("res://Scenes/Battle/bullet.tscn")
const SHOTS := "res://_dev/shots/"

var fails := 0
var passes := 0
var rng := RandomNumberGenerator.new()


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("TEST PASS: ", msg)
	else:
		fails += 1
		print("TEST FAIL: ", msg)


func frames(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	get_viewport().get_texture().get_image().save_png(SHOTS + file + ".png")
	print("CAPTURA: ", file)


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	rng.seed = 3202
	await frames(2)
	_test_specialty_rules()
	await _test_recruit_cards()
	await _test_peek_and_block()
	_test_tuning()
	await _test_combat_bullets()
	print("TEST DONE: %d fallos (%d ok)" % [fails, passes])
	get_tree().quit()


func _find_named(n: Node, nm: String) -> Node:
	return n.find_child(nm, true, false)


# ------------------------------------------------------------------ especialidad y reclutas

func _test_specialty_rules() -> void:
	check(TroopCard.SPECIALTY_LEVEL == 5, "la especialidad se elige al subir a Nv. 5")
	var c := UnitFactory.make_recruit(rng)
	var ok := true
	for lv in range(1, TroopCard.SPECIALTY_LEVEL - 1):
		c.level = lv
		for i in 30:
			if LevelUpSystem.roll_offers(c, rng).any(func(o): return o.type == "specialty"):
				ok = false
	check(ok, "de Nv. 1 a Nv. 4 nunca salen especialidades")
	c.level = TroopCard.SPECIALTY_LEVEL - 1
	var offers := LevelUpSystem.roll_offers(c, rng)
	check(offers.size() >= 2 and offers.all(func(o): return o.type == "specialty"), "al subir a Nv. 5 las ofertas son especialidades")
	var c2 := UnitFactory.make_recruit(rng, true)
	c2.specialty = GameContent.specialties()[0]
	c2.level = TroopCard.SPECIALTY_LEVEL - 1
	check(LevelUpSystem.roll_offers(c2, rng).all(func(o): return o.type != "specialty"), "un recluta que ya viene especializado no vuelve a elegir especialidad")
	# Enemigos: siguen especializándose pronto (equilibrio)
	var e := UnitFactory.make_enemy(8, false, false, rng)
	check(e.level >= 2 and e.specialty != null, "los enemigos siguen teniendo especialidad desde Nv. 2 (Nv. %d)" % e.level)
	# Primer recluta: nunca especialidad; Intendencia: a veces
	var first_spec := 0
	for i in 600:
		if UnitFactory.make_recruit(rng).specialty != null:
			first_spec += 1
	check(first_spec == 0, "make_recruit() por defecto (primer recluta) nunca trae especialidad")
	var shop_spec := 0
	var price_ok := true
	for i in 2000:
		var r := UnitFactory.make_recruit(rng, true)
		if r.specialty != null:
			shop_spec += 1
			var base := Economy.recruit_price(r) - Economy.recruit_extras_surcharge(r)
			if Economy.recruit_extras_surcharge(r) < Economy.RECRUIT_SPECIALTY_PRICE or base < Economy.RECRUIT_PRICE_MIN or base > Economy.RECRUIT_PRICE_MAX:
				price_ok = false
	var rate := shop_spec / 2000.0
	check(absf(rate - Economy.RECRUIT_SPECIALTY_CHANCE) < 0.03, "Intendencia: %.1f %% de reclutas vienen especializados (objetivo %d %%)" % [rate * 100.0, roundi(Economy.RECRUIT_SPECIALTY_CHANCE * 100.0)])
	check(price_ok, "un recluta especializado cuesta +%d 💰" % Economy.RECRUIT_SPECIALTY_PRICE)


func _test_recruit_cards() -> void:
	var with_item := UnitFactory.make_recruit(rng)
	with_item.items.clear()
	with_item.add_item(GameContent.find_item("chaleco_tactico"))
	var pc := UiKit.make_recruit_card(with_item, 238)
	add_child(pc)
	await frames(2)
	var il: Label = _find_named(pc, "ItemLine")
	check(il != null and il.text.contains(GameContent.find_item("chaleco_tactico").display_name), "la ficha muestra el objeto que trae (%s)" % (il.text if il else "—"))
	check(il != null and il.tooltip_text.contains(GameContent.find_item("chaleco_tactico").description) and il.mouse_filter != Control.MOUSE_FILTER_IGNORE, "el objeto tiene tooltip con su descripción")
	check(_find_named(pc, "NoItemLine") == null, "con objeto no pone 'Sin objeto'")
	pc.queue_free()
	var bare := UnitFactory.make_recruit(rng)
	bare.items.clear()
	var pc2 := UiKit.make_recruit_card(bare, 238)
	add_child(pc2)
	await frames(2)
	check(_find_named(pc2, "NoItemLine") != null and _find_named(pc2, "ItemLine") == null, "sin objeto la ficha lo dice: '🎒 Sin objeto'")
	check(_find_named(pc2, "SpecialtyLine") == null, "sin especialidad no hay línea de especialidad")
	pc2.queue_free()
	var spec := UnitFactory.make_recruit(rng, true)
	spec.specialty = GameContent.find_specialty("francotirador")
	var pc3 := UiKit.make_recruit_card(spec, 238)
	add_child(pc3)
	await frames(2)
	var sl: Label = _find_named(pc3, "SpecialtyLine")
	check(sl != null and sl.text.contains("Francotirador") and sl.tooltip_text.contains(spec.specialty.passive_name), "un recluta especializado lo muestra con tooltip")
	pc3.queue_free()

	# Pantalla de primer recluta: las 3 fichas dicen si traen objeto; ninguna trae especialidad
	GameStateManager.reset_run()
	var sel = load("res://Scenes/UI/troop_selection_screen.tscn").instantiate()
	sel.change_scene_on_start = false
	add_child(sel)
	await frames(3)
	var never_spec := true
	var all_lines := true
	for k in 20:
		sel.generate_offers()
		await get_tree().process_frame
		for i in sel.offers.size():
			if sel.offers[i].specialty != null:
				never_spec = false
			var p: Node = sel._panels[i]
			var has_line: bool = _find_named(p, "ItemLine") != null or _find_named(p, "NoItemLine") != null
			if not has_line:
				all_lines = false
	check(never_spec, "el primer recluta nunca viene con especialidad (60 ofertas)")
	check(all_lines, "cada ficha del primer recluta indica su objeto o 'Sin objeto'")
	# Forzar un ejemplo con objeto para la captura
	for k in 40:
		if sel.offers.any(func(o): return not o.items.is_empty()):
			break
		sel.generate_offers()
		await get_tree().process_frame
	await wait(0.2)
	await shot("v32_primer_recluta")
	sel.queue_free()
	await frames(2)


# ------------------------------------------------------------------ menú de mejora: botón 👀 y bloqueo

func _test_peek_and_block() -> void:
	GameStateManager.reset_run()
	GameStateManager.current_stage = 3
	GameStateManager.current_node_type = "Batalla"
	var c := UnitFactory.make_recruit(rng)
	c.level = TroopCard.SPECIALTY_LEVEL - 1
	GameStateManager.add_troop_to_army(c)
	GameStateManager.add_points(20, "test")
	var bt = load("res://Scenes/Battle/battle.tscn").instantiate()
	add_child(bt)
	await wait(0.5)
	var detail = null
	var prep = null
	for n in bt.get_children():
		var sc = n.get_script()
		if sc and sc.resource_path.ends_with("troop_detail_panel.gd"):
			detail = n
		if "start_button" in n:
			prep = n
	check(detail != null and prep != null, "batalla con submenú y botón de combatir")
	if detail == null or prep == null:
		return
	# Desplegar una tropa para que COMBATIR esté activo
	var t = TROOP.instantiate()
	t.team = t.Team.PLAYER
	t.setup(UnitFactory.make_recruit(rng))
	bt.add_child(t)
	t.global_position = bt.get_grid().grid_cells[12]
	await wait(0.2)
	detail.open_card(c)
	await frames(2)
	detail._on_level_up_pressed()
	await wait(0.7)
	var modal = detail.level_up_choice
	check(modal.is_open() and c.pending_offers.all(func(o): return o.type == "specialty"), "subir a Nv. 5 abre la elección de especialidad")
	check(modal._eye_button.visible and modal._eye_button.focus_mode == Control.FOCUS_NONE, "hay un botón 👀 visible (sin foco de teclado)")
	await shot("v32_eleccion")
	# Intentar combatir / abrir la Intendencia con la elección abierta: no pasa nada
	var started := [false]
	var cb := func(): started[0] = true
	EventBus.battle_fight_started.connect(cb)
	prep.start_button.disabled = false
	prep._on_start_button_pressed()
	var shop_req := [false]
	var cb2 := func(_t): shop_req[0] = true
	EventBus.shop_requested.connect(cb2)
	prep._on_shop_pressed()
	await frames(2)
	check(not started[0], "con la elección abierta no se puede iniciar el combate")
	check(not shop_req[0], "con la elección abierta no se abre la Intendencia")
	# Modo 👀
	modal.set_peek(true)
	await frames(2)
	check(modal.is_peeking() and not modal._center.visible and not modal._dim.visible and modal._peek_blocker.visible, "👀: las cartas se ocultan y una capa invisible bloquea los clics")
	check(not modal.choose_offer(0) and c.pending_offers.size() >= 2, "👀: mientras se mira no se puede elegir")
	prep._on_start_button_pressed()
	await frames(2)
	check(not started[0] and GameStateManager.ui_blocking, "👀: tampoco se puede combatir; ui_blocking sigue activo")
	# Clic real sobre el botón COMBATIR mientras se mira: la capa lo absorbe
	var sb_pos: Vector2 = prep.start_button.get_global_rect().get_center()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = sb_pos
	ev.global_position = sb_pos
	get_viewport().push_input(ev)
	var ev2 := ev.duplicate()
	ev2.pressed = false
	get_viewport().push_input(ev2)
	await frames(3)
	check(not started[0], "👀: un clic en COMBATIR no hace nada")
	await shot("v32_ojo")
	modal.set_peek(false)
	await frames(2)
	check(not modal.is_peeking() and modal._center.visible and modal._dim.visible and not modal._peek_blocker.visible, "al soltar vuelve el menú de cartas")
	check(modal.choose_offer(0), "se puede elegir tras volver")
	await wait(1.0)
	check(c.level == TroopCard.SPECIALTY_LEVEL and c.specialty != null and not modal.is_open(), "elegida la especialidad en Nv. 5")
	EventBus.battle_fight_started.disconnect(cb)
	EventBus.shop_requested.disconnect(cb2)
	detail.close()
	await frames(2)
	# Intendencia: ficha de recluta especializado
	GameStateManager.add_coins(200, "test")
	GameStateManager.shop_offers.clear()
	var r1 := UnitFactory.make_recruit(rng, true)
	r1.specialty = GameContent.find_specialty("medico")
	r1.items.clear()
	r1.add_item(GameContent.find_item("botiquin"))
	var r2 := UnitFactory.make_recruit(rng, true)
	r2.specialty = null
	r2.items.clear()
	var r3 := UnitFactory.make_recruit(rng, true)
	r3.specialty = null
	GameStateManager.shop_offers.assign([r1, r2, r3])
	EventBus.shop_requested.emit("reclutas")
	await wait(0.5)
	var shop = null
	for n in bt.get_children():
		var sc = n.get_script()
		if sc and sc.resource_path.ends_with("recruit_shop.gd"):
			shop = n
	if shop:
		shop.open("reclutas")
		await wait(0.4)
		var btn: Button = shop._buy_buttons.get(r1)
		check(btn != null and btn.tooltip_text.contains("%d" % Economy.recruit_extras_surcharge(r1)), "el botón de compra explica el recargo (%s)" % (btn.tooltip_text if btn else "—"))
		await shot("v32_intendencia_reclutas")
		shop.close()
	bt.queue_free()
	await frames(3)


# ------------------------------------------------------------------ ajustes

func _test_tuning() -> void:
	var sniper := GameContent.find_weapon("rifle_francotirador")
	check(sniper.fire_rate <= 0.3 + 0.001, "francotirador más lento: %.2f disparos/s" % sniper.fire_rate)
	var c := UnitFactory.make_recruit(rng)
	c.items.clear()
	c.weapons.assign([sniper])
	check(TroopStats.compute(c).fire_rate <= 0.31, "sin habilidades ni objetos dispara a ≤0.3/s")
	check(Economy.subboss_hp(10) < 480.0 and Economy.subboss_hp(20) < 950.0, "Jefe de Sector más suave (R10 %d · R20 %d)" % [Economy.subboss_hp(10), Economy.subboss_hp(20)])
	var battle_script = load("res://Scripts/Battle/battle.gd")
	check(battle_script.BOSS_HP_MULT < 2.6 and battle_script.BOSS_DMG_MULT < 2.0, "Jefe Final más suave (vida ×%.1f, daño ×%.1f)" % [battle_script.BOSS_HP_MULT, battle_script.BOSS_DMG_MULT])


# ------------------------------------------------------------------ balas

func _spawn(weapon_id: String, team: int, pos: Vector2, hp: float = 100.0) -> Node:
	var c := UnitFactory.make_recruit(rng)
	c.items.clear()
	c.weapons.assign([GameContent.find_weapon(weapon_id)])
	c.base_health = hp
	var t = TROOP.instantiate()
	t.team = team
	t.setup(c)
	t.position = pos
	add_child(t)
	t.ai_enabled = false
	t.force_lethal = 0
	t.force_dodge = 0
	return t


func _test_combat_bullets() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.22, 0.3, 0.2)
	bg.size = Vector2(1400, 800)
	bg.z_index = -50
	add_child(bg)
	# Escopeta: si el perdigón central acierta y los de los lados fallan, NO sale "¡Fallo!"
	var sg = _spawn("escopeta", 0, Vector2(300, 300))
	var dummy = _spawn("pistola", 1, Vector2(360, 300), 5000.0)
	EventBus.battle_fight_started.emit()
	await frames(2)
	sg.target = dummy
	sg.force_hit_pattern = [false, false, true, false, false]
	sg._miss_text_cd = 0.0
	sg.attack()
	check(sg._miss_text_cd <= 0.0, "escopeta con el perdigón central dentro: no pone '¡Fallo!'")
	sg.attack_cooldown = 0.0
	sg.force_hit_pattern = [false, false, false, false, false]
	sg._miss_text_cd = 0.0
	sg.attack()
	check(sg._miss_text_cd > 0.0, "escopeta sin ningún perdigón dentro: sí pone '¡Fallo!'")
	sg.force_hit_pattern = []
	await wait(0.6)
	for ch in get_children():
		if ch.is_in_group("troops"):
			ch.queue_free()
	await frames(3)

	# Bala desviada que se cruza con un ENEMIGO: le da y cuenta como acierto
	var shooter = _spawn("fusil_asalto", 0, Vector2(200, 400))
	var other_enemy = _spawn("pistola", 1, Vector2(400, 400), 5000.0)
	await frames(2)
	shooter.misses = 1
	shooter.hits = 0
	var hp0: float = other_enemy.health
	_fire_stray(shooter, Vector2(600, 400), WeaponData.Projectile.BALA)
	await wait(0.6)
	check(other_enemy.health < hp0, "bala desviada que se cruza con otro enemigo le hace daño (%d → %d)" % [hp0, other_enemy.health])
	check(shooter.hits == 1 and shooter.misses == 0 and shooter.stray_hits == 1, "y cuenta como acierto (aciertos %d, fallos %d)" % [shooter.hits, shooter.misses])

	# Bala desviada que se cruza con un COMPAÑERO: fuego amigo
	var ally = _spawn("pistola", 0, Vector2(300, 520), 5000.0)
	await frames(2)
	var ahp: float = ally.health
	_fire_stray(shooter, Vector2(400, 640), WeaponData.Projectile.BALA)
	await wait(0.6)
	check(ally.health < ahp and shooter.friendly_hits == 1, "bala desviada contra un compañero: fuego amigo (%d → %d)" % [ahp, ally.health])
	await shot("v32_fuego_amigo")

	# El tirador nunca se da a sí mismo
	var shp: float = shooter.health
	_fire_stray(shooter, Vector2(100, 400), WeaponData.Projectile.BALA)
	await wait(0.5)
	check(is_equal_approx(shooter.health, shp), "una bala nunca daña a quien la dispara")

	# Explosivos y llamas NO hacen fuego amigo
	var ahp2: float = ally.health
	var g = _fire_stray(shooter, ally.global_position, WeaponData.Projectile.GRANADA)
	g.aoe_radius = 60.0
	await wait(1.2)
	check(is_equal_approx(ally.health, ahp2), "una granada que cae sobre un compañero no le daña")
	_fire_stray(shooter, ally.global_position + Vector2(40, 40), WeaponData.Projectile.LLAMA)
	await wait(0.8)
	check(is_equal_approx(ally.health, ahp2), "las llamas desviadas no hacen fuego amigo")

	# Bala que acierta: va a su objetivo y no hiere a un compañero que esté cerca del camino
	var ahp3: float = ally.health
	var b = BULLET.instantiate()
	b.kind = WeaponData.Projectile.BALA
	b.family = WeaponData.Family.AUTOMATICA
	b.shooter_team = 0
	b.shooter = shooter
	b.info = {"damage": 10.0, "attacker": shooter}
	b.target = other_enemy
	b.target_pos = other_enemy.global_position
	b.position = shooter.global_position
	add_child(b)
	await wait(0.6)
	check(is_equal_approx(ally.health, ahp3), "las balas que aciertan solo dañan a su objetivo")
	EventBus.battle_fight_started.emit()


func _fire_stray(shooter: Node, to: Vector2, kind: int) -> Node:
	var b = BULLET.instantiate()
	b.kind = kind
	b.family = WeaponData.Family.AUTOMATICA
	b.speed = 900.0 if kind == WeaponData.Projectile.BALA else 400.0
	b.shooter_team = shooter.team
	b.shooter = shooter
	b.info = {"damage": 12.0, "crit": false, "attacker": shooter}
	b.is_miss = true
	b.aoe_radius = 50.0
	b.target_pos = to
	b.position = shooter.global_position + shooter.global_position.direction_to(to) * 14.0
	add_child(b)
	return b
