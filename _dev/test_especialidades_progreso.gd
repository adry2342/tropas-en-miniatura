extends Node
## Pruebas de la meta-progresión de especialidades: SpecialtyProgression (árboles y medallas por run),
## ProfileManager (medallas, rangos, guardado v2), mejoras solo para tropas del jugador, Jefes de Sector
## en GameStateManager, medallas en el panel de fin de partida y el panel SpecialtyTreePanel.

const SHOTS := "res://_dev/shots/"
const GAME_OVER := preload("res://Scenes/UI/game_over_panel.tscn")

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


func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	get_viewport().get_texture().get_image().save_png(SHOTS + file + ".png")
	print("CAPTURA: ", file)


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	rng.seed = 77
	ProfileManager.persist = false
	ProfileManager.clear_profile()
	SpecialtyProgression.reset_trees()
	_test_trees()
	_test_medals_formula()
	_test_unlock()
	_test_serialization()
	_test_player_only()
	_test_gsm_subbosses()
	await _test_game_over()
	await _test_panel()
	await _test_specialty_unlocks()
	await _test_victory_candidates()
	await _test_dev_buttons()
	SpecialtyProgression.reset_trees()
	ProfileManager.persist = true
	ProfileManager.load_profile()
	GameStateManager.reset_run()
	print("TEST DONE: %d fallos (%d ok)" % [fails, passes])
	get_tree().quit()


func _card(spec: String, weapon_id: String = "pistola") -> TroopCard:
	var c := TroopCard.new()
	c.unit_name = "Prueba"
	c.weapons.assign([GameContent.find_weapon(weapon_id)])
	c.specialty = GameContent.find_specialty(spec)
	return c


func _test_trees() -> void:
	var all_ok := true
	for sp in GameContent.specialties():
		var ns := SpecialtyProgression.nodes(sp.id)
		if ns.size() != SpecialtyProgression.MAX_RANK:
			all_ok = false
			print("  sin 4 nodos: ", sp.id)
			continue
		for r in range(1, SpecialtyProgression.MAX_RANK + 1):
			var n := SpecialtyProgression.node(sp.id, r)
			if SpecialtyProgression.cost(sp.id, r) <= 0 or str(n.get("name", "")) == "" or not n.get("modifiers") is Dictionary or not n.get("effects") is Dictionary:
				all_ok = false
	check(all_ok, "las 7 especialidades tienen 4 nodos con nombre, coste, modifiers y effects")
	check(SpecialtyProgression.cost("soldado", 1) == 3 and SpecialtyProgression.cost("soldado", 2) == 5 \
			and SpecialtyProgression.cost("soldado", 3) == 8 and SpecialtyProgression.cost("soldado", 4) == 12, "costes por defecto 3/5/8/12")
	check(SpecialtyProgression.node("soldado", 0).is_empty() and SpecialtyProgression.node("soldado", 5).is_empty() \
			and SpecialtyProgression.nodes("no_existe").is_empty(), "rangos fuera de 1..4 o especialidad desconocida → vacío")
	check(str(SpecialtyProgression.node("medico", 1).description).contains("pendiente"), "texto provisional deja claro que está pendiente")
	var keys_ok := true
	for sp_id in SpecialtyProgression.DEFAULT_TREES:
		for n in SpecialtyProgression.DEFAULT_TREES[sp_id]:
			for k in n.modifiers:
				if not k in TroopStats.MODIFIER_KEYS:
					keys_ok = false
	check(keys_ok, "los modificadores por defecto solo usan claves de TroopStats.MODIFIER_KEYS")
	# Suma y fusión
	SpecialtyProgression.trees["soldado"][0]["modifiers"] = {"health_pct": 0.1}
	SpecialtyProgression.trees["soldado"][1]["modifiers"] = {"health_pct": 0.2, "accuracy": 0.05}
	SpecialtyProgression.trees["soldado"][1]["effects"] = {"prueba": {"x": 1.0}}
	SpecialtyProgression.trees["soldado"][2]["effects"] = {"prueba": {"x": 3.0, "y": 2.0}}
	var m := SpecialtyProgression.modifiers_for("soldado", 2)
	check(is_equal_approx(m.health_pct, 0.3) and is_equal_approx(m.accuracy, 0.05), "modifiers_for suma los nodos 1..rango")
	check(SpecialtyProgression.modifiers_for("soldado", 1).size() == 1 and SpecialtyProgression.modifiers_for("soldado", 0).is_empty(), "rango 1 solo el nodo 1; rango 0 nada")
	var e := SpecialtyProgression.effects_for("soldado", 3)
	check(e.has("prueba") and is_equal_approx(e.prueba.x, 3.0) and is_equal_approx(e.prueba.y, 2.0), "effects_for fusiona (mayor de cada parámetro)")
	SpecialtyProgression.reset_trees()
	check(SpecialtyProgression.modifiers_for("soldado", 4).is_empty(), "reset_trees restaura los árboles por defecto")


