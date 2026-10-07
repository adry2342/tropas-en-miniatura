extends Node2D
## Test del combate (agente combate). Arena propia (sin UI) + prueba final con battle.tscn.
## Imprime TEST PASS / TEST FAIL y al final TEST DONE: N fallos.

const TROOP := preload("res://Scenes/Troops/troop.tscn")
const BATTLE_SCRIPT := preload("res://Scripts/Battle/battle.gd")
const SHOTS := "res://_dev/shots/"

var fails: Array[String] = []
var passes: int = 0
var bg: ColorRect


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
		print("TEST PASS: ", what)
	else:
		fails.append(what)
		print("TEST FAIL: ", what)


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	bg = ColorRect.new()
	bg.color = Color(0.22, 0.3, 0.2)
	bg.size = Vector2(1400, 800)
	bg.z_index = -50
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	await get_tree().process_frame
	await _run_all()
	print("TEST DONE: %d fallos" % fails.size())
	for f in fails:
		print("  - ", f)
	get_tree().quit()


func _run_all() -> void:
	await t_planning_labels()
	await t_hits_and_misses_screenshot()
	await t_reload()
	await t_explosion()
	await t_flamethrower_burn()
	await t_shotgun_pellets()
	await t_melee()
	await t_dodge_armor()
	await t_botiquin()
	await t_grenade()
	await t_camouflage()
	await t_pierce()
	await t_medic()
	await t_enemies()
	await t_bench_and_persistence()
	await t_battle_scene()


# ------------------------------------------------------------------ utilidades

func card_for(weapon_id: String, opts: Dictionary = {}) -> TroopCard:
	var c := UnitFactory.make_recruit()
	var w: WeaponData = opts.get("weapon_res", GameContent.find_weapon(weapon_id))
	c.weapons.assign([w])
	c.equipped_weapon = 0
	if opts.has("name"):
		c.unit_name = opts.name
	if opts.has("spec"):
		c.specialty = GameContent.find_specialty(opts.spec)
	for s in opts.get("skills", []):
		c.skills.append(GameContent.find_skill(s))
	for it in opts.get("items", []):
		c.items.append(GameContent.find_item(it))
	if opts.has("hp"):
		c.base_health = opts.hp
	if opts.has("level"):
		c.level = opts.level
	c.is_boss = opts.get("boss", false)
	return c


func spawn(weapon_id: String, team: int, pos: Vector2, opts: Dictionary = {}) -> Node:
	var t = TROOP.instantiate()
	t.team = team
	t.setup(card_for(weapon_id, opts))
	t.position = pos
	add_child(t)
	if opts.get("dummy", false):
		t.ai_enabled = false
	t.force_lethal = int(opts.get("lethal", 0)) # v3.1: el impacto letal aleatorio se prueba aparte (test_v31)
	return t


func fight() -> void:
	EventBus.battle_fight_started.emit()
	await get_tree().process_frame


func clear_arena() -> void:
	for ch in get_children():
		if ch != bg:
			ch.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return cond.call()


func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(SHOTS + file)
	print("Captura ", SHOTS + file, " -> ", err)


func alive(t) -> bool:
	return is_instance_valid(t) and not t.is_queued_for_deletion()


# ------------------------------------------------------------------ pruebas

