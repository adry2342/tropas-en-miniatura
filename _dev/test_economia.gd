extends Node
## Tests de economía (SPEC v3): Economy, monedas/PM del GSM, recompensas, inventario.

var _fails: Array[String] = []
var _passes := 0
var _coin_signals: Array = []
var _pm_signals: Array = []
var _roster_n := 0


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
	_test_tables()
	_test_prices()
	_test_kills_points()
	_test_card()
	_test_gsm()
	_test_rewards()
	_test_inventory()
	_test_reset()
	await _test_battle_rewards()
	print("TEST DONE: %d fallos (%d ok)" % [_fails.size(), _passes])
	for f in _fails:
		print("  FALLO: ", f)
	GameStateManager.reset_run()
	get_tree().quit()


func _w(rarity: int) -> WeaponData:
	var w := WeaponData.new()
	w.id = "w_test_%d" % rarity
	w.rarity = rarity
	return w


func _it(rarity: int) -> ItemData:
	var i := ItemData.new()
	i.id = "i_test_%d" % rarity
	i.rarity = rarity
	return i


func _test_tables() -> void:
	_check(Economy.STARTING_COINS > 0 and Economy.STARTING_POINTS == 1, "constantes iniciales (monedas > 0, 1 PM)")
	_check(is_equal_approx(Economy.TRAINING_BONUS, 0.06), "TRAINING_BONUS 0.06")
	_check(GameStateManager.STARTING_GOLD == Economy.STARTING_COINS, "STARTING_GOLD alias")
	var exp: Array = Economy.LEVEL_COST
	var ok := true
	for l in range(1, 10):
		if Economy.level_cost(l) != exp[l]:
			ok = false
	_check(ok, "level_cost 1..9 según tabla")
	_check(Economy.level_cost(10) == 0 and Economy.level_cost(15) == 0, "level_cost 0 en nivel máximo")
	_check(Economy.max_shop_rarity(1) == 1 and Economy.max_shop_rarity(3) == 1, "max_shop_rarity r<4")
	_check(Economy.max_shop_rarity(4) == 2 and Economy.max_shop_rarity(7) == 2, "max_shop_rarity r<8")
	_check(Economy.max_shop_rarity(8) == 3 and Economy.max_shop_rarity(30) == 3, "max_shop_rarity r>=8")
	_check(Economy.skill_rarity_weights(2) == [60, 30, 10, 5] and Economy.skill_rarity_weights(3) == [60, 30, 10, 5], "pesos habilidad <=3")
	_check(Economy.skill_rarity_weights(4) == [40, 35, 18, 7] and Economy.skill_rarity_weights(6) == [40, 35, 18, 7], "pesos habilidad 4-6")
	_check(Economy.skill_rarity_weights(7) == [25, 35, 27, 13] and Economy.skill_rarity_weights(10) == [25, 35, 27, 13], "pesos habilidad >=7")


func _test_prices() -> void:
	for r in 4:
		_check(Economy.price_of(_it(r)) == Economy.ITEM_PRICE[r], "precio objeto rareza %d" % r)
		_check(Economy.price_of(_w(r)) == Economy.WEAPON_PRICE[r], "precio arma rareza %d" % r)
	_check(Economy.sell_price(_it(0)) == floori(Economy.ITEM_PRICE[0] * Economy.SELL_RATIO), "venta objeto común al 50 %")
	_check(Economy.sell_price(_it(3)) == floori(Economy.ITEM_PRICE[3] * Economy.SELL_RATIO), "venta objeto legendario al 50 %")
	_check(Economy.sell_price(_w(0)) == floori(Economy.WEAPON_PRICE[0] * Economy.SELL_RATIO) and Economy.sell_price(_w(2)) == floori(Economy.WEAPON_PRICE[2] * Economy.SELL_RATIO), "venta armas")
	_check(Economy.sell_price(null) == 1 and Economy.price_of(null) == 0, "null: precio 0, venta mínimo 1")
	var card := UnitFactory.make_recruit()
	var rp := Economy.recruit_price(card)
	var rp_base := rp - Economy.recruit_extras_surcharge(card)
	_check(rp_base >= Economy.RECRUIT_PRICE_MIN and rp_base <= Economy.RECRUIT_PRICE_MAX, "recruit_price (sin el suplemento por objeto) dentro de [MIN, MAX]")
	_check(Economy.price_of(card) == rp, "price_of(TroopCard) = recruit_price")
	_check(Economy.reroll_price(0) == 1 and Economy.reroll_price(1) == 2 and Economy.reroll_price(4) == 5, "reroll_price")
	_check(Economy.interest_for(0) == 0 and Economy.interest_for(9) == 0, "interés 0 con <10")
	_check(Economy.interest_for(10) == 1 and Economy.interest_for(19) == 1, "interés +1 con 10")
	_check(Economy.interest_for(20) == 2 and Economy.interest_for(99) == 2, "interés tope +2")