func _test_medals_formula() -> void:
	check(SpecialtyProgression.medals_for_run(0, 0, false) == 0, "medallas: run vacía = 0")
	check(SpecialtyProgression.medals_for_run(4, 0, false) == 0, "medallas: 4 rondas = 0")
	check(SpecialtyProgression.medals_for_run(5, 0, false) == 1, "medallas: 5 rondas = 1")
	check(SpecialtyProgression.medals_for_run(14, 1, false) == 4, "medallas: 14 rondas + 1 Jefe de Sector = 2 + 2")
	check(SpecialtyProgression.medals_for_run(23, 2, true) == 13, "medallas: 23 rondas + 2 sectores + Jefe Final = 4 + 4 + 5")


func _test_unlock() -> void:
	ProfileManager.clear_profile()
	var emitted := [0]
	var cb := func(): emitted[0] += 1
	ProfileManager.progress_changed.connect(cb)
	check(ProfileManager.get_rank("medico") == 0 and ProfileManager.next_cost("medico") == 3, "rango inicial 0, siguiente cuesta 3")
	check(not ProfileManager.can_unlock_next("medico") and not ProfileManager.unlock_next("medico"), "sin medallas no se desbloquea")
	ProfileManager.add_medals(0)
	ProfileManager.add_medals(-5)
	check(ProfileManager.medals == 0, "add_medals ignora 0 y negativos")
	ProfileManager.add_medals(10, "prueba")
	check(ProfileManager.medals == 10 and emitted[0] >= 1, "add_medals suma y emite progress_changed")
	check(ProfileManager.unlock_next("medico") and ProfileManager.get_rank("medico") == 1 and ProfileManager.medals == 7, "desbloquear rango 1 gasta 3")
	check(ProfileManager.unlock_next("medico") and ProfileManager.get_rank("medico") == 2 and ProfileManager.medals == 2, "rango 2 gasta 5")
	check(not ProfileManager.unlock_next("medico") and ProfileManager.get_rank("medico") == 2 and ProfileManager.medals == 2, "no alcanza para el rango 3 (8): no cambia nada")
	ProfileManager.add_medals(100)
	check(ProfileManager.unlock_next("medico") and ProfileManager.unlock_next("medico") and ProfileManager.get_rank("medico") == 4, "llega a MAX_RANK")
	var before: int = ProfileManager.medals
	check(not ProfileManager.can_unlock_next("medico") and not ProfileManager.unlock_next("medico") and ProfileManager.medals == before \
			and ProfileManager.next_cost("medico") == 0, "al máximo no se sube más ni se gasta")
	check(not ProfileManager.unlock_next("no_existe"), "especialidad desconocida no se desbloquea")
	ProfileManager.progress_changed.disconnect(cb)
	ProfileManager.clear_profile()
	check(ProfileManager.medals == 0 and ProfileManager.get_rank("medico") == 0, "clear_profile borra medallas y rangos")


