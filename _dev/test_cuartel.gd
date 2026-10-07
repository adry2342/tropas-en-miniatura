extends Node
## Pruebas v5: Cuartel general (hub), bóveda de veteranos (ProfileManager), guardar tropa al vencer al
## Jefe Final, modo nuevo bloqueado, menú principal con Configuración.

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


func veteran(name: String, spec: String = "medico") -> TroopCard:
	var c := UnitFactory.make_recruit(rng)
	c.unit_name = name
	c.level = 7
	c.specialty = GameContent.find_specialty(spec)
	c.weapons.assign([GameContent.find_weapon("fusil_asalto"), GameContent.find_weapon("pistola")])
	c.equipped_weapon = 0
	c.items.assign([GameContent.find_item("chaleco_tactico"), GameContent.find_item("granada")])
	c.skills.assign([GameContent.find_skill("piel_dura"), GameContent.find_skill("piel_dura"), GameContent.find_skill("ojo_certero")])
	c.weapon_levels = {"fusil_asalto": 3}
	c.training_ranks = 2
	return c


func _ready() -> void:
	rng.seed = 55
	ProfileManager.persist = false
	SettingsManager.persist = false
	ProfileManager.clear_profile()
	await _test_profile()
	# v7: el menú principal y el Cuartel se sustituyen por el Centro de mando → _dev/test_centro_mando.gd
	await _test_victory_store()
	ProfileManager.persist = true
	ProfileManager.load_profile()
	SettingsManager.persist = true
	GameStateManager.reset_run()
	print("TEST DONE: %d fallos (%d ok)" % [fails, passes])
	get_tree().quit()


func _test_profile() -> void:
	var c := veteran("Rojas")
	var d := ProfileManager.card_to_dict(c)
	var back := ProfileManager.card_from_dict(JSON.parse_string(JSON.stringify(d)))
	check(back != null and back.unit_name == "Rojas" and back.level == 7, "serializa nombre y nivel")
	check(back.specialty == c.specialty and back.weapons.size() == 2 and back.weapons[0] == c.weapons[0], "serializa especialidad y arsenal (mismos recursos)")
	check(back.items.size() == 2 and back.skills.size() == 3 and back.has_skill("ojo_certero"), "serializa objetos y habilidades (acumulables incluidas)")
	check(back.get_weapon_level(back.weapons[0]) == 3 and back.training_ranks == 2, "serializa mejora de arma y entrenamiento")
	check(is_equal_approx(TroopStats.compute(back).max_health, TroopStats.compute(c).max_health), "mismas estadísticas tras guardar y cargar")
	check(ProfileManager.card_from_dict({"unit_name": "X", "weapons": ["no_existe"]}) == null, "un veterano sin armas válidas se descarta")

	c.pending_offers.append({"type": "skill", "resource": GameContent.find_skill("velocista")})
	check(ProfileManager.store_troop(c), "guarda un veterano")
	var stored: TroopCard = ProfileManager.vault[0]
	check(stored != c and stored.pending_offers.is_empty(), "se guarda una copia sin mejoras pendientes")
	c.level = 1
	check(stored.level == 7, "la copia no cambia si cambia la tropa de la run")
	for i in 4:
		ProfileManager.store_troop(veteran("V%d" % i))
	check(ProfileManager.vault.size() == 5 and ProfileManager.is_new_mode_unlocked(), "5 veteranos → modo nuevo desbloqueado")
	check(not ProfileManager.store_troop(veteran("Sobra")), "bóveda llena: no se añade un sexto")
	check(ProfileManager.store_troop(veteran("Nuevo"), 2) and ProfileManager.vault[2].unit_name == "Nuevo", "bóveda llena: se puede sustituir un hueco")
	ProfileManager.clear_profile()
	check(ProfileManager.vault.is_empty() and not ProfileManager.is_new_mode_unlocked(), "perfil vacío → modo bloqueado")
	check(ProfileManager.save_path() == ProfileManager.SAVE_PATH_EDITOR, "desde Godot se guarda en profile_dev.json (el .exe usa profile.json)")


func _test_victory_store() -> void:
	# Bóveda con 2 huecos libres: elegir y guardar
	ProfileManager.clear_profile()
	ProfileManager.store_troop(veteran("Antiguo"))
	GameStateManager.reset_run()
	var army: Array[TroopCard] = [veteran("Alfa", "soldado"), veteran("Bravo", "mecanico"), veteran("Charlie", "comunicaciones")]
	for c in army:
		GameStateManager.add_troop_to_army(c)
	var wins: int = ProfileManager.final_boss_wins
	var p = GAME_OVER.instantiate()
	add_child(p)
	p.setup(true)
	await frames(3)
	check(ProfileManager.final_boss_wins == wins + 1, "vencer al Jefe Final cuenta la victoria")
	check(p.candidates.size() == 3, "candidatos: las tropas del ejército (%d)" % p.candidates.size())
	check(p.restart_button.disabled and p.hub_button.disabled, "no se sale sin decidir el veterano")
	check(not p.confirm_store(), "sin elegir no se guarda")
	p.select_candidate(1)
	await frames(1)
	await shot("v5_victoria_elegir")
	check(p.confirm_store(), "guardar al elegido")
	check(ProfileManager.vault.size() == 2 and ProfileManager.vault[1].unit_name == "Bravo", "Bravo entra en el Cuartel (2/5)")
	check(not p.restart_button.disabled and not p.hub_button.disabled, "tras decidir se puede salir")
	await frames(1)
	await shot("v5_victoria_guardado")
	p.queue_free()
	await frames(2)

	# Bóveda llena: hay que elegir a quién sustituir (o no guardar)
	for i in 3:
		ProfileManager.store_troop(veteran("Viejo%d" % i))
	var p2 = GAME_OVER.instantiate()
	add_child(p2)
	p2.setup(true)
	await frames(3)
	p2.select_candidate(0)
	await frames(1)
	check(p2._replace_row.visible and not p2.confirm_store(), "bóveda llena: pide a quién sustituir")
	p2.select_replace(3)
	await frames(1)
	await shot("v5_victoria_sustituir")
	check(p2.confirm_store() and ProfileManager.vault[3].unit_name == "Alfa" and ProfileManager.vault.size() == 5, "Alfa sustituye al hueco 4")
	p2.queue_free()
	await frames(2)
	var p3 = GAME_OVER.instantiate()
	add_child(p3)
	p3.setup(true)
	await frames(2)
	p3.skip_store()
	check(p3.vault_decided and not p3.restart_button.disabled and ProfileManager.vault[0].unit_name == "Antiguo", "No guardar deja la bóveda igual")
	p3.queue_free()
	# Derrota: sin selector
	var p4 = GAME_OVER.instantiate()
	add_child(p4)
	p4.setup(false)
	await frames(2)
	check(p4.find_child("VaultPicker", true, false) == null and not p4.restart_button.disabled, "en derrota no se guarda veterano")
	p4.queue_free()
	await frames(2)
	ProfileManager.clear_profile()