func _test_kills_points() -> void:
	var normal := TroopCard.new()
	var boss := TroopCard.new()
	boss.is_boss = true
	_check(Economy.coins_for_kill(normal, "Batalla Normal") == Economy.COINS_PER_KILL, "baja normal %d" % Economy.COINS_PER_KILL)
	_check(Economy.coins_for_kill(normal, "Batalla Élite") == Economy.COINS_PER_KILL_ELITE, "baja élite %d" % Economy.COINS_PER_KILL_ELITE)
	_check(Economy.coins_for_kill(boss, "Jefe Final") == Economy.COINS_PER_KILL_BOSS, "baja jefe %d" % Economy.COINS_PER_KILL_BOSS)
	_check(Economy.coins_for_kill(normal, "Jefe Final") == Economy.COINS_PER_KILL, "escolta del jefe %d" % Economy.COINS_PER_KILL)
	_check(Economy.points_for_win("Batalla Normal", false) == Economy.POINTS_PER_WIN, "PM victoria normal")
	_check(Economy.points_for_win("Batalla Normal", true) == Economy.POINTS_PER_WIN + Economy.CLEAN_WIN_BONUS_POINTS, "PM victoria normal limpia")
	_check(Economy.points_for_win("Batalla Élite", false) == Economy.POINTS_PER_WIN_ELITE, "PM victoria élite")
	_check(Economy.points_for_win("Batalla Élite", true) == Economy.POINTS_PER_WIN_ELITE + Economy.CLEAN_WIN_BONUS_POINTS, "PM victoria élite limpia")


func _test_card() -> void:
	var c := TroopCard.new()
	c.level = 1
	_check(c.get_level_up_cost() == 1, "get_level_up_cost nv1 = 1 PM")
	c.level = 5
	_check(c.get_level_up_cost() == 3, "get_level_up_cost nv5 = 3 PM")
	c.level = 10
	_check(c.get_level_up_cost() == 0, "get_level_up_cost nv10 = 0")
	c.training_ranks = 3
	_check(c.duplicate_card().training_ranks == 3, "duplicate_card copia training_ranks")
	_check(TroopCard.new().training_ranks == 0, "training_ranks por defecto 0")


func _on_coins(t: int, d: int) -> void:
	_coin_signals.append([t, d])


func _on_pm(t: int, d: int) -> void:
	_pm_signals.append([t, d])


func _on_roster() -> void:
	_roster_n += 1


func _test_gsm() -> void:
	var g := GameStateManager
	g.reset_run()
	EventBus.coins_changed.connect(_on_coins)
	EventBus.command_points_changed.connect(_on_pm)
	EventBus.roster_changed.connect(_on_roster)
	g.add_coins(7, "test")
	_check(g.coins == 7 and _coin_signals.size() == 1 and _coin_signals[0] == [7, 7], "add_coins + señal coins_changed")
	_check(_roster_n >= 1, "add_coins emite roster_changed")
	_check(g.spend_coins(3) and g.coins == 4 and _coin_signals[-1] == [4, -3], "spend_coins ok + señal")
	var n := _coin_signals.size()
	_check(not g.spend_coins(5) and g.coins == 4 and _coin_signals.size() == n, "spend_coins insuficiente: false sin señal")
	_check(not g.spend_coins(-1), "spend_coins negativo rechazado")
	g.add_points(3, "test")
	_check(g.command_points == 3 and _pm_signals[0] == [3, 3], "add_points + señal")
	_check(g.spend_points(2) and g.command_points == 1 and _pm_signals[-1] == [1, -2], "spend_points ok + señal")
	_check(not g.spend_points(2) and g.command_points == 1, "spend_points insuficiente")
	g.gold = 20
	_check(g.coins == 20, "alias gold set")
	g.add_gold(5)
	_check(g.coins == 25 and g.gold == 25, "alias add_gold")
	_check(g.spend_gold(5) and g.coins == 20, "alias spend_gold")
	_check(not g.spend_gold(99), "alias spend_gold insuficiente")
	# recruit_troop en monedas
	g.reset_run()
	var card := UnitFactory.make_recruit()
	g.coins = 5
	_check(not g.recruit_troop(card, 8) and g.coins == 5, "recruit_troop sin monedas falla")
	g.coins = 12
	_check(g.recruit_troop(card, 8) and g.coins == 4 and card in g.player_bench, "recruit_troop cobra monedas")


