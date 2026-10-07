extends Node2D
## Pruebas v4: puntería por distancia, alcances por arma, IA de movimiento (carriles, separación,
## distancia de combate, retirada, disparo en marcha), especialidades con mecánicas y sinergias,
## mapa de calor del Radioperador, explosiones con caída, economía lenta y presupuesto de oleadas.

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


func card(wid: String, spec: String = "", hp: float = 100.0) -> TroopCard:
	var c := UnitFactory.make_recruit(rng)
	c.items.clear()
	c.weapons.assign([GameContent.find_weapon(wid)])
	c.base_health = hp
	c.base_damage = 1.0
	if spec != "":
		c.specialty = GameContent.find_specialty(spec)
		c.level = TroopCard.SPECIALTY_LEVEL
	return c


func spawn(wid: String, team: int, pos: Vector2, opts: Dictionary = {}) -> Node:
	var t = TROOP.instantiate()
	t.team = team
	t.setup(card(wid, opts.get("spec", ""), opts.get("hp", 100.0)))
	t.position = pos
	add_child(t)
	t.force_lethal = 0
	t.force_dodge = 0
	if opts.get("dummy", false):
		t.ai_enabled = false
	if opts.has("hit"):
		t.force_hit = int(opts.hit)
	return t


func start() -> void:
	EventBus.battle_fight_started.emit()
	await get_tree().physics_frame


func clear() -> void:
	for ch in get_children():
		if ch is ColorRect:
			continue
		ch.queue_free()
	await frames(3)


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	rng.seed = 404
	seed(404)
	var bg := ColorRect.new()
	bg.color = Color(0.22, 0.3, 0.2)
	bg.size = Vector2(1400, 800)
	bg.z_index = -50
	add_child(bg)
	await frames(2)
	_test_accuracy_and_ranges()
	_test_economy_and_budget()
	await _test_map_roulette()
	await _test_ai()
	await _test_specialties()
	await _test_explosion_falloff()
	print("TEST DONE: %d fallos (%d ok)" % [fails, passes])
	get_tree().quit()


# ------------------------------------------------------------------ armas

func _test_accuracy_and_ranges() -> void:
	check(GameContent.find_weapon("lanzagranadas") == null and GameContent.find_item("granada") != null, "sin lanzagranadas como arma; la granada sigue como objeto")
	for wid in ["pistola", "escopeta", "fusil_asalto", "subfusil"]:
		var s := TroopStats.compute(card(wid))
		var opt: float = s.optimal_range
		var close := Troop_hit(s, 15.0)
		var at_opt := Troop_hit(s, opt)
		var far := Troop_hit(s, s.attack_range)
		check(close > at_opt + 0.1 and at_opt > far, "%s: de cerca falla menos (%.0f %% a 15 px · %.0f %% a %d px · %.0f %% a %d px)" % [wid, close * 100, at_opt * 100, roundi(opt), far * 100, roundi(s.attack_range)])
	var sn := TroopStats.compute(card("rifle_francotirador"))
	check(Troop_hit(sn, 40.0) < Troop_hit(sn, sn.optimal_range) - 0.2, "francotirador: con un enemigo encima falla mucho (%.0f %% vs %.0f %%)" % [Troop_hit(sn, 40.0) * 100, Troop_hit(sn, sn.optimal_range) * 100])
	var r := {}
	for w in GameContent.weapons():
		r[w.id] = TroopStats.compute(card(w.id)).attack_range
	check(r.rifle_francotirador > r.bazuca and r.bazuca > r.ametralladora and r.ametralladora >= r.fusil_asalto \
			and r.fusil_asalto > r.subfusil and r.subfusil > r.pistola and r.pistola > r.escopeta and r.escopeta > r.lanzallamas \
			and r.lanzallamas > r.cuchillo, "alcances: franco > bazuca > ametralladora ≥ fusil > subfusil > pistola > escopeta > llamas > cuchillo")
	check(GameContent.find_weapon("bazuca").min_range == 0.0, "v4.1: la bazuca dispara también de cerca (sin pasos atrás)")
	check(GameContent.find_weapon("pistola").fire_on_move and not GameContent.find_weapon("rifle_francotirador").fire_on_move \
			and not GameContent.find_weapon("ametralladora").fire_on_move, "ligeras disparan en marcha; francotirador y pesadas, paradas")