func _test_serialization() -> void:
	ProfileManager.clear_profile()
	ProfileManager.add_medals(30)
	ProfileManager.unlock_next("francotirador")
	ProfileManager.unlock_next("francotirador")
	ProfileManager.unlock_next("saboteador")
	var d := ProfileManager.progress_to_dict()
	var json: Dictionary = JSON.parse_string(JSON.stringify(d))
	ProfileManager.clear_profile()
	ProfileManager.apply_progress_dict(json)
	check(ProfileManager.medals == 30 - 3 - 5 - 3, "medallas sobreviven al guardado (JSON)")
	check(ProfileManager.get_rank("francotirador") == 2 and ProfileManager.get_rank("saboteador") == 1 and ProfileManager.get_rank("soldado") == 0, "rangos sobreviven al guardado (JSON)")
	# Perfil v1 (sin claves nuevas) y valores raros
	ProfileManager.apply_progress_dict({"version": 1, "final_boss_wins": 3, "vault": []})
	check(ProfileManager.medals == 0 and ProfileManager.specialty_ranks.is_empty(), "perfil v1 se carga con 0 medallas y sin rangos")
	ProfileManager.apply_progress_dict({"medals": -4, "specialty_ranks": {"granadero": 2, "inventada": 3, "soldado": 99}})
	check(ProfileManager.medals == 0 and ProfileManager.get_rank("saboteador") == 2 and not ProfileManager.specialty_ranks.has("inventada") \
			and ProfileManager.get_rank("soldado") == SpecialtyProgression.MAX_RANK, "ids antiguos se traducen, desconocidos se ignoran, rangos acotados")
	check(ProfileManager.SAVE_VERSION == 2, "SAVE_VERSION = 2")
	# La bóveda sigue funcionando con is_enemy
	var c := _card("medico", "fusil_asalto")
	c.is_enemy = true
	check(c.duplicate_card().is_enemy, "duplicate_card copia is_enemy")
	var back := ProfileManager.card_from_dict(JSON.parse_string(JSON.stringify(ProfileManager.card_to_dict(c))))
	check(back != null and back.specialty == c.specialty and not back.is_enemy, "card_to_dict/card_from_dict siguen funcionando (veterano = tropa del jugador)")
	ProfileManager.clear_profile()


func _test_player_only() -> void:
	ProfileManager.clear_profile()
	var player := _card("soldado")
	var enemy := player.duplicate_card()
	enemy.is_enemy = true
	var h0: float = TroopStats.compute(player).max_health
	check(is_equal_approx(TroopStats.compute(enemy).max_health, h0), "sin rangos jugador y enemigo iguales")
	SpecialtyProgression.trees["soldado"][0]["modifiers"] = {"health_pct": 0.5}
	SpecialtyProgression.trees["soldado"][0]["effects"] = {"efecto_prueba": {"v": 2.0}}
	check(is_equal_approx(TroopStats.compute(player).max_health, h0), "rango 0: el árbol aún no aplica")
	ProfileManager.add_medals(3)
	check(ProfileManager.unlock_next("soldado"), "desbloquea Soldado rango 1")
	var hp: float = TroopStats.compute(player).max_health
	check(is_equal_approx(hp, h0 * 1.5), "rango 1 con health_pct 0.5: vida del jugador ×1.5 (%.1f → %.1f)" % [h0, hp])
	check(is_equal_approx(TroopStats.compute(enemy).max_health, h0), "el enemigo con la misma especialidad NO mejora")
	check(Effects.collect(player).has("efecto_prueba") and not Effects.collect(enemy).has("efecto_prueba"), "efectos del árbol solo para el jugador")
	var other := _card("medico")
	check(not Effects.collect(other).has("efecto_prueba") and is_equal_approx(TroopStats.compute(other).max_health, TroopStats.compute(_card("medico")).max_health), "otras especialidades no se ven afectadas")
	var recruit := TroopCard.new()
	recruit.weapons.assign([GameContent.find_weapon("pistola")])
	check(TroopStats.compute(recruit).max_health > 0.0, "un Recluta (sin especialidad) no se ve afectado")
	var en := UnitFactory.make_enemy(8, false, false, rng)
	check(en.is_enemy, "UnitFactory.make_enemy marca is_enemy")
	check(not UnitFactory.make_recruit(rng).is_enemy, "los reclutas son del jugador")
	SpecialtyProgression.reset_trees()
	ProfileManager.clear_profile()


func _test_gsm_subbosses() -> void:
	GameStateManager.reset_run()
	check(GameStateManager.subbosses_defeated == 0, "subbosses_defeated empieza en 0")
	GameStateManager.apply_victory_rewards(GameStateManager.NORMAL_TYPE)
	check(GameStateManager.subbosses_defeated == 0, "ganar una batalla normal no cuenta")
	GameStateManager.apply_victory_rewards(GameStateManager.SUBBOSS_TYPE)
	GameStateManager.apply_victory_rewards(GameStateManager.SUBBOSS_TYPE)
	check(GameStateManager.subbosses_defeated == 2, "cada victoria contra un Jefe de Sector suma 1")
	GameStateManager.reset_run()
	check(GameStateManager.subbosses_defeated == 0, "reset_run lo reinicia")


