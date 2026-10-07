extends Node
## Simulador de PARTIDA COMPLETA (equilibrado v3). Combates reales de battle.tscn; un bot juega la
## economía real (monedas por baja, PM por victoria, Intendencia, subida de nivel con PM).
## Argumentos (tras "--"): policy=sensato|aleatorio|heroe|solo_reclutas|ahorrador|ambas|lista,separada,por,comas runs=N seconds=S out=/ruta.csv tag=X
## Escribe una línea por ronda jugada (CSV, append) y termina con "RUNSIM DONE".

const BATTLE = preload("res://Scenes/Battle/battle.tscn")
const TROOP = preload("res://Scenes/Troops/troop.tscn")
const MAX_ROUNDS := 70
const TIMEOUT := 150.0 # s de juego por combate (empate = derrota)
const COLS := 5
const SAVE_REACH := 5 # monedas que el sensato está dispuesto a ahorrar
const SAVE_FACTOR := 1.3
const AHORRO_RESERVE := 20 # el ahorrador nunca baja de 20 💰 (interés máximo)
const HEADER := "tag,policy,run,round,node,won,coins_start,coins_earned,coins_spent,pm_earned,pm_spent,coins_end,lvl_avg,lvl_max,troops,items_eq,weapons_bought,recruits_bought,items_bought,p_power,e_power,p_lan,e_lan,dur,n_enemies"

var _clock := 0.0
var rng := RandomNumberGenerator.new()
## Experimento (propuesta, NO es la mecánica actual): +N monedas al precio del recluta por cada tropa que ya tengas.
var recruit_step := 0
var out_path := "/tmp/runsim.csv"
var tag := "x"
var roster: Array[TroopCard] = []
# Contadores de la ronda (gasto)
var r_spent := 0
var r_pm_spent := 0
var r_recruits := 0
var r_items := 0
var r_weapons := 0