func _test_rewards() -> void:
	var g := GameStateManager
	g.reset_run()
	g.coins = 5
	g.command_points = 0
	g.begin_round_tracking()
	var e := TroopCard.new()
	var b := TroopCard.new()
	b.is_boss = true
	var kn := Economy.COINS_PER_KILL
	var ke := Economy.COINS_PER_KILL_ELITE
	var kb := Economy.COINS_PER_KILL_BOSS
	_check(g.register_enemy_kill(e, "Batalla Normal") == kn, "register_enemy_kill normal -> %d" % kn)
	_check(g.register_enemy_kill(e, "Batalla Élite") == ke, "register_enemy_kill élite -> %d" % ke)
	_check(g.register_enemy_kill(b, "Jefe Final") == kb, "register_enemy_kill jefe -> %d" % kb)
	var ksum := kn + ke + kb
	_check(g.round_kills == 3 and g.round_kill_coins == ksum and g.coins == 5 + ksum, "seguimiento de bajas")
	var s := g.apply_victory_rewards("Batalla Normal")
	var i1 := Economy.interest_for(5 + ksum + Economy.WIN_BONUS_COINS)
	var tot1 := 5 + ksum + Economy.WIN_BONUS_COINS + i1
	var p1 := Economy.points_for_win("Batalla Normal", true)
	_check(s["kills"] == 3 and s["kill_coins"] == ksum and s["win_coins"] == Economy.WIN_BONUS_COINS, "resumen: bajas y bono")
	_check(s["interest"] == i1 and s["points"] == p1 and s["clean"] == true, "resumen: interés, PM, limpia")
	_check(s["coins_total"] == tot1 and g.coins == tot1 and s["points_total"] == p1 and g.command_points == p1, "resumen: totales")
	_check(g.last_round_summary == s, "last_round_summary guardado")
	# Con bajas, élite, interés máximo
	g.coins = Economy.INTEREST_STEP * (Economy.INTEREST_MAX + 1)
	var c2 := g.coins
	g.command_points = 0
	g.begin_round_tracking()
	g.register_player_loss()
	_check(g.round_player_losses == 1, "register_player_loss")
	s = g.apply_victory_rewards("Batalla Élite")
	_check(s["clean"] == false and s["points"] == Economy.points_for_win("Batalla Élite", false) and s["points"] == Economy.POINTS_PER_WIN_ELITE,
			"victoria con bajas: sin bono, élite %d PM" % Economy.POINTS_PER_WIN_ELITE)
	_check(s["interest"] == Economy.INTEREST_MAX and s["coins_total"] == c2 + Economy.WIN_BONUS_COINS + Economy.INTEREST_MAX, "interés tope +%d" % Economy.INTEREST_MAX)
	g.begin_round_tracking()
	_check(g.round_kills == 0 and g.round_kill_coins == 0 and g.round_player_losses == 0, "begin_round_tracking limpia")


func _test_inventory() -> void:
	var g := GameStateManager
	g.reset_run()
	var w := _w(1)
	var i := _it(2)
	g.player_bench.append(w)
	g.player_bench.append(i)
	_check(g.get_bench_weapons() == [w] and g.get_bench_items() == [i], "get_bench_weapons / items separan")
	var card := UnitFactory.make_recruit()
	var before := card.weapons.size()
	_check(g.equip_weapon_from_bench(card, w), "equip_weapon_from_bench ok")
	_check(card.weapons.size() == before + 1 and card.has_weapon(w.id) and not w in g.player_bench, "arma al arsenal y fuera del inventario")
	g.player_bench.append(w)
	_check(not g.equip_weapon_from_bench(card, w) and w in g.player_bench, "arma repetida: false y se queda")
	_check(not g.equip_weapon_from_bench(card, _w(3)), "arma ajena al inventario: false")
	# venta
	g.coins = 0
	var si := Economy.sell_price(i)
	var sw := Economy.sell_price(w)
	_check(g.sell_from_bench(i) == si and g.coins == si and not i in g.player_bench, "sell_from_bench objeto épico +%d" % si)
	_check(g.sell_from_bench(i) == 0 and g.coins == si, "vender dos veces: 0")
	_check(g.sell_from_bench(w) == sw and g.coins == si + sw, "sell_from_bench arma rara +%d" % sw)