func _test_game_over() -> void:
	# Derrota en la ronda 12 con 1 Jefe de Sector: 11 rondas ganadas → 2 + 2 = 4
	ProfileManager.clear_profile()
	GameStateManager.reset_run()
	GameStateManager.current_stage = 12
	GameStateManager.subbosses_defeated = 1
	var p = GAME_OVER.instantiate()
	add_child(p)
	p.setup(false)
	await frames(3)
	check(p.medals_awarded == 4 and ProfileManager.medals == 4, "derrota en ronda 12 con 1 sector: +4 medallas (%d)" % p.medals_awarded)
	check(p.medals_label != null and p.medals_label.is_visible_in_tree() and p.medals_label.text.contains("+4") and p.medals_label.text.contains("total 4"), "derrota: muestra la línea de medallas (%s)" % (p.medals_label.text if p.medals_label else "?"))
	p.setup(false)
	await frames(1)
	check(ProfileManager.medals == 4, "las medallas se dan una sola vez aunque se repita setup")
	check(p.medals_label.get_index() == p.title_label.get_index() + 1, "la línea va justo debajo del título")
	check(_inside_viewport(p.get_node("Control/Panel")), "panel de derrota dentro de la pantalla")
	await shot("prog_fin_partida_derrota")
	p.queue_free()
	await frames(2)

	# Derrota temprana: +0 se muestra igualmente
	GameStateManager.reset_run()
	GameStateManager.current_stage = 3
	var p0 = GAME_OVER.instantiate()
	add_child(p0)
	p0.setup(false)
	await frames(2)
	check(p0.medals_awarded == 0 and p0.medals_label.text.contains("+0") and ProfileManager.medals == 4, "derrota en la ronda 3: se muestra +0")
	p0.queue_free()
	await frames(2)

	# Victoria (Jefe Final) en la ronda 23 con 2 sectores: 23 rondas → 4 + 4 + 5 = 13
	GameStateManager.reset_run()
	GameStateManager.current_stage = 23
	GameStateManager.subbosses_defeated = 2
	for i in 4:
		var c := UnitFactory.make_recruit(rng)
		c.level = 6
		c.specialty = GameContent.specialties()[i]
		GameStateManager.add_troop_to_army(c)
	var pv = GAME_OVER.instantiate()
	add_child(pv)
	pv.setup(true)
	await frames(3)
	check(pv.medals_awarded == 13 and ProfileManager.medals == 17, "victoria ronda 23 con 2 sectores: +13 (%d, total %d)" % [pv.medals_awarded, ProfileManager.medals])
	check(pv.medals_label.text.contains("+13") and pv.medals_label.text.contains("total 17"), "victoria: muestra la línea de medallas")
	check(pv.find_child("VaultPicker", true, false) != null and pv.medals_label.get_index() == pv.title_label.get_index() + 1, "victoria: medallas bajo el título y encima del selector de veterano")
	check(_inside_viewport(pv.get_node("Control/Panel")), "panel de victoria dentro de la pantalla")
	pv.select_candidate(1)
	await frames(2)
	await shot("prog_fin_partida")
	pv.queue_free()
	await frames(2)
	GameStateManager.reset_run()


func _inside_viewport(c: Control) -> bool:
	var vr := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var r := c.get_global_rect()
	return vr.encloses(r)