func t_planning_labels() -> void:
	var specs := ["", "soldado", "francotirador", "saboteador", "medico", "mecanico"]
	var weapons := ["fusil_asalto", "subfusil", "rifle_francotirador", "bazuca", "pistola", "ametralladora"]
	var names := ["Lindqvist", "Ríos", "Kowalski", "Nakamura", "O'Brien", "Castillo"]
	var list: Array = []
	for i in 6:
		var opts := {"name": names[i], "level": 1 + i * 2}
		if specs[i] != "":
			opts["spec"] = specs[i]
		var pos := Vector2(120 + (i % 3) * 80, 200 + (i / 3) * 80)
		list.append(spawn(weapons[i], 0, pos, opts))
	var boss = spawn("bazuca", 1, Vector2(800, 260), {"name": "Volkov", "boss": true, "level": 8, "spec": "saboteador"})
	spawn("escopeta", 1, Vector2(700, 200), {"name": "Andersen"})
	spawn("cuchillo", 1, Vector2(700, 300), {"name": "Herrera", "level": 3, "spec": "soldado"})
	await get_tree().process_frame
	var lbl: Label = list[0].get_node("NameLabel")
	check(lbl.text.begins_with("Lindqvist") and "Nv.1" in lbl.text and list[0].EMOJI_FALLBACK.get(list[0].card.get_weapon().emoji, list[0].card.get_weapon().emoji) in lbl.text, "etiqueta 'Nombre Nv.X emoji' (%s)" % lbl.text.replace("\n", " / "))
	check(lbl.get_theme_color("font_color").is_equal_approx(Color.WHITE), "recluta en blanco")
	var lbl2: Label = list[2].get_node("NameLabel")
	check(lbl2.get_theme_color("font_color").is_equal_approx(GameContent.find_specialty("francotirador").color), "etiqueta con color de especialidad")
	check(lbl.size.x <= 120.0, "etiqueta no más ancha que 120 px (%d)" % lbl.size.x)
	var bl: Label = boss.get_node("NameLabel")
	check(bl.text.begins_with("☠ Volkov"), "jefe con '☠ Nombre'")
	var spr: Sprite2D = boss.get_node("Sprite2D")
	check(absf(spr.texture.get_height() * spr.scale.y - 80.0 * 1.8) < 1.0, "jefe grande (sprite ×1.8)")
	var spr0: Sprite2D = list[0].get_node("Sprite2D")
	check(absf(spr0.texture.get_height() * spr0.scale.y - 80.0) < 1.0, "sprite normal de 80 px")
	# refresh automático al subir de nivel / equipar fuera de combate
	var c: TroopCard = list[0].card
	c.items.append(GameContent.find_item("chaleco_tactico"))
	EventBus.roster_changed.emit()
	check(absf(list[0].health - TroopStats.compute(c).max_health) < 0.01 and list[0].get_max_health() > c.base_health, "roster_changed refresca stats y deja la vida al máximo")
	c.level += 1
	EventBus.troop_leveled.emit(c)
	check("Nv.2" in lbl.text, "troop_leveled refresca la etiqueta")
	await shot("combat_planificacion.png")
	await clear_arena()


func t_hits_and_misses_screenshot() -> void:
	var players: Array = []
	var enemies: Array = []
	var pw := ["fusil_asalto", "subfusil", "escopeta", "pistola"]
	var ew := ["pistola", "fusil_asalto", "subfusil", "rifle_francotirador"]
	for i in 4:
		players.append(spawn(pw[i], 0, Vector2(250, 180 + i * 90), {"hp": 400}))
		enemies.append(spawn(ew[i], 1, Vector2(800, 180 + i * 90), {"hp": 400}))
	await fight()
	for t in players + enemies:
		t.ammo = mini(t.ammo, 3) # para que se vea la recarga enseguida
	var any_reload := func():
		for t in players + enemies:
			if alive(t) and t.reloading:
				return true
		return false
	await wait(1.4)
	await wait_until(any_reload, 2.0)
	await shot("combat_disparos.png")
	await wait(1.0)
	var h := 0
	var m := 0
	for t in players + enemies:
		if alive(t):
			h += t.hits
			m += t.misses
	check(h > 0, "hay aciertos (%d)" % h)
	check(m > 0, "hay fallos (%d)" % m)
	await clear_arena()


func t_reload() -> void:
	var w: WeaponData = GameContent.find_weapon("pistola").duplicate()
	w.magazine = 3
	w.reload_time = 0.6
	w.fire_rate = 6.0
	var p = spawn("", 0, Vector2(300, 300), {"weapon_res": w})
	var e = spawn("pistola", 1, Vector2(450, 300), {"dummy": true, "hp": 5000})
	await fight()
	var saw_reload := await wait_until(func(): return p.reloading, 2.0)
	check(saw_reload, "la recarga ocurre al vaciar el cargador")
	check(p.get_node("ReloadBar").visible, "barra amarilla de recarga visible")
	var shots_at_reload: int = p.shots_fired
	await wait_until(func(): return p.shots_fired > shots_at_reload, 2.0)
	check(p.shots_fired > shots_at_reload and p.reloads >= 1, "tras recargar vuelve a disparar (%d disparos, %d recargas)" % [p.shots_fired, p.reloads])
	check(p.get_node("ReloadBar").visible and (p.reloading or p.get_node("ReloadBar").value > 0.0), "tras recargar la barra vuelve a mostrar la munición (siempre visible)")
	await clear_arena()