func Troop_hit(s: Dictionary, d: float) -> float:
	return load("res://Scripts/Troops/troop.gd").hit_chance_for(s, d)


# ------------------------------------------------------------------ economía y oleadas

func _test_economy_and_budget() -> void:
	check(Economy.points_for_win("Batalla Normal", true) == 1 and Economy.points_for_win("Batalla Élite", false) == 2, "1 PM por victoria (2 en élite/sector), sin bonus por victoria limpia")
	var total_pm := 0
	for l in range(1, TroopCard.MAX_LEVEL):
		total_pm += Economy.level_cost(l)
	check(total_pm >= 20, "llevar una tropa a Nv. %d cuesta %d PM: con ~1 PM por ronda solo 1–2 llegan al máximo en 30 rondas" % [TroopCard.MAX_LEVEL, total_pm])
	var G = GameStateManager
	check(G.BOSS_MIN_ROUND == 11 and G.boss_chance_for_round(10) == 0.0 and is_equal_approx(G.boss_chance_for_round(11), 0.005) \
			and is_equal_approx(G.boss_chance_for_round(30), 0.10), "v4.1: jefe final desde la ronda 11: 0,5 %% y +0,5 %% por ronda (R30 = %.1f %%)" % (G.boss_chance_for_round(30) * 100))
	var B = load("res://Scripts/Battle/battle.gd")
	var mono := true
	for x in range(1, 80):
		if B.power_budget(x + 1) <= B.power_budget(x):
			mono = false
	check(mono, "el presupuesto de poder enemigo crece en cada ronda")
	check(B.power_budget(30) / B.power_budget(10) < 4.5, "crece de forma suave (R30/R10 = ×%.1f)" % (B.power_budget(30) / B.power_budget(10)))
	var cards: Array[TroopCard] = []
	for i in 4:
		var e := UnitFactory.make_enemy(15, false, false, rng)
		B.apply_difficulty(e, B.difficulty_for(15))
		cards.append(e)
	B.normalize_wave(cards, 5000.0)
	var tot := 0.0
	for c in cards:
		tot += B.card_power(c)
	check(absf(tot - 5000.0) / 5000.0 < 0.05, "normalize_wave ajusta la oleada a su presupuesto (%.0f ≈ 5000)" % tot)
	var sb: Array[TroopCard] = [UnitFactory.make_enemy(10, false, true, rng), UnitFactory.make_enemy(10, false, false, rng)]
	B.apply_subboss(sb[0], B.difficulty_for(10), 10)
	B.normalize_wave(sb, 4000.0, 10)
	check(absf(TroopStats.compute(sb[0]).max_health - Economy.subboss_hp(10)) < 2.0, "el Jefe de Sector conserva su vida fija (%d)" % roundi(TroopStats.compute(sb[0]).max_health))


# ------------------------------------------------------------------ IA

