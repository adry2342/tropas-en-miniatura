extends Node2D
## Simulación de balance (QA, sin ajustar a fondo): combates reales de battle.tscn con tropas del
## jugador generadas como lo haría un jugador. Mide % de victorias y duración (s de juego).

const BATTLE = preload("res://Scenes/Battle/battle.tscn")
const TROOP = preload("res://Scenes/Troops/troop.tscn")
const TIMEOUT := 120.0
const SPEED := 4.0
const FRONT_CELLS := [14, 9, 19, 13, 8, 18] # cuadrícula 5x5: frente = última columna

var _clock := 0.0


func _process(delta: float) -> void:
	_clock += delta


func player_card(level: int) -> TroopCard:
	var c := UnitFactory.make_recruit()
	while c.level < level:
		var offers := LevelUpSystem.roll_offers(c)
		if offers.is_empty():
			c.level += 1
			continue
		var offer: Dictionary = offers[randi() % offers.size()]
		for o in offers: # jugador sensato: especialidad afín a su arma, o arma afín a su especialidad
			if o.type == "specialty" and o.resource.is_affine(c.get_weapon()):
				offer = o
			elif o.type == "weapon" and c.specialty != null and c.specialty.is_affine(o.resource):
				offer = o
		var equip: bool = offer.type == "weapon" and c.specialty != null and c.specialty.is_affine(offer.resource) \
				and not c.specialty.is_affine(c.get_weapon())
		LevelUpSystem.apply_offer(c, offer, equip)
		c.level += 1
	return c


## prop = propuesta de dificultad {hp, dmg} (incremento por ronda); {} = valores actuales de battle.gd
func fight(stage: int, levels: Array, node_type: String = "Batalla Normal", prop: Dictionary = {}) -> Dictionary:
	GameStateManager.reset_run()
	GameStateManager.current_stage = stage
	GameStateManager.current_node_type = node_type
	GameStateManager.rolled_round = stage
	var bt = BATTLE.instantiate()
	add_child(bt)
	await get_tree().process_frame
	var grid = bt.find_child("DeploymentGrid", true, false)
	var enemies: Array = bt.get_enemies()
	if prop.get("regen", false):
		# Propuesta completa: menos enemigos (2 + r/3), nivel 1 + ronda/4 y dificultad suave
		var r0 := stage - 1
		var cells: Array[Vector2] = bt.get_enemy_cells()
		cells.shuffle()
		var count: int = randi_range(1 + int(r0 / 4.0), mini(2 + int(r0 / 3.0), 6))
		for e in enemies:
			e.free()
		enemies.clear()
		var diff := {"hp_mult": 1.0 + r0 * float(prop.hp), "dmg_mult": 1.0 + r0 * float(prop.dmg)}
		for k in count:
			var ec: TroopCard = UnitFactory.make_enemy(maxi(1, int(stage * 0.75)))
			bt.apply_difficulty(ec, diff, false)
			var en = TROOP.instantiate()
			en.team = en.Team.ENEMY
			en.setup(ec)
			bt.add_child(en)
			en.global_position = cells[k]
			enemies.append(en)
	elif not prop.is_empty():
		var r := stage - 1
		var cur: Dictionary = bt.difficulty_for(stage)
		for e in enemies:
			e.card.base_health *= (1.0 + r * float(prop.hp)) / float(cur.hp_mult)
			e.card.base_damage *= (1.0 + r * float(prop.dmg)) / float(cur.dmg_mult)
			e.refresh_from_card()
	var e_dps := 0.0
	var e_hp := 0.0
	for e in enemies:
		e_dps += float(e.stats.dps)
		e_hp += e.get_max_health()
	var e_desc: Array[String] = []
	for e in enemies:
		e_desc.append("Nv%d %s %s %dhp" % [e.card.level, e.card.get_specialty_name(), e.card.get_weapon().id, roundi(e.get_max_health())])
	var i := 0
	for lv in levels:
		var t = TROOP.instantiate()
		t.team = t.Team.PLAYER
		t.setup(player_card(lv))
		bt.add_child(t)
		t.global_position = grid.grid_cells[FRONT_CELLS[i]]
		i += 1
	await get_tree().process_frame
	await get_tree().process_frame
	var p_dps := 0.0
	var p_hp := 0.0
	for t in get_tree().get_nodes_in_group("troops"):
		if t.team == t.Team.PLAYER:
			p_dps += float(t.stats.dps)
			p_hp += t.get_max_health()
	EventBus.battle_fight_started.emit()
	var start := _clock
	while not bt.is_battle_over and _clock - start < TIMEOUT:
		await get_tree().process_frame
	var dur := _clock - start
	var won := false
	for t in get_tree().get_nodes_in_group("troops"):
		if is_instance_valid(t) and not t.is_queued_for_deletion() and t.team == t.Team.PLAYER:
			won = true
	won = won and bt.is_battle_over
	var timed_out: bool = not bt.is_battle_over
	bt.queue_free()
	for t in get_tree().get_nodes_in_group("troops"):
		t.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return {"won": won, "dur": dur, "timeout": timed_out, "enemies": e_desc, "p": Vector2(p_hp, p_dps), "e": Vector2(e_hp, e_dps)}


func scenario(label: String, stage: int, levels: Array, n: int, node_type: String = "Batalla Normal", prop: Dictionary = {}) -> void:
	var pv := Vector2.ZERO
	var ev := Vector2.ZERO
	var wins := 0
	var total := 0.0
	var mn := INF
	var mx := 0.0
	var timeouts := 0
	var sample: Array = []
	for k in n:
		var r: Dictionary = await fight(stage, levels, node_type, prop)
		pv += r.p
		ev += r.e
		if r.won:
			wins += 1
		if r.timeout:
			timeouts += 1
		total += r.dur
		mn = minf(mn, r.dur)
		mx = maxf(mx, r.dur)
		if k < 2:
			sample.append(", ".join(r.enemies))
	print("BALANCE %s | ronda %d %s | tropas %s | victorias %d/%d (%d%%) | duración media %.1f s (min %.1f, max %.1f) | timeouts %d" % [
		label, stage, node_type, str(levels), wins, n, roundi(100.0 * wins / n), total / n, mn, mx, timeouts])
	print("   jugador: vida %d · dps %.1f   |   enemigos: vida %d · dps %.1f" % [pv.x / n, pv.y / n, ev.x / n, ev.y / n])
	for sm in sample:
		print("   enemigos: ", sm)


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	Engine.physics_ticks_per_second = int(60 * SPEED)
	Engine.time_scale = SPEED
	# Ejércitos esperables con el oro de la partida (60 inicial + recompensas)
	await scenario("R5 3 tropas", 5, [3, 3, 2], 12)
	await scenario("R10 5 tropas", 10, [4, 4, 4, 4, 3], 14)
	await scenario("R7 4 tropas", 7, [4, 3, 3, 2], 10)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	print("BALANCE DONE")
