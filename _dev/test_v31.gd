extends Node
## Tests de los cambios v3.1: Códice, Jefes de Sector cada 10 rondas + ruleta desde la 11, críticos solo
## con objeto/habilidad, impacto letal, mejora de armas con PM, 3.ª oferta rara, reclutas con arma variada
## y objeto opcional, menos PM por victoria, desglose de monedas con ⓘ, monedas que vuelan al monedero y
## barra de munición siempre visible. Capturas v31_*.png.

const BATTLE := preload("res://Scenes/Battle/battle.tscn")
const TROOP := preload("res://Scenes/Troops/troop.tscn")

var _fails: Array[String] = []
var _passes := 0


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
	DirAccess.make_dir_recursive_absolute("res://_dev/shots")
	get_viewport().get_texture().get_image().save_png("res://_dev/shots/%s.png" % name)


func _all_text(n: Node) -> String:
	var out := ""
	if n is Label or n is Button:
		out += str(n.text) + "\n"
	for c in n.get_children():
		out += _all_text(c)
	return out


func _find_script(parent: Node, suffix: String) -> Node:
	for n in parent.get_children():
		var sc = n.get_script()
		if sc and sc.resource_path.ends_with(suffix):
			return n
	return null


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	await _frames()
	_test_bosses_logic()
	_test_crit_and_recruits()
	_test_points_and_offers()
	await _test_weapon_upgrade_ui()
	await _test_codex()
	await _test_battle_features()
	await _test_subboss_battle()
	await _test_reward_info()
	await _test_map_subboss()
	print("TEST DONE: %d fallos (%d ok)" % [_fails.size(), _passes])
	for f in _fails:
		print("  - ", f)
	get_tree().quit()


# ---------------------------------------------------------------- jefes
func _test_bosses_logic() -> void:
	var G = GameStateManager
	var bm: int = G.BOSS_MIN_ROUND
	_check(G.boss_chance_for_round(bm - 1) == 0.0 and G.boss_chance_for_round(5) == 0.0, "jefe final: 0 %% hasta la ronda %d" % (bm - 1))
	_check(is_equal_approx(G.boss_chance_for_round(bm), G.BOSS_CHANCE_STEP) and is_equal_approx(G.boss_chance_for_round(bm + 4), G.BOSS_CHANCE_STEP * 5), "jefe final: %d %% en la %d y +%d %% por ronda" % [roundi(G.BOSS_CHANCE_STEP * 100), bm, roundi(G.BOSS_CHANCE_STEP * 100)])
	_check(G.is_subboss_round(10) and G.is_subboss_round(20) and not G.is_subboss_round(11) and not G.is_subboss_round(9), "Jefe de Sector en las rondas 10, 20…")
	G.reset_run()
	for i in 9:
		G.advance_stage()
	_check(G.current_stage == 10 and G.roll_round_type() == G.SUBBOSS_TYPE and not G.is_boss_stage(), "la ronda 10 es de Jefe de Sector (no la ruleta)")
	G.advance_stage()
	_check(G.current_stage == 11 and is_equal_approx(G.boss_chance, G.boss_chance_for_round(11)), "tras el sector, ronda 11 (jefe final aún imposible: %d %%)" % roundi(G.boss_chance * 100))
	_check(Economy.subboss_hp(10) == Economy.SUBBOSS_HP[0] and Economy.subboss_hp(20) == Economy.SUBBOSS_HP[1] and Economy.subboss_hp(20) > Economy.subboss_hp(10), "vida del Jefe de Sector fija por sector y creciente")
	G.reset_run()


# ---------------------------------------------------------------- críticos y reclutas
func _test_crit_and_recruits() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var c := UnitFactory.make_recruit(rng)
	c.items.clear()
	_check(float(TroopStats.compute(c).crit_chance) == 0.0, "sin objetos ni habilidades de crítico no hay críticos")
	var mira := GameContent.find_item("mira_telescopica")
	c.add_item(mira)
	_check(float(TroopStats.compute(c).crit_chance) > 0.0, "con la Mira telescópica hay crítico (%.2f)" % float(TroopStats.compute(c).crit_chance))
	var ids := {}
	var with_item := 0
	var price_ok := true
	var discount_ok := true
	for i in 400:
		var r := UnitFactory.make_recruit(rng)
		ids[r.get_weapon().id] = true
		if not r.items.is_empty():
			with_item += 1
			var it: ItemData = r.items[0]
			var bare := r.duplicate_card()
			bare.items.clear()
			var surcharge := Economy.recruit_price(r) - Economy.recruit_price(bare)
			if surcharge <= 0:
				price_ok = false
			if surcharge >= Economy.ITEM_PRICE[it.rarity]:
				discount_ok = false
	_check(ids.size() > 4, "los reclutas traen más variedad de armas (%d distintas)" % ids.size())
	_check(with_item > 80 and with_item < 220, "algunos reclutas traen objeto y otros no (%d de 400)" % with_item)
	_check(price_ok and discount_ok, "con objeto cuestan más, pero menos que comprarlo aparte (≈ -25 %)")