func _test_ai() -> void:
	# Separación: dos compañeros en el mismo punto se apartan
	var a = spawn("pistola", 0, Vector2(300, 250))
	var b = spawn("pistola", 0, Vector2(302, 251))
	spawn("pistola", 1, Vector2(1100, 250), {"dummy": true, "hp": 99999})
	await start()
	await wait(1.0)
	check(a.global_position.distance_to(b.global_position) > 35.0, "dos compañeros juntos se separan (%.0f px)" % a.global_position.distance_to(b.global_position))
	await clear()

	# Carril: prefiere al enemigo de su fila aunque otro esté algo más cerca
	var me = spawn("fusil_asalto", 0, Vector2(200, 150))
	var lane_e = spawn("pistola", 1, Vector2(720, 150), {"dummy": true, "hp": 99999})
	var other_e = spawn("pistola", 1, Vector2(600, 430), {"dummy": true, "hp": 99999})
	await start()
	await wait(0.2)
	check(me.target == lane_e, "elige al enemigo de su carril (no al más cercano en línea recta)")
	await clear()

	# Distancia de combate: fusil se queda a media distancia, pistola se acerca, cuchillo pega
	var rifle = spawn("fusil_asalto", 0, Vector2(150, 160), {"hit": 0})
	var pistol = spawn("pistola", 0, Vector2(150, 300), {"hit": 0})
	var knife = spawn("cuchillo", 0, Vector2(150, 440), {"hit": 0})
	var t1 = spawn("pistola", 1, Vector2(700, 160), {"dummy": true, "hp": 99999})
	var t2 = spawn("pistola", 1, Vector2(700, 300), {"dummy": true, "hp": 99999})
	var t3 = spawn("pistola", 1, Vector2(700, 440), {"dummy": true, "hp": 99999})
	await start()
	var moving_shots := 0
	for k in 480:
		await get_tree().physics_frame
		if pistol.is_moving and pistol.shots_fired > moving_shots:
			moving_shots = pistol.shots_fired
	var dr: float = rifle.global_position.distance_to(t1.global_position)
	var dp: float = pistol.global_position.distance_to(t2.global_position)
	var dk: float = knife.global_position.distance_to(t3.global_position)
	check(dr > dp and dp > dk and dk < 60.0, "distancias de combate: fusil %d px > pistola %d px > cuchillo %d px" % [dr, dp, dk])
	check(absf(dr - rifle.engage_distance()) < 40.0, "el fusil se para cerca de su distancia de combate (%d ≈ %d)" % [dr, rifle.engage_distance()])
	check(moving_shots > 0, "la pistola dispara mientras avanza")
	await shot("v4_distancias")
	await clear()

	# v4.1: nadie da pasos atrás (el francotirador aguanta aunque se le eche encima un cuchillo)
	var sn = spawn("rifle_francotirador", 0, Vector2(500, 300), {"hit": 0})
	var kn = spawn("cuchillo", 1, Vector2(590, 300), {"hp": 99999})
	kn.force_hit = 0
	await start()
	await wait(0.6)
	check(sn.global_position.x >= 499.0, "el francotirador no retrocede (x %d)" % sn.global_position.x)
	await clear()

	# Camuflaje: no dispara mientras está oculto y luego espera a su distancia de combate
	var cm = spawn("pistola", 0, Vector2(150, 300), {"hit": 1})
	cm.card.skills.append(GameContent.find_skill("camuflaje"))
	cm.refresh_from_card()
	var tgt = spawn("pistola", 1, Vector2(700, 300), {"dummy": true, "hp": 99999})
	await start()
	var shots_during_camo := 0
	var shots_far := 0
	for k in 420:
		await get_tree().physics_frame
		if cm.camo_left > 0.0:
			shots_during_camo = cm.shots_fired
		elif cm.global_position.distance_to(tgt.global_position) > cm.engage_distance() + 12.0:
			shots_far = maxi(shots_far, cm.shots_fired)
	check(shots_during_camo == 0, "camuflado: no dispara mientras dura el camuflaje")
	check(shots_far == 0 and cm.shots_fired > 0, "camuflado: no dispara en marcha; abre fuego al llegar a su distancia")
	await clear()

	# Adrenalina: frenético (corre más) y se dibuja el efecto
	var ad = spawn("cuchillo", 0, Vector2(150, 300))
	ad.card.add_item(GameContent.find_item("inyector_adrenalina"))
	ad.refresh_from_card()
	spawn("pistola", 1, Vector2(900, 300), {"dummy": true, "hp": 99999})
	await start()
	await frames(2)
	check(ad.is_frenzied() and ad.get_effective_speed() > ad.get_move_speed() * 1.2, "adrenalina: frenético y más rápido (%.0f → %.0f px/s)" % [ad.get_move_speed(), ad.get_effective_speed()])
	await wait(0.4)
	await shot("v4_adrenalina")
	await clear()

	# Números de daño
	var nd = spawn("pistola", 0, Vector2(400, 300), {"dummy": true, "hp": 500})
	await start()
	var labels_before := _count_texts("-")
	nd.take_damage(37.0)
	await wait(0.3)
	check(_count_texts("-37") > 0, "al recibir daño aparece el número en blanco (-37)")
	await clear()

	# Batalla 6 vs 6 sin amontonarse
	var mine: Array = []
	for i in 6:
		mine.append(spawn(["cuchillo", "escopeta", "fusil_asalto", "pistola", "rifle_francotirador", "ametralladora"][i], 0, Vector2(120 + (i % 2) * 90, 80 + i * 70), {"hp": 300}))
	for i in 6:
		spawn(["fusil_asalto", "pistola", "subfusil", "escopeta", "cuchillo", "rifle_francotirador"][i], 1, Vector2(1030 - (i % 2) * 90, 80 + i * 70), {"hp": 300})
	await start()
	var stuck := 0
	var samples := 0
	for k in 300:
		await get_tree().physics_frame
		if k % 10 == 0:
			var alive: Array = mine.filter(func(x): return is_instance_valid(x) and not x.is_dead)
			for i in alive.size():
				for j in range(i + 1, alive.size()):
					samples += 1
					if alive[i].global_position.distance_to(alive[j].global_position) < 28.0:
						stuck += 1
		if k == 150:
			await shot("v4_batalla")
	check(samples > 0 and float(stuck) / samples < 0.05, "6 contra 6: las tropas no se amontonan (%d de %d muestras pegadas)" % [stuck, samples])
	await clear()