func _test_panel() -> void:
	ProfileManager.clear_profile()
	var panel := SpecialtyTreePanel.new()
	var closed_count := [0]
	panel.closed.connect(func(): closed_count[0] += 1)
	add_child(panel)
	await frames(3)
	var list: Node = panel.find_child("SpecialtyList", true, false)
	check(list != null and list.get_child_count() == 7, "el panel lista las 7 especialidades")
	check(panel.selected_id == "soldado", "por defecto muestra la primera (Soldado)")
	panel.select_specialty("medico")
	await frames(2)
	check(panel.selected_id == "medico", "seleccionar cambia selected_id")
	(list.get_child(5) as Button).pressed.emit()
	await frames(2)
	check(panel.selected_id == "francotirador", "pulsar en la lista selecciona (Francotirador)")
	var rows: Array = panel.get_node_rows()
	check(rows.size() == SpecialtyProgression.MAX_RANK + 1 and rows[0].get_meta("rank") == 0 and rows[0].get_meta("state") == "base", "5 filas, la [0] es la especialidad base")
	check(rows[0].global_position.y > rows[4].global_position.y, "árbol vertical: el rango 0 abajo y el 4 arriba")
	check(rows[1].get_meta("state") == "next" and rows[2].get_meta("state") == "locked", "sin rangos: el 1 es el siguiente y el resto bloqueados")
	var ub: Button = panel.get_unlock_button()
	check(ub != null and ub.disabled and ub.size.y >= 48 and ub.text.contains("3"), "sin medallas: botón Desbloquear (🏅 3) desactivado y ≥ 48 px")
	check(rows[1].find_child("ReasonLabel", true, false) != null, "se explica por qué no se puede (faltan medallas)")
	check(not panel.unlock_selected(), "unlock_selected falla sin medallas")
	ProfileManager.add_medals(12)
	await frames(2)
	check((panel.find_child("MedalsLabel", true, false) as Label).text == "🏅 12", "el contador de medallas se actualiza (progress_changed)")
	ub = panel.get_unlock_button()
	check(ub != null and not ub.disabled, "con medallas el botón se activa")
	ub.pressed.emit()
	await frames(2)
	rows = panel.get_node_rows()
	check(ProfileManager.get_rank("francotirador") == 1 and ProfileManager.medals == 9, "el botón desbloquea el rango 1 (gasta 3)")
	check(rows[1].get_meta("state") == "unlocked" and rows[2].get_meta("state") == "next" and rows[3].get_meta("state") == "locked", "las filas se actualizan tras desbloquear")
	var rl: Label = list.get_child(5).find_child("RankLabel", true, false)
	check(rl.text == "1/4", "la lista muestra el rango (1/4)")
	check(panel.unlock_selected() and ProfileManager.get_rank("francotirador") == 2 and ProfileManager.medals == 4, "unlock_selected sube al rango 2")
	# Más progreso para la captura
	ProfileManager.add_medals(30)
	ProfileManager.unlock_next("medico")
	ProfileManager.unlock_next("medico")
	ProfileManager.unlock_next("medico")
	ProfileManager.unlock_next("medico")
	ProfileManager.unlock_next("soldado")
	ProfileManager.medals = 4
	panel.refresh()
	await frames(3)
	var pr: Control = panel.find_child("Panel", true, false)
	check(_inside_viewport(pr), "el panel cabe en 1152×648 (%s)" % str(pr.get_global_rect()))
	var all_in := true
	for r in panel.get_node_rows():
		if not pr.get_global_rect().encloses((r as Control).get_global_rect()):
			all_in = false
	check(all_in, "todas las filas del árbol caben dentro del panel")
	await shot("prog_arbol")
	panel.select_specialty("medico")
	await frames(2)
	check(panel.get_unlock_button() == null and panel.get_node_rows()[4].get_meta("state") == "unlocked", "al máximo no hay botón y todo está encendido")
	await shot("prog_arbol_completo")
	# Esc cierra
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	get_viewport().push_input(ev)
	await frames(2)
	check(closed_count[0] == 1 and (not is_instance_valid(panel) or panel.is_queued_for_deletion()), "Esc cierra el panel y emite closed")
	await frames(2)
	# ✕ cierra
	var p2 := SpecialtyTreePanel.new()
	var c2 := [0]
	p2.closed.connect(func(): c2[0] += 1)
	add_child(p2)
	await frames(2)
	(p2.find_child("CloseButton", true, false) as Button).pressed.emit()
	await frames(2)
	check(c2[0] == 1 and not is_instance_valid(p2), "✕ cierra el panel y emite closed")
	ProfileManager.clear_profile()