func t_explosion() -> void:
	var p = spawn("bazuca", 0, Vector2(250, 320), {"spec": "saboteador"})
	p.force_hit = 1
	var es: Array = []
	for off in [Vector2(0, 0), Vector2(30, -25), Vector2(25, 30)]:
		es.append(spawn("pistola", 1, Vector2(560, 320) + off, {"dummy": true, "hp": 3000}))
	await fight()
	var damaged := func():
		var n := 0
		for e in es:
			if e.health < e.get_max_health():
				n += 1
		return n
	await wait_until(func(): return damaged.call() > 0, 3.0)
	await get_tree().process_frame
	await shot("combat_explosion.png")
	check(damaged.call() >= 2, "la explosión daña a 2+ enemigos agrupados (%d)" % damaged.call())
	await clear_arena()
	# v4: el lanzagranadas ya no existe como arma (la granada sigue como objeto)
	check(GameContent.find_weapon("lanzagranadas") == null, "el lanzagranadas ya no es un arma del juego")
	await clear_arena()


func t_flamethrower_burn() -> void:
	var p = spawn("lanzallamas", 0, Vector2(400, 320))
	p.force_hit = 1
	var e = spawn("pistola", 1, Vector2(510, 320), {"dummy": true, "hp": 3000})
	await fight()
	await wait(0.7)
	await shot("combat_lanzallamas.png")
	check(e.statuses.has("burn"), "el lanzallamas deja quemadura")
	e._hurt_flash = 0.0 # el destello blanco de cada impacto (6 por segundo) taparía el tinte en la comprobación
	e.update_visuals()
	check(e.get_node("Sprite2D").modulate.g < 0.85, "tinte naranja con quemadura")
	p.ai_enabled = false
	await wait(0.4)
	var h0: float = e.health
	var b0: float = e.burn_damage_taken
	await wait(1.2)
	check(e.health < h0 and e.burn_damage_taken > b0, "la quemadura hace daño con el tiempo (%.1f)" % (h0 - e.health))
	await wait(3.0)
	check(not e.statuses.has("burn"), "la quemadura se acaba")
	await clear_arena()


func t_shotgun_pellets() -> void:
	var p = spawn("escopeta", 0, Vector2(400, 320))
	var e = spawn("pistola", 1, Vector2(480, 320), {"dummy": true, "hp": 3000})
	await fight()
	await wait_until(func(): return p.shots_fired >= 1, 2.0)
	check(p.shots_fired >= 1 and p.pellets_fired == p.shots_fired * 5, "la escopeta lanza 5 perdigones por disparo (%d/%d)" % [p.pellets_fired, p.shots_fired])
	await clear_arena()


func t_melee() -> void:
	var p = spawn("cuchillo", 0, Vector2(300, 320))
	p.force_hit = 1
	var e = spawn("pistola", 1, Vector2(450, 320), {"dummy": true, "hp": 3000})
	await fight()
	await wait_until(func(): return e.health < e.get_max_health(), 4.0)
	check(e.health < e.get_max_health(), "el cuchillo se acerca y golpea (impacto instantáneo)")
	await clear_arena()


func t_dodge_armor() -> void:
	var v = spawn("pistola", 1, Vector2(500, 300), {"dummy": true, "hp": 200})
	await get_tree().process_frame
	v.stats.armor = 0.5
	v.stats.dodge = 0.0
	var h0: float = v.health
	v.receive_hit({"damage": 20.0})
	check(absf((h0 - v.health) - 10.0) < 0.01, "armor 0.5: 20 de daño → 10")
	v.force_dodge = 1
	h0 = v.health
	v.receive_hit({"damage": 20.0})
	check(v.health == h0 and v.dodges == 1, "esquiva: no recibe daño")
	v.force_dodge = -1
	v.stats.dodge = 0.0
	v.stats.armor = 0.0
	h0 = v.health
	v.receive_hit({"damage": 20.0})
	check(absf((h0 - v.health) - 20.0) < 0.01, "sin armor ni esquiva: daño completo")
	var a = spawn("pistola", 1, Vector2(600, 300), {"dummy": true, "items": ["blindaje_pesado"]})
	await get_tree().process_frame
	check(absf(a.stats.armor - 0.2) < 0.001, "blindaje pesado da armor 0.2")
	h0 = a.health
	a.force_dodge = 0
	a.receive_hit({"damage": 50.0})
	check(absf((h0 - a.health) - 40.0) < 0.01, "armor del objeto reduce el daño (50 → 40)")
	await clear_arena()