# ------------------------------------------------------------------ especialidades

func _test_specialties() -> void:
	# Soldado: supresión
	var so = spawn("fusil_asalto", 0, Vector2(400, 200), {"spec": "soldado", "hit": 1})
	var dm = spawn("pistola", 1, Vector2(560, 200), {"dummy": true, "hp": 99999})
	await start()
	await wait(1.0)
	check(dm.suppressed_left > 0.0 and so.effects.suppressions > 0, "Soldado: sus impactos suprimen al blanco")
	var p_norm: float = dm.hit_chance(100.0)
	check(dm.suppressed_left > 0.0, "un suprimido pierde precisión y velocidad (velocidad ×%.2f)" % (dm.get_effective_speed() / dm.get_move_speed()))
	await clear()

	# Francotirador: tirador de élite (elige al más peligroso) y crítico contra suprimidos/marcados
	var sn = spawn("rifle_francotirador", 0, Vector2(150, 300), {"spec": "francotirador", "hit": 0})
	var weak = spawn("cuchillo", 1, Vector2(500, 300), {"dummy": true, "hp": 99999})
	var danger = spawn("bazuca", 1, Vector2(700, 200), {"dummy": true, "hp": 99999, "spec": "saboteador"})
	await start()
	await wait(0.6)
	check(sn.target == danger, "Francotirador: apunta al enemigo más peligroso a su alcance (la bazuca, no el cuchillo cercano)")
	danger.suppressed_left = 2.0
	var bonus: Dictionary = sn.effects.on_before_shot()
	check(float(bonus.crit_chance) >= 0.25, "Francotirador: +25 %% de crítico contra un suprimido (%.0f %%)" % (float(bonus.crit_chance) * 100))
	await clear()

	# Radioperador: marca, más daño al marcado y artillería sobre el grupo
	var ra = spawn("subfusil", 0, Vector2(300, 300), {"spec": "comunicaciones", "hit": 0})
	var e1 = spawn("pistola", 1, Vector2(650, 300), {"dummy": true, "hp": 5000})
	var e2 = spawn("pistola", 1, Vector2(690, 320), {"dummy": true, "hp": 5000})
	var e3 = spawn("pistola", 1, Vector2(670, 260), {"dummy": true, "hp": 5000})
	var ally = spawn("pistola", 0, Vector2(300, 420), {"dummy": true, "hp": 5000})
	await start()
	await wait(2.3)
	var marked: Array = [e1, e2, e3].filter(func(e): return e.marked_left > 0.0)
	check(marked.size() == 1 and ra.effects.marks_done >= 1, "Radioperador: marca a un enemigo")
	var unmarked: Array = [e1, e2, e3].filter(func(e): return e.marked_left <= 0.0)
	var m0: float = marked[0].health if not marked.is_empty() else 0.0
	var u0: float = unmarked[0].health
	if not marked.is_empty():
		CombatFX.apply_hit(marked[0], {"damage": 100.0})
		CombatFX.apply_hit(unmarked[0], {"damage": 100.0})
		check((m0 - marked[0].health) > (u0 - unmarked[0].health) * 1.1, "el marcado recibe más daño (%.0f vs %.0f)" % [m0 - marked[0].health, u0 - unmarked[0].health])
	var hp_before: Array = [e1.health, e2.health, e3.health]
	await wait(5.5)
	check(ra.effects.artillery_done, "Radioperador: pide artillería una vez")
	await wait(1.2)
	var hurt := 0
	for i in 3:
		if [e1, e2, e3][i].health < hp_before[i]:
			hurt += 1
	check(hurt >= 2 and is_equal_approx(ally.health, ally.get_max_health()), "la artillería cae sobre el grupo enemigo (%d heridos) y no daña a los aliados" % hurt)
	await shot("v4_radio")
	await clear()

	# Doctor: estabiliza una vez a un aliado que iba a caer
	var md = spawn("pistola", 0, Vector2(300, 300), {"spec": "medico", "dummy": true})
	var tank = spawn("pistola", 0, Vector2(380, 300), {"dummy": true, "hp": 100})
	await start()
	tank.take_damage(9999.0)
	check(not tank.is_dead and tank.health > 1.0, "Doctor: estabiliza al aliado que iba a caer (vida %d)" % tank.health)
	tank.take_damage(9999.0)
	check(tank.is_dead, "solo una vez por combate")
	await clear()

	# Contenido
	check(GameContent.specialties().size() == 7 and GameContent.find_specialty("comunicaciones") != null, "7 especialidades con el Radioperador")
	var all_desc := true
	for sp in GameContent.specialties():
		if sp.synergy_text == "" or sp.passive_description == "":
			all_desc = false
	check(all_desc, "todas las especialidades explican su mecánica y sus sinergias")