# ---------------------------------------------------------------- PM y 3.ª oferta
func _test_points_and_offers() -> void:
	_check(Economy.points_for_win("Batalla Normal", false) == 1 and Economy.points_for_win("Batalla Élite", false) == 2, "v4: 1 PM por victoria (2 en élite)")
	_check(Economy.points_for_win("Jefe de Sector", false) == Economy.POINTS_PER_WIN_ELITE, "el Jefe de Sector da los PM de élite")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var c := UnitFactory.make_recruit(rng)
	c.specialty = GameContent.specialties()[0]
	c.level = 3
	var threes := 0
	var n := 4000
	var max_size := 0
	for i in n:
		var o := LevelUpSystem.roll_offers(c, rng)
		max_size = maxi(max_size, o.size())
		if o.size() == 3:
			threes += 1
	var f := float(threes) / n
	_check(max_size == 3 and f > 0.015 and f < 0.06, "3.ª mejora rara al subir (%.1f %%, objetivo 2–5 %%)" % (f * 100.0))


# ---------------------------------------------------------------- mejora de armas
func _test_weapon_upgrade_ui() -> void:
	var G = GameStateManager
	G.reset_run()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var c := UnitFactory.make_recruit(rng)
	c.items.clear()
	c.weapons.assign([GameContent.find_weapon("fusil_asalto")])
	c.equipped_weapon = 0
	var dmg0: float = float(TroopStats.compute(c).damage_mult)
	var mag0: int = int(TroopStats.compute(c).magazine)
	_check(c.get_weapon_level() == 1 and c.get_weapon_upgrade_cost() == Economy.WEAPON_UPGRADE_COST[1], "arma en Nv. 1, mejorar cuesta %d PM" % Economy.WEAPON_UPGRADE_COST[1])
	_check(not LevelUpSystem.upgrade_weapon(c), "sin PM no se mejora el arma")
	G.add_points(20)
	var spent := 0
	while c.can_upgrade_weapon():
		spent += c.get_weapon_upgrade_cost()
		LevelUpSystem.upgrade_weapon(c)
	_check(c.get_weapon_level() == Economy.WEAPON_MAX_LEVEL and G.command_points == 20 - spent, "se mejora hasta Nv. %d gastando %d PM" % [Economy.WEAPON_MAX_LEVEL, spent])
	_check(not LevelUpSystem.upgrade_weapon(c), "al máximo no se puede mejorar más")
	var dmg3: float = float(TroopStats.compute(c).damage_mult)
	var mag3: int = int(TroopStats.compute(c).magazine)
	_check(dmg3 > dmg0 and dmg3 / dmg0 < 1.2 and mag3 > mag0, "la mejora es suave: daño ×%.2f y cargador %d → %d (automática)" % [dmg3 / dmg0, mag0, mag3])
	_check(c.duplicate_card().get_weapon_level() == Economy.WEAPON_MAX_LEVEL, "el nivel del arma se copia con la tropa")
	# UI del submenú
	var bt = BATTLE.instantiate()
	add_child(bt)
	await _frames(3)
	for e in bt.get_enemies():
		e.queue_free()
	var c2 := UnitFactory.make_recruit(rng)
	G.add_troop_to_army(c2)
	var detail = _find_script(bt, "troop_detail_panel.gd")
	detail.open_card(c2)
	await _frames(3)
	var btn: Button = detail.find_child("WeaponUpgradeButton", true, false)
	_check(btn != null and btn.text.contains("⭐") and not btn.disabled, "el submenú tiene 'Mejorar arma (⭐ N)'")
	await _shot("v31_mejora_arma")
	var pm0: int = G.command_points
	btn.pressed.emit()
	await _frames(3)
	_check(c2.get_weapon_level() == 2 and G.command_points < pm0, "pulsar el botón mejora el arma y gasta PM")
	var btn2: Button = detail.find_child("WeaponUpgradeButton", true, false)
	_check(btn2 != null and btn2.text.contains("Nv. 3"), "el botón pasa a ofrecer el Nv. 3")
	detail.close()
	bt.queue_free()
	await _frames(3)
	G.reset_run()