func _process(delta: float) -> void:
	_clock += delta


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	Engine.physics_ticks_per_second = int(OS.get_environment("SIM_TPS")) if OS.get_environment("SIM_TPS") != "" else 30
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var policy: String = args.get("policy", "ambas")
	var runs: int = int(args.get("runs", "4"))
	var seconds: float = float(args.get("seconds", "450"))
	out_path = args.get("out", out_path)
	tag = args.get("tag", tag)
	recruit_step = int(args.get("recruit_step", "0"))
	rng.randomize()
	Engine.max_physics_steps_per_frame = 8
	if not FileAccess.file_exists(out_path):
		var f0 := FileAccess.open(out_path, FileAccess.WRITE)
		f0.store_line(HEADER)
		f0.close()
	var t0 := Time.get_ticks_msec()
	var done := 0
	for i in runs:
		if (Time.get_ticks_msec() - t0) / 1000.0 > seconds:
			break
		var pols: PackedStringArray = ["sensato", "aleatorio"] if policy == "ambas" else policy.split(",")
		var pol: String = pols[i % pols.size()]
		await play_run(pol, "%s-%d" % [tag, i])
		done += 1
	print("RUNSIM DONE runs=%d in %.0fs" % [done, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit()


# ---------------------------------------------------------------- partida
func play_run(policy: String, run_id: String) -> void:
	var gsm = GameStateManager
	gsm.reset_run()
	roster.clear()
	_cur_policy_sensible = policy != "aleatorio"
	_policy = policy
	gsm.add_coins(Economy.STARTING_COINS, "inicio")
	gsm.add_points(Economy.STARTING_POINTS, "inicio")
	# Selección inicial: 3 reclutas, se elige 1
	var picks: Array[TroopCard] = []
	for k in 3:
		picks.append(UnitFactory.make_recruit())
	var first: TroopCard = picks[rng.randi_range(0, 2)]
	if policy != "aleatorio":
		for c in picks:
			if card_power(c) > card_power(first):
				first = c
	roster.append(first)
	var coins_total_earned := 0
	for round_num in range(1, MAX_ROUNDS + 1):
		gsm.current_stage = round_num
		var node: String = gsm.roll_round_type()
		r_spent = 0; r_pm_spent = 0; r_recruits = 0; r_items = 0; r_weapons = 0
		var coins_start: int = gsm.coins
		var pm_before: int = gsm.command_points
		# Planificación: subir de nivel y comprar
		match policy:
			"aleatorio":
				level_up_random()
				shop_random()
			"heroe":
				level_up_hero()
				shop_sensible()
			"solo_reclutas":
				level_up_sensible()
				shop_sensible(0, true)
			"ahorrador":
				level_up_sensible()
				shop_sensible(AHORRO_RESERVE)
			_:
				level_up_sensible()
				shop_sensible()
		var coins_pre_battle: int = gsm.coins
		var res: Dictionary = await fight()
		var coins_earned: int = gsm.coins - coins_pre_battle
		var pm_earned: int = gsm.command_points - (pm_before - r_pm_spent)
		coins_total_earned += coins_earned
		var lv_sum := 0
		var lv_max := 0
		var items_eq := 0
		for c in roster:
			lv_sum += c.level
			lv_max = maxi(lv_max, c.level)
			items_eq += c.items.size()
		var row := [tag, policy, run_id, round_num, node, int(res.won), coins_start, coins_earned, r_spent,
			pm_earned, r_pm_spent, gsm.coins, "%.2f" % (float(lv_sum) / roster.size()), lv_max, roster.size(),
			items_eq, r_weapons, r_recruits, r_items, "%.0f" % res.p_power, "%.0f" % res.e_power,
			"%.0f" % res.p_lan, "%.0f" % res.e_lan, "%.1f" % res.dur, res.n_enemies]
		var f := FileAccess.open(out_path, FileAccess.READ_WRITE)
		f.seek_end()
		f.store_line(",".join(row.map(func(v): return str(v))))
		f.close()
		if not res.won or node == gsm.BOSS_TYPE:
			break
		gsm.advance_stage()
	print("RUN %s %s fin ronda %d" % [run_id, policy, gsm.current_stage])


# ---------------------------------------------------------------- poder
## Valor de combate de una tropa: vida efectiva × DPS (con extras heurísticos).
func card_power(c: TroopCard) -> float:
	var s: Dictionary = TroopStats.compute(c)
	return ehp(s, c) * edps(s, c)


func ehp(s: Dictionary, c: TroopCard) -> float:
	var h: float = float(s.max_health) / (1.0 - float(s.armor)) / (1.0 - float(s.dodge))
	for it in c.items:
		if it.effect_id == "botiquin":
			h *= 1.15
	return h


func edps(s: Dictionary, c: TroopCard) -> float:
	var d: float = float(s.dps) * (1.0 + 0.15 * float(s.pierce)) * (1.0 + 0.3 * float(s.attack_range) / 600.0)
	if float(s.aoe_radius) > 0.0:
		d *= 1.3
	for it in c.items:
		if it.effect_id == "granada":
			d *= 1.15
		elif it.effect_id == "adrenalina":
			d *= 1.12
	for sk in c.skills:
		if sk.effect_id != "":
			d *= 1.0 + 0.04 * (sk.rarity + 1)
	return d


## Poder de ejército (Lanchester): (Σ vida efectiva) × (Σ DPS).
func army_power(cards: Array) -> float:
	var h := 0.0
	var d := 0.0
	for c in cards:
		var s: Dictionary = TroopStats.compute(c)
		h += ehp(s, c)
		d += edps(s, c)
	return h * d


# ---------------------------------------------------------------- subir de nivel
func level_up_sensible() -> void:
	var guard := 0
	while guard < 20:
		guard += 1
		# La más barata de subir; a igualdad, la más fuerte (se concentra algo de poder)
		var best: TroopCard = null
		for c in roster:
			if not c.can_level_up() or c.get_level_up_cost() <= 0:
				continue
			if c.get_level_up_cost() > GameStateManager.command_points:
				continue
			if best == null or c.get_level_up_cost() < best.get_level_up_cost() \
					or (c.get_level_up_cost() == best.get_level_up_cost() and card_power(c) > card_power(best)):
				best = c
		if best == null:
			return
		var cost := best.get_level_up_cost()
		if not LevelUpSystem.begin_level_up(best, rng):
			return
		r_pm_spent += cost
		LevelUpSystem.choose(best, pick_offer_sensible(best))


func pick_offer_sensible(c: TroopCard) -> int:
	var best_i := 0
	var best_v := -INF
	for i in c.pending_offers.size():
		var o: Dictionary = c.pending_offers[i]
		var v := 0.0
		match String(o.type):
			"specialty":
				v = 100.0 if o.resource.is_affine(c.get_weapon()) else 0.0
				v += rng.randf()
			"skill":
				v = 10.0 * o.resource.rarity + (5.0 if o.resource.specialty_id != "" else 0.0) + rng.randf()
			"training":
				v = 3.0
		if v > best_v:
			best_v = v
			best_i = i
	return best_i


## Héroe: todos los PM a la misma tropa (la elegida al empezar); solo si ya es Nv. máximo, a las demás.
func level_up_hero() -> void:
	var guard := 0
	while guard < 20:
		guard += 1
		var hero: TroopCard = roster[0]
		var target: TroopCard = null
		if hero.can_level_up() and hero.get_level_up_cost() > 0:
			target = hero
		else:
			for c in roster:
				if c.can_level_up() and c.get_level_up_cost() > 0 and (target == null or c.get_level_up_cost() < target.get_level_up_cost()):
					target = c
		if target == null or target.get_level_up_cost() > GameStateManager.command_points:
			return
		var cost := target.get_level_up_cost()
		if not LevelUpSystem.begin_level_up(target, rng):
			return
		r_pm_spent += cost
		LevelUpSystem.choose(target, pick_offer_sensible(target))


func level_up_random() -> void:
	var guard := 0
	while guard < 20:
		guard += 1
		var opts: Array = []
		for c in roster:
			if c.can_level_up() and c.get_level_up_cost() > 0 and c.get_level_up_cost() <= GameStateManager.command_points:
				opts.append(c)
		if opts.is_empty() or rng.randf() < 0.3: # a veces se guarda PM sin motivo
			return
		var c: TroopCard = opts[rng.randi_range(0, opts.size() - 1)]
		var cost := c.get_level_up_cost()
		if not LevelUpSystem.begin_level_up(c, rng):
			return
		r_pm_spent += cost
		LevelUpSystem.choose(c, rng.randi_range(0, c.pending_offers.size() - 1))


# ---------------------------------------------------------------- Intendencia
func ensure_recruit_offers() -> void:
	var gsm = GameStateManager
	if gsm.shop_offers.is_empty():
		for i in 3:
			gsm.shop_offers.append(UnitFactory.make_recruit(null, true))


func army_slots_free() -> bool:
	return roster.size() < GameStateManager.MAX_ARMY_SIZE


## Mejor uso de un objeto/arma: [tropa, ganancia de poder de ejército, índice de arma] (tropa null si no sirve).
func best_use(res: Resource) -> Array:
	var base := army_power(roster)
	var best: TroopCard = null
	var best_gain := 0.0
	for c in roster:
		var tmp := c.duplicate_card()
		if res is ItemData:
			if not tmp.add_item(res):
				continue
		elif res is WeaponData:
			if tmp.has_weapon(res.id):
				continue
			tmp.weapons.append(res)
			tmp.equipped_weapon = tmp.weapons.size() - 1
		var arr: Array = roster.duplicate()
		arr[arr.find(c)] = tmp
		var gain := army_power(arr) - base
		if gain > best_gain:
			best_gain = gain
			best = c
	return [best, best_gain]


func equip(res: Resource, c: TroopCard) -> void:
	var gsm = GameStateManager
	if res is ItemData:
		gsm.equip_item_from_bench(c, res)
	elif res is WeaponData:
		var before := card_power(c)
		var prev := c.equipped_weapon
		if gsm.equip_weapon_from_bench(c, res):
			c.equipped_weapon = c.weapons.size() - 1
			if card_power(c) < before:
				c.equipped_weapon = prev


func rprice(card: TroopCard) -> int:
	return Economy.recruit_price(card) + recruit_step * maxi(0, roster.size() - 1)


func buy_recruit(card: TroopCard) -> bool:
	var gsm = GameStateManager
	if not gsm.recruit_troop(card, rprice(card)):
		return false
	r_spent += rprice(card)
	r_recruits += 1
	gsm.shop_offers.erase(card)
	gsm.player_bench.erase(card) # el simulador guarda el ejército en `roster`
	roster.append(card)
	return true


func buy_equipment_at(i: int) -> Resource:
	var gsm = GameStateManager
	var res: Resource = gsm.equipment_offers[i]
	var price := Economy.price_of(res)
	if not ShopSystem.buy_equipment(i):
		return null
	r_spent += price
	if res is WeaponData:
		r_weapons += 1
	else:
		r_items += 1
	return res


## Sensato: compra lo que más poder de ejército da por moneda (reclutas incluidos), mientras pueda.
func shop_sensible(reserve: int = 0, recruits_only: bool = false) -> void:
	var gsm = GameStateManager
	ensure_recruit_offers()
	ShopSystem.ensure_offers()
	var rerolled := false
	var guard := 0
	while guard < 30:
		guard += 1
		var base := army_power(roster)
		var best_kind := ""
		var best_ref = null
		var best_target: TroopCard = null
		var best_ratio := 0.0
		var best_any := 0.0
		if army_slots_free():
			for rc in gsm.shop_offers:
				var price := rprice(rc)
				var arr: Array = roster.duplicate()
				arr.append(rc)
				var ratio := (army_power(arr) - base) / price
				if price - (gsm.coins - reserve) <= SAVE_REACH:
					best_any = maxf(best_any, ratio)
				if price > (gsm.coins - reserve):
					continue
				if ratio > best_ratio:
					best_ratio = ratio; best_kind = "recruit"; best_ref = rc
		for i in gsm.equipment_offers.size():
			var res: Resource = gsm.equipment_offers[i]
			if res == null or recruits_only:
				continue
			var use := best_use(res)
			if use[0] == null:
				continue
			var ratio2: float = float(use[1]) / Economy.price_of(res)
			if Economy.price_of(res) - (gsm.coins - reserve) <= SAVE_REACH:
				best_any = maxf(best_any, ratio2)
			if Economy.price_of(res) > (gsm.coins - reserve):
				continue
			if ratio2 > best_ratio:
				best_ratio = ratio2; best_kind = "equip"; best_ref = i; best_target = use[0]
		# Ahorrar: lo mejor está a pocas monedas y rinde bastante más que lo asequible
		if best_any > SAVE_FACTOR * best_ratio:
			return
		if best_kind == "recruit":
			buy_recruit(best_ref)
		elif best_kind == "equip":
			var bought := buy_equipment_at(best_ref)
			if bought:
				equip(bought, best_target)
		else:
			# Nada útil asequible: renovar una vez si sobra dinero
			if not rerolled and not recruits_only and (gsm.coins - reserve) >= 12 and (gsm.coins - reserve) >= ShopSystem.reroll_cost() + 6:
				var rc_cost := ShopSystem.reroll_cost()
				if ShopSystem.reroll():
					r_spent += rc_cost
					rerolled = true
					continue
			return


## Aleatorio: compra cosas al azar que pueda pagar (50 % de seguir comprando) y las equipa al azar.
func shop_random() -> void:
	var gsm = GameStateManager
	ensure_recruit_offers()
	ShopSystem.ensure_offers()
	var guard := 0
	while guard < 20 and rng.randf() < 0.75:
		guard += 1
		var opts: Array = []
		if army_slots_free():
			for rc in gsm.shop_offers:
				if rprice(rc) <= gsm.coins:
					opts.append(rc)
		for i in gsm.equipment_offers.size():
			var res: Resource = gsm.equipment_offers[i]
			if res != null and Economy.price_of(res) <= gsm.coins:
				opts.append(i)
		if opts.is_empty():
			return
		var pick = opts[rng.randi_range(0, opts.size() - 1)]
		if pick is TroopCard:
			buy_recruit(pick)
		else:
			var bought := buy_equipment_at(pick)
			if bought:
				var targets := roster.duplicate()
				targets.shuffle()
				for c in targets:
					var before_bench: bool = bought in gsm.player_bench
					equip(bought, c)
					if before_bench and not bought in gsm.player_bench:
						break


# ---------------------------------------------------------------- combate
func fight() -> Dictionary:
	var gsm = GameStateManager
	gsm.deployed_troops_data.clear()
	var bt = BATTLE.instantiate()
	add_child(bt)
	await get_tree().process_frame
	var grid = bt.find_child("DeploymentGrid", true, false)
	var enemies: Array = bt.get_enemies()
	var e_power := 0.0
	var e_h := 0.0
	var e_d := 0.0
	for e in enemies:
		e_power += e.get_max_health() * float(e.stats.dps)
		e_h += e.get_max_health()
		e_d += float(e.stats.dps)
	# Despliegue: sensato = alcance corto delante; aleatorio = casillas al azar
	var order: Array = roster.duplicate()
	order.sort_custom(func(a, b): return TroopStats.compute(a).attack_range < TroopStats.compute(b).attack_range)
	var front: Array[int] = []
	for col in [4, 3, 2, 1, 0]:
		for row in [2, 1, 3, 0, 4]:
			front.append(row * COLS + col)
	var p_power := 0.0
	var p_h := 0.0
	var p_d := 0.0
	var idx := 0
	var rnd_cells: Array = range(25)
	rnd_cells.shuffle()
	for c in order:
		var t = TROOP.instantiate()
		t.team = t.Team.PLAYER
		t.setup(c)
		bt.add_child(t)
		var cell: int = front[idx] if _policy_is_sensible() else int(rnd_cells[idx])
		t.global_position = grid.grid_cells[cell]
		idx += 1
		var s: Dictionary = TroopStats.compute(c)
		p_power += float(s.max_health) * float(s.dps)
		p_h += float(s.max_health)
		p_d += float(s.dps)
	await get_tree().process_frame
	EventBus.battle_fight_started.emit()
	var start := _clock
	while not bt.is_battle_over and _clock - start < TIMEOUT:
		await get_tree().process_frame
	var dur := _clock - start
	var won := false
	if bt.is_battle_over:
		for t in get_tree().get_nodes_in_group("troops"):
			if is_instance_valid(t) and not t.is_queued_for_deletion() and t.team == t.Team.PLAYER:
				won = true
	bt.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return {"won": won, "dur": dur, "p_power": p_power, "e_power": e_power,
		"p_lan": p_h * p_d, "e_lan": e_h * e_d, "n_enemies": enemies.size()}


var _cur_policy_sensible := true
var _policy := "sensato"
func _policy_is_sensible() -> bool:
	return _cur_policy_sensible