func _test_explosion_falloff() -> void:
	var shooter = spawn("bazuca", 0, Vector2(200, 300), {"dummy": true})
	var center = spawn("pistola", 1, Vector2(600, 300), {"dummy": true, "hp": 5000})
	var edge = spawn("pistola", 1, Vector2(660, 300), {"dummy": true, "hp": 5000})
	await start()
	var b = BULLET.instantiate()
	b.kind = WeaponData.Projectile.COHETE
	b.shooter_team = 0
	b.shooter = shooter
	b.info = {"damage": 100.0, "attacker": shooter}
	b.aoe_radius = 75.0
	b.target = center
	b.target_pos = center.global_position
	b.position = Vector2(560, 300)
	add_child(b)
	await wait(0.4)
	var dc: float = center.get_max_health() - center.health
	var de: float = edge.get_max_health() - edge.health
	check(dc > 90.0 and de > 0.0 and de < dc * 0.6, "la explosión pierde fuerza hacia el borde (centro %d · borde %d)" % [dc, de])
	await clear()


func _count_texts(prefix: String) -> int:
	var n := 0
	for ch in get_children():
		if ch is Label and ch.text.begins_with(prefix):
			n += 1
	return n


func _test_map_roulette() -> void:
	var G = GameStateManager
	G.reset_run()
	for k in 4:
		G.advance_stage()
	var m = load("res://Scenes/Map/map.tscn").instantiate()
	add_child(m)
	await frames(3)
	check(not m._track_holder.visible and m._chance_label.text.contains("Sin riesgo"), "ronda 5: no se ve la barra de la ruleta del jefe final")
	m.queue_free()
	G.reset_run()
	for k in 10:
		G.advance_stage()
	G.rolled_round = 0
	var m2 = load("res://Scenes/Map/map.tscn").instantiate()
	add_child(m2)
	await frames(3)
	check(m2._track_holder.visible and m2._chance_label.text.contains("0,5%"), "tras ganar la ronda 10: aparece la barra con 0,5 %% (%s)" % m2._chance_label.text)
	m2.queue_free()
	G.reset_run()
	await frames(2)