# ---------------------------------------------------------------- Códice
func _test_codex() -> void:
	# v5: el Códice está en el Cuartel general (hub)
	var menu = load("res://Scenes/UI/hub.tscn").instantiate()
	menu.change_scene_enabled = false
	add_child(menu)
	await _frames(3)
	var cb: Button = menu.find_child("CodexButton", true, false)
	_check(cb != null and cb.text.contains("Códice"), "el Cuartel tiene el botón Códice")
	await _shot("v31_menu")
	cb.pressed.emit()
	await _frames(3)
	var codex: CodexPanel = menu.codex
	_check(codex != null and codex.get_tiles().size() == GameContent.skills().size(), "el Códice muestra las %d habilidades" % GameContent.skills().size())
	var tile: Button = codex.get_tiles()[3]
	tile.mouse_entered.emit()
	await _frames(1)
	var entry: Resource = tile.get_meta("entry")
	_check(codex._detail_name.text == entry.display_name and tile.tooltip_text.contains(entry.display_name), "al pasar el ratón se ve qué hace (%s)" % entry.display_name)
	tile.pressed.emit()
	tile.mouse_exited.emit()
	await _frames(1)
	_check(codex._detail_name.text == entry.display_name, "al hacer clic la ficha queda fijada")
	await _shot("v31_codice_habilidades")
	codex.show_tab(1)
	await _frames(2)
	_check(codex.get_tiles().size() == GameContent.items().size(), "pestaña Objetos con %d objetos" % GameContent.items().size())
	await _shot("v31_codice_objetos")
	codex.show_tab(2)
	await _frames(2)
	_check(codex.get_tiles().size() == GameContent.weapons().size(), "pestaña Armas con %d armas" % GameContent.weapons().size())
	codex.close()
	await _frames(2)
	_check(not is_instance_valid(codex), "el Códice se cierra")
	menu.queue_free()
	await _frames(2)


# ---------------------------------------------------------------- combate: letal, monedero, munición
func _spawn(card: TroopCard, team: int, pos: Vector2, parent: Node) -> Node:
	var t = TROOP.instantiate()
	t.team = team
	t.setup(card)
	parent.add_child(t)
	t.global_position = pos
	return t