## v7.1: en un perfil nuevo solo el Soldado; cada hito desbloquea otra especialidad.
func _test_specialty_unlocks() -> void:
	ProfileManager.all_specialties_unlocked = false
	ProfileManager.clear_profile()
	var avail := SpecialtyProgression.available_specialties()
	check(avail.size() == 1 and avail[0].id == "soldado", "perfil nuevo: solo el Soldado está disponible")
	check(SpecialtyProgression.UNLOCKS.size() == GameContent.specialties().size(), "cada especialidad tiene su hito de desbloqueo")
	# Elección en Nv. 5 y reclutas de la Intendencia: solo desbloqueadas (los enemigos, todas)
	var c := UnitFactory.make_recruit(rng)
	c.level = TroopCard.SPECIALTY_LEVEL - 1
	var only_soldier := true
	for i in 30:
		for o in LevelUpSystem.roll_offers(c, rng):
			if o.type == "specialty" and o.resource.id != "soldado":
				only_soldier = false
	check(only_soldier, "al subir a Nv. 5 solo se ofrece el Soldado")
	var rec_ok := true
	for i in 300:
		var r := UnitFactory.make_recruit(rng, true)
		if r.specialty and r.specialty.id != "soldado":
			rec_ok = false
	check(rec_ok, "la Intendencia solo trae reclutas especializados en especialidades desbloqueadas")
	var enemy_specs := {}
	for i in 60:
		var e := UnitFactory.make_enemy(12, false, false, rng)
		if e.specialty:
			enemy_specs[e.specialty.id] = true
	check(enemy_specs.size() > 1, "los enemigos siguen usando todas las especialidades (%d distintas)" % enemy_specs.size())
	check(not CodexPanel.is_unlocked(GameContent.find_specialty("saboteador")) and CodexPanel.is_unlocked(GameContent.find_specialty("soldado")), "el Códice oculta las especialidades bloqueadas")
	check(not ProfileManager.can_unlock_next("francotirador"), "no se compran mejoras de una especialidad bloqueada")
	# Hitos: llegar al Jefe de Sector 1 y 2, vencer al Jefe Final
	GameStateManager.reset_run()
	GameStateManager.current_stage = 10
	GameStateManager.rolled_round = 0
	GameStateManager.roll_round_type()
	check(not ProfileManager.is_specialty_unlocked("medico") and ProfileManager.is_specialty_claimable("medico") and ProfileManager.recent_unlocks.size() == 1,
			"v7.2: llegar al 1.er Jefe de Sector deja el Doctor LISTO, pero no desbloqueado en esta run")
	var c5 := UnitFactory.make_recruit(rng)
	c5.level = TroopCard.SPECIALTY_LEVEL - 1
	var still_soldier := true
	for i in 30:
		for o in LevelUpSystem.roll_offers(c5, rng):
			if o.type == "specialty" and o.resource.id != "soldado":
				still_soldier = false
	check(still_soldier, "v7.2: en la misma run el Doctor aún no sale al subir a Nv. 5")
	GameStateManager.rolled_round = 0
	GameStateManager.roll_round_type()
	check(ProfileManager.recent_unlocks.size() == 1 and ProfileManager.milestones.count("sector_1") == 1, "el mismo hito no se repite")
	GameStateManager.current_stage = 20
	GameStateManager.roll_round_type()
	check(ProfileManager.is_specialty_claimable("comunicaciones"), "llegar al 2.º Jefe de Sector deja listo el Radioperador")
	GameStateManager.current_stage = 30
	GameStateManager.roll_round_type()
	check(ProfileManager.is_specialty_claimable("francotirador"), "llegar al 3.er Jefe de Sector deja listo el Francotirador")
	# El panel de fin de partida anuncia las de esta run
	var p = preload("res://Scenes/UI/game_over_panel.tscn").instantiate()
	add_child(p)
	p.setup(true) # victoria: Jefe Final → Infiltrado
	await frames(3)
	check(ProfileManager.is_specialty_claimable("infiltrado") and not ProfileManager.is_specialty_unlocked("infiltrado"), "vencer al Jefe Final deja listo el Infiltrado")
	var names: Array = p.unlocked_specialties.map(func(sp): return sp.id)
	check(names.size() == 4 and p.medals_label.text.contains("Centro de mando") and p.medals_label.text.contains("Infiltrado"), "el fin de partida anuncia las 4 listas para desbloquear (%s)" % p.medals_label.text)
	check(ProfileManager.recent_unlocks.is_empty(), "y se anuncian una sola vez")
	await shot("prog_fin_desbloqueos")
	p.queue_free()
	await frames(2)
	check(not ProfileManager.is_specialty_unlocked("mecanico") and not ProfileManager.is_specialty_unlocked("saboteador"), "Mecánico y Saboteador siguen bloqueados (sector 4 y Modo Infinito)")
	# Árbol: especialidad bloqueada se ve sellada
	var panel := SpecialtyTreePanel.new()
	add_child(panel)
	await frames(3)
	panel.select_specialty("saboteador")
	await frames(2)
	var rows: Array = panel.get_node_rows()
	check(rows[0].get_meta("state") == "sealed" and panel.get_unlock_button() == null and panel.get_claim_button() == null, "árbol: especialidad bloqueada sellada y sin botones")
	await shot("prog_arbol_bloqueada")
	panel.select_specialty("medico")
	await frames(2)
	check(panel.get_node_rows()[0].get_meta("state") == "claimable" and panel.get_claim_button() != null, "árbol: el Doctor (hito conseguido) tiene botón Desbloquear")
	await shot("prog_arbol_lista")
	panel.get_claim_button().pressed.emit()
	await frames(2)
	check(ProfileManager.is_specialty_unlocked("medico") and panel.get_node_rows()[0].get_meta("state") == "base", "pulsar Desbloquear en el terminal desbloquea el Doctor")
	check(SpecialtyProgression.available_specialties().size() == 2, "ya hay 2 especialidades disponibles para las runs")
	check(not ProfileManager.claim_specialty("saboteador"), "no se puede desbloquear sin el hito")
	panel.close()
	await frames(2)
	GameStateManager.reset_run()
	ProfileManager.clear_profile()
	ProfileManager.all_specialties_unlocked = true