func t_botiquin() -> void:
	var t = spawn("pistola", 0, Vector2(300, 300), {"items": ["botiquin"], "hp": 100})
	t.ai_enabled = false
	await fight()
	var mx: float = t.get_max_health()
	t.take_damage(mx * 0.7) # queda al 30 %
	check(t.health > mx * 0.6 and t.effects.botiquin_used, "el botiquín cura al bajar del 40 %% (%.0f/%.0f)" % [t.health, mx])
	var h1: float = t.health
	t.take_damage(mx * 0.4)
	check(t.health < h1 - mx * 0.39, "el botiquín solo cura una vez")
	await clear_arena()


func t_grenade() -> void:
	var p = spawn("pistola", 0, Vector2(300, 320), {"items": ["granada"]})
	p.force_hit = 0
	var e = spawn("pistola", 1, Vector2(480, 320), {"dummy": true, "hp": 3000})
	await fight()
	await wait_until(func(): return p.grenades_thrown >= 1, 4.5)
	check(p.grenades_thrown >= 1, "la granada se lanza")
	await wait_until(func(): return e.health < e.get_max_health(), 2.0)
	check(e.health < e.get_max_health(), "la granada hace daño (los disparos fallan siempre)")
	await clear_arena()


func t_camouflage() -> void:
	var p = spawn("rifle_francotirador", 0, Vector2(200, 320))
	var near = spawn("pistola", 1, Vector2(400, 320), {"dummy": true, "skills": ["camuflaje"], "hp": 3000})
	var far = spawn("pistola", 1, Vector2(600, 320), {"dummy": true, "hp": 3000})
	await fight()
	await wait(0.2)
	check(near.camo_left > 0.0 and near.modulate.a < 0.6, "camuflaje activo y semitransparente")
	check(p.target == far, "camuflaje evita ser objetivo (apunta al lejano)")
	far.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(p.target == null, "si solo quedan camuflados, espera")
	var g = spawn("pistola", 1, Vector2(450, 400), {"dummy": true, "skills": ["camuflaje", "traje_ghillie"]})
	await fight()
	check(absf(g.camo_left - 6.0) < 0.2, "camuflaje + traje ghillie: duración mayor (6 s)")
	await wait(3.2)
	check(near.camo_left <= 0.0 and p.target == near, "al acabar el camuflaje ya es objetivo")
	await clear_arena()


func t_pierce() -> void:
	var p = spawn("pistola", 0, Vector2(200, 320), {"items": ["balas_perforantes"]})
	p.force_hit = 1
	var e1 = spawn("pistola", 1, Vector2(340, 320), {"dummy": true, "hp": 3000})
	var e2 = spawn("pistola", 1, Vector2(420, 320), {"dummy": true, "hp": 3000})
	await fight()
	check(p.stats.pierce == 1, "balas perforantes: pierce 1")
	await wait_until(func(): return p.shots_fired >= 1, 1.0)
	p.ai_enabled = false
	await wait(0.8)
	check(e1.health < e1.get_max_health() and e2.health < e2.get_max_health(), "pierce atraviesa al segundo enemigo")
	await clear_arena()


func t_medic() -> void:
	var m = spawn("pistola", 0, Vector2(300, 300), {"spec": "medico", "skills": ["cirujano"]})
	var ally = spawn("pistola", 0, Vector2(380, 300), {"hp": 100})
	await fight()
	ally.health = ally.get_max_health() * 0.5
	var h0: float = ally.health
	await wait(4.4)
	var expected: float = ally.get_max_health() * 0.06 * 1.5
	check(absf((ally.health - h0) - expected) < 0.05, "el médico cura un 6 %% × heal_mult 1.5 (%.2f vs %.2f)" % [ally.health - h0, expected])
	check(m.effects.heal_done > 0.0, "el médico registra curación")
	var r = spawn("pistola", 0, Vector2(300, 450), {"skills": ["autocuracion"], "hp": 100})
	await fight()
	r.health = 50.0
	await wait(1.1)
	check(r.health > 51.5, "autocuración cura con el tiempo (%.1f)" % r.health)
	await clear_arena()