func _test_reset() -> void:
	var g := GameStateManager
	g.coins = 9
	g.command_points = 4
	g.equipment_offers = [_it(0), null]
	g.reroll_count = 3
	g.round_kills = 5
	g.last_round_summary = {"x": 1}
	g.advance_stage()
	_check(g.equipment_offers.is_empty() and g.reroll_count == 0, "advance_stage limpia ofertas y reroll")
	_check(g.coins == 9 and g.command_points == 4, "advance_stage conserva monedas/PM")
	g.equipment_offers = [_it(1)]
	g.reroll_count = 2
	g.shop_offers = [1]
	g.reset_run()
	_check(g.coins == 0 and g.command_points == 0, "reset_run pone monedas/PM a 0")
	_check(g.equipment_offers.is_empty() and g.reroll_count == 0 and g.shop_offers.is_empty(), "reset_run limpia ofertas")
	_check(g.round_kills == 0 and g.last_round_summary.is_empty(), "reset_run limpia seguimiento")
	_check(g.current_stage == 1 and g.wins_count == 0, "reset_run reinicia ronda")



func _test_battle_rewards() -> void:
	var g := GameStateManager
	g.reset_run()
	g.current_stage = 1
	g.current_node_type = "Batalla Normal"
	
	# Simular manualmente una victoria: configurar resumen y llamar apply_victory_rewards
	var kc := Economy.COINS_PER_KILL
	var start_coins := 13
	g.coins = start_coins
	g.command_points = 0
	g.begin_round_tracking()
	
	# Simular bajas (sin instanciar batalla)
	var enemy_card := TroopCard.new()
	g.register_enemy_kill(enemy_card, "Batalla Normal")
	g.register_enemy_kill(enemy_card, "Batalla Normal")
	var after_kills := start_coins + 2 * kc
	_check(g.round_kills == 2 and g.round_kill_coins == 2 * kc and g.coins == after_kills, "bajas registradas: 2 kills, +%d monedas" % (2 * kc))
	
	# apply_victory_rewards: el interés se calcula sobre las monedas tras bajas y bonus
	var summary := g.apply_victory_rewards("Batalla Normal")
	var interest := Economy.interest_for(after_kills + Economy.WIN_BONUS_COINS)
	var total := after_kills + Economy.WIN_BONUS_COINS + interest
	var pts := Economy.points_for_win("Batalla Normal", true)
	_check(summary.get("kills") == 2 and summary.get("kill_coins") == 2 * kc, "resumen: kills=2, kill_coins=%d" % (2 * kc))
	_check(summary.get("win_coins") == Economy.WIN_BONUS_COINS and summary.get("interest") == interest, "resumen: victoria +%d, interés +%d" % [Economy.WIN_BONUS_COINS, interest])
	_check(summary.get("points") == pts and summary.get("clean") == true, "resumen: puntos=%d, limpia=true" % pts)
	_check(summary.get("coins_total") == total and g.coins == total, "resumen: total %d monedas" % total)
	_check(summary.get("points_total") == pts and g.command_points == pts, "resumen: total %d PM" % pts)
	
	# La pantalla de recompensa real muestra el resumen (💰/⭐, "Bajas") y nunca "oro"
	var rs: Node = load("res://Scenes/UI/reward_screen.tscn").instantiate()
	add_child(rs)
	await get_tree().process_frame
	await get_tree().process_frame
	var labels: Array[String] = []
	for l in rs.find_children("*", "Label", true, false):
		labels.append((l as Label).text)
	var all_text := "\n".join(labels)
	var has_kills := labels.any(func(t): return t.contains("Bajas") and t.contains("💰") and t.contains("+%d" % (2 * kc)))
	var has_oro := RegEx.create_from_string("(?i)\\boro\\b").search(all_text) != null
	_check(has_kills, "reward_screen: etiqueta 'Bajas' con 💰 (+%d por 2 bajas)" % (2 * kc))
	_check(labels.any(func(t): return t.contains("Victoria") and t.contains("💰")) and labels.any(func(t): return t.contains("⭐") and t.contains("Puntos de Mando")),
			"reward_screen: bono de victoria 💰 y PM ⭐")
	_check(labels.any(func(t): return t.begins_with("💰 %d" % total)) and labels.any(func(t): return t.begins_with("⭐ %d" % pts)), "reward_screen: totales 💰 %d · ⭐ %d" % [total, pts])
	_check(not has_oro, "reward_screen: ningún texto dice 'oro' ni 💰")
	rs.queue_free()
	await get_tree().process_frame

	await _test_kill_timing()