## v7.2: al vencer al Jefe Final se puede guardar a CUALQUIER soldado del ejército (también los caídos).
func _test_victory_candidates() -> void:
	GameStateManager.reset_run()
	var all_cards: Array[TroopCard] = []
	for i in 6:
		var c := UnitFactory.make_recruit(rng)
		c.unit_name = "S%d" % i
		all_cards.append(c)
	# 4 desplegados al empezar el combate (2 caen) + 2 en la reserva
	for i in 4:
		GameStateManager.deployed_troops_data.append({"card": all_cards[i], "position": Vector2(100 + i * 50, 200)})
	GameStateManager.add_troop_to_army(all_cards[4])
	GameStateManager.add_troop_to_army(all_cards[5])
	var army := GameStateManager.get_army_cards()
	check(army.size() == 6 and all_cards.all(func(c): return c in army), "candidatos: los 6 soldados (desplegados, caídos y reserva) (%d)" % army.size())
	var p = GAME_OVER.instantiate()
	add_child(p)
	p.setup(true)
	await frames(3)
	check(p.candidates.size() == 6 and p._cand_row.get_child_count() == 6, "el panel de victoria muestra los 6")
	await shot("prog_victoria_6")
	p.queue_free()
	await frames(2)
	GameStateManager.reset_run()


## v7.2: botones provisionales de Configuración (desbloquear todo / borrar partida).
func _test_dev_buttons() -> void:
	ProfileManager.all_specialties_unlocked = false
	ProfileManager.test_mode = true # el botón Borrar no debe tocar el perfil real del disco
	ProfileManager.clear_profile()
	var sp = SettingsPanel.new()
	add_child(sp)
	await frames(3)
	check(sp.unlock_all_button != null and sp.delete_save_button != null and sp.no_save_check != null, "Configuración: botones de pruebas")
	sp.unlock_all_button.pressed.emit()
	await frames(1)
	check(SpecialtyProgression.available_specialties().size() == 7 and ProfileManager.is_new_mode_unlocked() and ProfileManager.medals >= 999, "Desbloquear todo: 7 especialidades, hangar y medallas")
	await shot("prog_config_pruebas")
	sp.delete_save_button.pressed.emit()
	await frames(1)
	check(ProfileManager.medals >= 999, "Borrar: la primera pulsación solo pide confirmar")
	sp.delete_save_button.pressed.emit()
	await frames(1)
	check(ProfileManager.medals == 0 and SpecialtyProgression.available_specialties().size() == 1 and not ProfileManager.is_new_mode_unlocked(), "Borrar: la segunda pulsación deja el perfil como nuevo")
	sp.no_save_check.button_pressed = false
	check(ProfileManager.persist, "desmarcar 'No guardar' vuelve a guardar")
	sp.no_save_check.button_pressed = true # (sin escrituras entre medias)
	check(not ProfileManager.persist, "marcar 'No guardar' deja de escribir en disco")
	sp.close()
	await frames(2)
	ProfileManager.all_specialties_unlocked = true