func t_enemies() -> void:
	var hp1 := 0.0
	var hp12 := 0.0
	var all_armed := true
	for i in 10:
		var c1 := UnitFactory.make_enemy(1)
		BATTLE_SCRIPT.apply_difficulty(c1, BATTLE_SCRIPT.difficulty_for(1), false)
		var c12 := UnitFactory.make_enemy(12)
		BATTLE_SCRIPT.apply_difficulty(c12, BATTLE_SCRIPT.difficulty_for(12), false)
		all_armed = all_armed and c1.get_weapon() != null and c12.get_weapon() != null
		hp1 += TroopStats.compute(c1).max_health
		hp12 += TroopStats.compute(c12).max_health
	check(all_armed, "los enemigos tienen card con arma")
	check(hp12 > hp1 * 1.5, "los enemigos escalan con la ronda (vida media %.0f → %.0f)" % [hp1 / 10.0, hp12 / 10.0])
	var b := UnitFactory.make_enemy(5, false, true)
	var base_hp := b.base_health
	BATTLE_SCRIPT.apply_difficulty(b, BATTLE_SCRIPT.difficulty_for(5), true)
	check(b.is_boss and b.base_health > base_hp * BATTLE_SCRIPT.BOSS_HP_MULT * 0.84, "el jefe lleva ×%.1f de vida" % BATTLE_SCRIPT.BOSS_HP_MULT)


func t_bench_and_persistence() -> void:
	var gsm = get_node("/root/GameStateManager")
	var t = spawn("fusil_asalto", 0, Vector2(300, 300), {"spec": "soldado", "level": 4, "skills": ["piel_dura"], "items": ["botiquin"]})
	await get_tree().process_frame
	var c: TroopCard = t.card
	gsm.save_deployed_troops([t])
	var saved: Dictionary = gsm.deployed_troops_data[0]
	check(saved.get("card") == c and saved.get("position") == t.global_position, "persistencia guarda {card, position}")
	var t2 = TROOP.instantiate()
	t2.setup(saved.card)
	add_child(t2)
	check(t2.card.level == 4 and t2.card.has_skill("piel_dura") and t2.card.has_item("botiquin") and t2.card.specialty.id == "soldado", "al restaurar conserva nivel, objetos y habilidades")
	var n0: int = gsm.player_bench.size()
	gsm.return_troop_to_bench(t)
	check(gsm.player_bench.size() == n0 + 1 and gsm.player_bench.back() == c, "retirar a la reserva conserva el card")
	gsm.player_bench.erase(c)
	gsm.deployed_troops_data.clear()
	await clear_arena()


func t_battle_scene() -> void:
	var gsm = get_node("/root/GameStateManager")
	var keep_stage: int = gsm.current_stage
	var keep_type: String = gsm.current_node_type
	var pc := card_for("fusil_asalto", {"name": "Persistente", "spec": "soldado", "level": 5, "skills": ["piel_dura", "pulso_firme"], "items": ["chaleco_tactico"]})
	gsm.deployed_troops_data = [{"card": pc, "position": Vector2(200, 300)}]
	gsm.current_stage = 9
	gsm.current_node_type = "Jefe Final"
	bg.visible = false
	var battle = load("res://Scenes/Battle/battle.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	var restored = null
	var enemies: Array = []
	for t in get_tree().get_nodes_in_group("troops"):
		if t.card == pc:
			restored = t
		elif t.team == 1:
			enemies.append(t)
	check(restored != null and restored.card.level == 5 and restored.card.has_item("chaleco_tactico") and restored.card.has_skill("pulso_firme"), "battle.tscn restaura la tropa persistida con su card")
	var boss = null
	for e in enemies:
		if e.card.is_boss:
			boss = e
	check(enemies.size() >= 2 and enemies.all(func(e): return e.card.get_weapon() != null), "battle.tscn genera enemigos con card y arma (%d)" % enemies.size())
	check(boss != null and absf(boss.get_node("Sprite2D").scale.y * boss.get_node("Sprite2D").texture.get_height() - 144.0) < 1.0, "battle.tscn: jefe grande")
	if boss:
		var avg := 0.0
		for e in enemies:
			if e != boss:
				avg += e.get_max_health()
		avg /= maxf(1.0, enemies.size() - 1)
		check(boss.get_max_health() > avg * 1.4, "el jefe tiene mucha más vida (%.0f vs %.0f)" % [boss.get_max_health(), avg])
	battle.queue_free()
	gsm.deployed_troops_data.clear()
	gsm.current_stage = keep_stage
	gsm.current_node_type = keep_type
	await get_tree().process_frame
	bg.visible = true