func _test_battle_features() -> void:
	var G = GameStateManager
	G.reset_run()
	G.current_stage = 3
	G.current_node_type = "Batalla Normal"
	G.coins = 10
	var bt = BATTLE.instantiate()
	add_child(bt)
	await _frames(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var grid = bt.find_child("DeploymentGrid", true, false)
	var pc := UnitFactory.make_recruit(rng)
	pc.items.clear()
	pc.weapons.assign([GameContent.find_weapon("fusil_asalto")])
	var p = _spawn(pc, 0, grid.grid_cells[14], bt)
	await _frames(2)
	var rbar: ProgressBar = p.get_node("ReloadBar")
	_check(rbar.visible and is_equal_approx(rbar.value, 1.0), "barra de munición visible y llena en la planificación")
	await _shot("v31_municion_planificacion")
	var enemies: Array = bt.get_enemies()
	EventBus.battle_fight_started.emit()
	var waited := 0.0
	while p.shots_fired == 0 and waited < 6.0 and is_instance_valid(p) and not p.is_dead:
		await _wait(0.1)
		waited += 0.1
	await _frames(2)
	_check(p.shots_fired > 0 and rbar.visible and (rbar.value < 1.0 or p.reloading), "al disparar la barra de munición baja (%d disparos, %.2f)" % [p.shots_fired, rbar.value])
	# Captura de las monedas en pleno vuelo hacia el monedero
	var purse0: CoinPurseHud = bt.find_child("CoinPurseHud", true, false)
	EventBus.enemy_reward.emit(Vector2(820, 220), 3)
	await _wait(0.3)
	await _shot("v31_monedas_vuelo")
	await _wait(0.8)
	purse0._shown -= 3.0 # la emisión manual no suma monedas reales
	purse0._refresh_label()
	# Impacto letal contra un enemigo normal: lo mata de un golpe
	var victim = enemies[0]
	var info := {"damage": 1.0, "crit": false, "lethal": true, "attacker": p}
	var killed: bool = CombatFX.apply_hit(victim, info)
	_check(killed, "un impacto letal mata al instante a un enemigo normal")
	var purse: CoinPurseHud = bt.find_child("CoinPurseHud", true, false)
	_check(purse != null and purse.visible, "el monedero aparece en el combate")
	var shown0: String = purse._label.text
	await _wait(0.25)
	await _shot("v31_monedas_volando")
	await _wait(0.9)
	var n0 := int(shown0.replace("💰", "").strip_edges())
	var n1 := int(purse._label.text.replace("💰", "").strip_edges())
	_check(n1 >= n0 + Economy.COINS_PER_KILL and n1 <= G.coins, "las monedas llegan al monedero y suma (%d → %d)" % [n0, n1])
	# Letal contra jefe: ×3 de daño, no muerte instantánea
	var bc := UnitFactory.make_enemy(5, false, true, rng)
	bc.base_health = 5000.0
	var boss = _spawn(bc, 1, Vector2(900, 300), bt)
	await _frames(2)
	var hp0: float = boss.health
	CombatFX.apply_hit(boss, {"damage": 40.0, "crit": false, "lethal": true, "attacker": p})
	_check(not boss.is_dead and absf((hp0 - boss.health) - 40.0 * Economy.LETHAL_BOSS_MULT) < 0.5, "contra un jefe el letal hace ×3 (−%d)" % roundi(hp0 - boss.health))
	_check(Economy.LETHAL_CHANCE > 0.0 and Economy.LETHAL_CHANCE <= 0.01, "la probabilidad de letal es muy baja (%.1f %%)" % (Economy.LETHAL_CHANCE * 100.0))
	await _shot("v31_combate")
	bt.queue_free()
	await _frames(3)
	G.reset_run()


func _test_subboss_battle() -> void:
	var G = GameStateManager
	var hps: Array = []
	for i in 3:
		G.reset_run()
		G.current_stage = 10
		G.current_node_type = G.SUBBOSS_TYPE
		var bt = BATTLE.instantiate()
		add_child(bt)
		await _frames(2)
		for e in bt.get_enemies():
			if e.card.is_boss:
				hps.append(e.get_max_health())
		bt.queue_free()
		await _frames(2)
	var same := hps.size() == 3 and hps.all(func(h): return absf(h - Economy.subboss_hp(10)) < 1.0)
	_check(same, "el Jefe de Sector de la ronda 10 tiene siempre la misma vida (%s)" % str(hps))
	G.reset_run()


# ---------------------------------------------------------------- recompensa con ⓘ
func _test_reward_info() -> void:
	var G = GameStateManager
	G.reset_run()
	G.coins = 12
	G.begin_round_tracking()
	var e := UnitFactory.make_enemy(1)
	G.register_enemy_kill(e, "Batalla Normal")
	G.register_enemy_kill(e, "Batalla Normal")
	G.apply_victory_rewards("Batalla Normal")
	var rs = load("res://Scenes/UI/reward_screen.tscn").instantiate()
	add_child(rs)
	await _frames(3)
	var gained: Label = rs.find_child("CoinsGained", true, false)
	var info: Button = rs.find_child("CoinsInfoButton", true, false)
	var breakdown: Control = rs.find_child("CoinsBreakdown", true, false)
	var s: Dictionary = G.last_round_summary
	var total: int = int(s.kill_coins) + int(s.win_coins) + int(s.interest)
	_check(gained != null and gained.text.contains("+%d" % total), "la recompensa muestra solo cuántas monedas ganas (+%d)" % total)
	_check(info != null and info.tooltip_text.contains("Bajas") and info.tooltip_text.contains("Victoria"), "el botón ⓘ explica de dónde sale cada moneda (tooltip)")
	_check(breakdown != null and not breakdown.visible, "el desglose empieza oculto")
	info.pressed.emit()
	await _frames(2)
	_check(breakdown.visible, "pulsar ⓘ muestra el desglose")
	await _shot("v31_recompensa_desglose")
	rs.queue_free()
	await _frames(2)
	G.reset_run()


func _test_map_subboss() -> void:
	var G = GameStateManager
	G.reset_run()
	for i in 9:
		G.advance_stage()
	var map = load("res://Scenes/Map/map.tscn").instantiate()
	add_child(map)
	await _frames(4)
	var t := _all_text(map)
	_check(t.contains("JEFE DE SECTOR") and t.contains(str(roundi(Economy.subboss_hp(10)))), "el mapa anuncia el Jefe de Sector y su vida")
	await _shot("v31_mapa_sector")
	map.queue_free()
	await _frames(2)
	G.reset_run()
	var map2 = load("res://Scenes/Map/map.tscn").instantiate()
	add_child(map2)
	await _frames(4)
	_check(_all_text(map2).contains("ronda 10"), "en la ronda 1 se avisa del Jefe de Sector de la ronda 10")
	map2.queue_free()
	await _frames(2)
