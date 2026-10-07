extends Node
## Laboratorio de IA de combate (v4): monta una batalla real (battle.tscn) con un ejército variado
## en distintas filas, la juega y mide si las tropas se amontonan y si respetan su carril.
## Capturas en _dev/shots/ai_*.png. Args: -- seed=N round=R shots=1

const BATTLE := preload("res://Scenes/Battle/battle.tscn")
const TROOP := preload("res://Scenes/Troops/troop.tscn")

var shots := true


func _card(wid: String, spec: String = "") -> TroopCard:
	var c := UnitFactory.make_recruit()
	c.items.clear()
	c.weapons.assign([GameContent.find_weapon(wid)])
	c.level = 4
	if spec != "":
		c.specialty = GameContent.find_specialty(spec)
		c.level = 5
	if wid == "cuchillo":
		c.add_item(GameContent.find_item("inyector_adrenalina")) # para ver el efecto frenético
	return c


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	seed(int(args.get("seed", "7")))
	shots = args.get("shots", "1") == "1"
	var gsm = GameStateManager
	gsm.reset_run()
	gsm.current_stage = int(args.get("round", "8"))
	gsm.current_node_type = "Batalla Élite" if args.get("elite", "0") == "1" else "Batalla Normal"
	gsm.deployed_troops_data.clear()
	var bt = BATTLE.instantiate()
	add_child(bt)
	await get_tree().process_frame
	var grid = bt.get_grid()
	# Ejército: (arma, especialidad, fila, columna) — col 4 = primera línea
	var army := [
		["cuchillo", "", 0, 4], ["escopeta", "soldado", 4, 4], ["ametralladora", "mecanico", 2, 3],
		["pistola", "medico", 1, 2], ["rifle_francotirador", "francotirador", 3, 0], ["subfusil", "comunicaciones", 2, 1],
	]
	if args.get("army", "") == "b":
		army = [["bazuca", "saboteador", 0, 1], ["fusil_asalto", "soldado", 2, 4], ["fusil_asalto", "soldado", 4, 3],
			["pistola", "medico", 2, 2], ["rifle_francotirador", "francotirador", 1, 0], ["subfusil", "comunicaciones", 3, 1]]
	var mine: Array = []
	for a in army:
		var t = TROOP.instantiate()
		t.team = t.Team.PLAYER
		t.setup(_card(a[0], a[1]))
		bt.add_child(t)
		t.global_position = grid.grid_cells[int(a[2]) * 5 + int(a[3])]
		mine.append(t)
	await get_tree().process_frame
	if args.get("mirror", "0") == "1":
		# Espejo exacto: mismo ejército para el enemigo, en las casillas reflejadas
		for e in bt.get_enemies():
			e.queue_free()
		await get_tree().process_frame
		for a in army:
			var e = TROOP.instantiate()
			e.team = e.Team.ENEMY
			e.setup(_card(a[0], a[1]))
			bt.add_child(e)
			var idx: int = int(a[2]) * 5 + int(a[3])
			e.global_position = Vector2(get_viewport().get_visible_rect().size.x - grid.grid_cells[idx].x, grid.grid_cells[idx].y)
		await get_tree().process_frame
	if shots:
		await _shot("ai_0_despliegue")
	EventBus.battle_fight_started.emit()
	var move_stats := {0: [0.0, 0, 0], 1: [0.0, 0, 0]} # distancia, muestras, muestras en marcha
	var last_pos := {}
	var last_hp := {}
	var early_deaths := [0, 0] # [muertes con >35 % de vida en el fotograma anterior, muertes totales]
	for t in get_tree().get_nodes_in_group("troops"):
		t.died.connect(func(tr):
			early_deaths[1] += 1
			var prev: float = last_hp.get(tr, 1.0)
			if prev > 0.35:
				early_deaths[0] += 1
				print("AILAB muerte con %.0f %% de vida (equipo %d): último golpe %.0f de %.0f de vida máx." % [prev * 100, tr.team, tr.last_damage, tr.get_max_health()]))
	var t0 := Time.get_ticks_msec()
	var samples := 0
	var min_pair_sum := 0.0
	var lane_dev_sum := 0.0
	var clumps := 0
	var shot_marks := [1.2, 3.0, 6.0]
	var elapsed := 0.0
	while not bt.is_battle_over and elapsed < 40.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if shots and not shot_marks.is_empty() and elapsed >= shot_marks[0]:
			await _shot("ai_%d_t%.0f" % [4 - shot_marks.size(), shot_marks[0]])
			shot_marks.pop_front()
		for t in get_tree().get_nodes_in_group("troops"):
			if not is_instance_valid(t) or t.is_dead:
				continue
			last_hp[t] = t.health / maxf(1.0, t.get_max_health())
			if last_pos.has(t):
				var d: float = t.global_position.distance_to(last_pos[t])
				move_stats[int(t.team)][0] += d
				move_stats[int(t.team)][1] += 1
				if d > 0.3:
					move_stats[int(t.team)][2] += 1
			last_pos[t] = t.global_position
		if args.get("debug", "0") == "1" and Engine.get_physics_frames() % 60 == 0:
			for t in get_tree().get_nodes_in_group("troops"):
				if is_instance_valid(t) and not t.is_dead and t.team == 1:
					var tg = t.target
					print("DBG t=%.1f %s arma=%s pos=%s ai=%s started=%s tgt=%s dist=%.0f engage=%.0f rango=%.0f vel=%s moving=%s camo=%.1f supp=%.1f speed=%.0f" % [elapsed, t.name, t.stats.weapon.id, t.global_position.round(), t.ai_enabled, t.is_battle_started,
						tg.name if tg else "-", t.global_position.distance_to(tg.global_position) if tg else -1.0, t.engage_distance(), t.get_attack_range(), t.velocity.round(), t.is_moving, t.camo_left, t.suppressed_left, t.get_effective_speed()])
		if Engine.get_physics_frames() % 15 == 0:
			var alive: Array = mine.filter(func(x): return is_instance_valid(x) and not x.is_dead)
			if alive.size() >= 2:
				samples += 1
				var mn := INF
				for i in alive.size():
					lane_dev_sum += absf(alive[i].global_position.y - alive[i].home_y)
					for j in range(i + 1, alive.size()):
						var d: float = alive[i].global_position.distance_to(alive[j].global_position)
						mn = minf(mn, d)
						if d < 30.0:
							clumps += 1
				min_pair_sum += mn
	for team in [0, 1]:
		var ms: Array = move_stats[team]
		print("AILAB equipo %s: velocidad media %.1f px/s · en marcha %.0f %% del tiempo" % ["JUGADOR" if team == 0 else "ENEMIGO",
				ms[0] / maxf(1, ms[1]) * Engine.physics_ticks_per_second, 100.0 * ms[2] / maxf(1, ms[1])])
	print("AILAB muertes con >35 %% de vida justo antes: %d de %d" % [early_deaths[0], early_deaths[1]])
	var alive_n := mine.filter(func(x): return is_instance_valid(x) and not x.is_dead).size()
	print("AILAB resultado: %s en %.1fs · vivos %d/6 · dist. mínima media entre aliados %.0f px · desvío de carril medio %.0f px · pares pegados(<30px) %d" % [
		"VICTORIA" if alive_n > 0 else "DERROTA", elapsed, alive_n,
		min_pair_sum / maxf(1, samples), lane_dev_sum / maxf(1, samples * 3), clumps])
	if shots:
		await _shot("ai_9_final")
	print("AILAB DONE (%d ms)" % (Time.get_ticks_msec() - t0))
	get_tree().quit()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_dev/shots"))
	get_viewport().get_texture().get_image().save_png("res://_dev/shots/%s.png" % file)