## Bajas enemigas en una batalla real: solo cuentan tras battle_fight_started y mientras la batalla no ha terminado.
func _test_kill_timing() -> void:
	var g := GameStateManager
	g.reset_run()
	# Primera ronda cuyo máximo de enemigos permite ≥ 3 (con menos no se podrían probar las bajas)
	var stage := 1
	while stage < 30 and int(load("res://Scripts/Battle/battle.gd").difficulty_for(stage).max_enemies) < 3:
		stage += 1
	g.current_stage = stage
	g.current_node_type = "Batalla Normal"
	g.coins = 5
	var battle: Node = null
	var enemies: Array = []
	for attempt in 20: # el nº de enemigos es aleatorio por ronda: se repite hasta tener ≥ 3
		battle = load("res://Scenes/Battle/battle.tscn").instantiate()
		add_child(battle)
		await get_tree().create_timer(0.3).timeout
		enemies = battle.get_enemies()
		if enemies.size() >= 3:
			break
		battle.queue_free()
		await get_tree().process_frame
	_check(enemies.size() >= 3, "batalla real con enemigos (%d)" % enemies.size())
	if enemies.size() < 3:
		if is_instance_valid(battle):
			battle.queue_free()
		return
	# 1) Muere ANTES de battle_fight_started: ni bajas ni monedas
	var rewards: Array = []
	var cb := func(_pos: Vector2, c: int): rewards.append(c)
	EventBus.enemy_reward.connect(cb)
	var coins0: int = g.coins
	enemies[0].die()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(g.coins == coins0 and g.round_kills == 0 and g.round_kill_coins == 0 and rewards.is_empty(), "enemigo muerto antes del combate: sin monedas, sin baja, sin enemy_reward")
	_check(not battle.is_battle_over, "una baja previa al combate no termina la batalla")
	# 2) Tras empezar el combate, cada baja cuenta (hace falta una tropa del jugador viva: si no, la batalla se pierde al instante)
	var ally: Node = load("res://Scenes/Troops/troop.tscn").instantiate()
	ally.team = ally.Team.PLAYER
	ally.setup(UnitFactory.make_recruit())
	ally.position = Vector2(200, 300)
	battle.add_child(ally)
	ally.ai_enabled = false
	await get_tree().process_frame
	EventBus.battle_fight_started.emit()
	await get_tree().process_frame
	var alive: Array = battle.get_enemies().filter(func(e): return is_instance_valid(e) and not e.is_queued_for_deletion() and e.health > 0.0)
	_check(g.round_kills == 0, "begin_round_tracking al empezar el combate (bajas = 0)")
	if alive.size() >= 2:
		alive[0].die()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(g.round_kills == 1 and g.round_kill_coins == Economy.COINS_PER_KILL and g.coins == coins0 + Economy.COINS_PER_KILL and rewards == [Economy.COINS_PER_KILL],
				"baja en combate: +%d 💰 y enemy_reward" % Economy.COINS_PER_KILL)
		# 3) Tras is_battle_over no se cuentan más bajas
		battle.is_battle_over = true
		var kills := g.round_kills
		var coins1: int = g.coins
		alive[1].die()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(g.round_kills == kills and g.coins == coins1 and rewards.size() == 1, "tras is_battle_over no se cuentan más bajas ni monedas")
	else:
		_check(false, "quedan ≥2 enemigos vivos para probar las bajas")
	EventBus.enemy_reward.disconnect(cb)
	battle.queue_free()
	await get_tree().process_frame
