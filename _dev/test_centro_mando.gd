extends Node
## Pruebas v7: Centro de mando (pantalla principal). Objetos clicables por silueta, brillo, tubos
## criogénicos con los veteranos, accesos (run, Códice, especialidades, Configuración, hangar),
## escalado a pantallas de PC y móvil, eliminar veterano desde un tubo.

const SHOTS := "res://_dev/shots/"
const CC := preload("res://Scenes/UI/command_center.tscn")

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


func veteran(vname: String, spec: String) -> TroopCard:
	var c := UnitFactory.make_recruit(rng)
	c.unit_name = vname
	c.level = 6
	c.specialty = GameContent.find_specialty(spec)
	return c


## Punto de la sala (1920×1080) → coordenadas locales de un hotspot.
func local_of(h: Control, room_pt: Vector2) -> Vector2:
	return room_pt - h.position


func _ready() -> void:
	rng.seed = 77
	ProfileManager.persist = false
	ProfileManager.clear_profile()
	await _test_scene()
	await _test_actions()
	await _test_tubes()
	await _test_scaling()
	ProfileManager.persist = true
	ProfileManager.load_profile()
	GameStateManager.reset_run()
	print("TEST DONE: %d fallos (%d ok)" % [fails, passes])
	get_tree().quit()


func _test_scene() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://Scenes/UI/main_menu.tscn", "v7.1: el juego empieza en el menú principal (Jugar · Configuración · Salir)")
	var menu = load("res://Scenes/UI/main_menu.tscn").instantiate()
	check(menu.hub_scene_path == "res://Scenes/UI/command_center.tscn", "Jugar lleva al Centro de mando")
	menu.free()
	ProfileManager.store_troop(veteran("Rojas", "medico"))
	ProfileManager.store_troop(veteran("Ibarra", "francotirador"))
	ProfileManager.add_medals(7)
	var cc = CC.instantiate()
	cc.change_scene_enabled = false
	add_child(cc)
	await frames(4)
	for key in ["war_table", "specialty_terminal", "hangar_door", "archive", "radio_station"]:
		check(cc.hotspots.has(key) and cc.hotspots[key] is CCHotspot, "objeto clicable: %s" % key)
	check(cc.tubes.size() == 5, "5 tubos criogénicos")
	# La sala cabe entera en la pantalla de prueba (1152×648)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var r: Rect2 = Rect2(cc.room.position, cc.room.size * cc.room.scale)
	check(r.size.x <= vp.x + 1.0 and r.size.y <= vp.y + 1.0 and (r.size.x >= vp.x - 1.0 or r.size.y >= vp.y - 1.0), "la sala se escala para caber en %dx%d (%.2f)" % [vp.x, vp.y, cc.room.scale.x])
	# Silueta: centro del holomapa sí; esquina transparente no
	var table: CCHotspot = cc.hotspots.war_table
	check(table.hits(local_of(table, Vector2(1000, 650))), "la mesa responde sobre el holomapa")
	check(not table.hits(Vector2(4, 4)), "la mesa NO responde en su esquina transparente (máscara por silueta)")
	var door: CCHotspot = cc.hotspots.hangar_door
	check(door.hits(local_of(door, Vector2(1700, 300))) and not door.hits(Vector2(3, door.size.y - 3)), "el hangar responde sobre la puerta, no en el borde vacío")
	# Brillo al pasar el ratón
	table.mouse_entered.emit()
	await get_tree().create_timer(0.3).timeout
	check(table.is_glowing(), "al pasar el ratón la mesa brilla")
	await shot("cc_hover_mesa")
	table.mouse_exited.emit()
	await get_tree().create_timer(0.3).timeout
	check(not table.is_glowing(), "al salir deja de brillar")
	# HUD y rótulos
	check(cc._hud_label.text.contains("7") and cc._hud_label.text.contains("Medallas"), "HUD con las medallas (%s)" % cc._hud_label.text)
	check(cc.hotspots.hangar_door.tooltip_text.contains("2/5"), "hangar bloqueado con progreso 2/5 (tooltip)")
	var overlay_labels: Array = cc.room.get_children().filter(func(n): return n is Label)
	check(overlay_labels.is_empty(), "v7.1: sin rótulos de texto encima del arte (%d)" % overlay_labels.size())
	check(cc.back_button.visible and cc.back_button.text.contains("Menú principal"), "botón ← Menú principal")
	await shot("cc_sala")
	cc.queue_free()
	await frames(2)


func _test_actions() -> void:
	var cc = CC.instantiate()
	cc.change_scene_enabled = false
	add_child(cc)
	await frames(3)
	cc.hotspots.archive.pressed.emit()
	await frames(2)
	check(cc.codex != null and is_instance_valid(cc.codex), "Archivo → abre el Códice")
	cc.codex.close()
	await frames(2)
	cc.hotspots.radio_station.pressed.emit()
	await frames(2)
	check(cc.settings != null and cc.settings.find_child("WindowModeOption", true, false) != null, "Radio → abre la Configuración")
	cc.settings.close()
	await frames(2)
	cc.hotspots.specialty_terminal.pressed.emit()
	await frames(3)
	check(cc.tree_panel != null and is_instance_valid(cc.tree_panel), "Terminal → abre el árbol de especialidades")
	await shot("cc_arbol")
	cc.tree_panel.close()
	await frames(2)
	check(cc.tree_panel == null, "el árbol se cierra")
	cc.hotspots.hangar_door.pressed.emit()
	await frames(1)
	check(cc._toast.text.contains("bloqueado") and not cc.is_confirm_open(), "Hangar bloqueado → avisa, sin confirmación (%s)" % cc._toast.text)
	GameStateManager.coins = 50
	cc.hotspots.war_table.pressed.emit()
	await frames(2)
	check(cc.is_confirm_open() and GameStateManager.coins == 50, "Mesa táctica → pide confirmación antes de empezar")
	await shot("cc_confirmar")
	cc._confirm_no.pressed.emit()
	await frames(1)
	check(not cc.is_confirm_open() and GameStateManager.coins == 50, "Cancelar no empieza la run")
	cc.hotspots.war_table.pressed.emit()
	await frames(1)
	cc._confirm_yes.pressed.emit()
	await frames(1)
	check(GameStateManager.coins == 0 and GameStateManager.current_stage == 1, "confirmar → empieza una run nueva")
	cc.queue_free()
	await frames(2)


func _test_tubes() -> void:
	var cc = CC.instantiate()
	cc.change_scene_enabled = false
	add_child(cc)
	await frames(3)
	check(cc.tube_sprites[0].texture != null and cc.tube_sprites[1].texture != null and cc.tube_sprites[2].texture == null, "los veteranos se ven dentro de sus tubos (2 ocupados, 3 vacíos)")
	check(cc.tubes[0].tooltip_text.begins_with("Rojas") and cc.tubes[3].tooltip_text.contains("vacío"), "tooltips de los tubos")
	cc.tubes[1].pressed.emit()
	await frames(2)
	var dp = cc.detail_panel
	check(dp.visible and dp.vault_mode and dp.card == ProfileManager.vault[1], "clic en un tubo → ficha del veterano (modo Cuartel)")
	await shot("cc_ficha_veterano")
	# Eliminar desde la ficha: mantener + confirmar
	var del: HoldButton = dp._delete_button
	del.button_down.emit()
	await get_tree().create_timer(dp.DELETE_HOLD_TIME + 0.3).timeout
	check(dp.is_remove_confirm_open(), "mantener pulsado Eliminar pide confirmación")
	dp._confirm_yes.pressed.emit()
	await frames(3)
	check(ProfileManager.vault.size() == 1 and cc.tube_sprites[1].texture == null, "al confirmar el tubo se vacía")
	cc.tubes[4].pressed.emit()
	await frames(1)
	check(not dp.visible and cc._toast.text.contains("vacío"), "tubo vacío → aviso, sin ficha")
	# Con 5 veteranos el hangar se desbloquea
	for i in 4:
		ProfileManager.store_troop(veteran("V%d" % i, ["soldado", "mecanico", "infiltrado", "saboteador"][i]))
	await frames(2)
	check(not cc.hotspots.hangar_door.tooltip_text.contains("bloqueado") and cc.tube_sprites[4].texture != null, "5 veteranos → hangar desbloqueado y tubos llenos")
	cc.hotspots.hangar_door.pressed.emit()
	await frames(1)
	check(cc.is_confirm_open() and cc._confirm_title.text.contains("Modo Infinito"), "Hangar desbloqueado → pide confirmación para el Modo Infinito")
	cc._confirm_yes.pressed.emit()
	await frames(1)
	check(cc._toast.text.contains("próximamente"), "confirmar → (el modo aún no existe) aviso")
	await shot("cc_tubos_llenos")
	cc.queue_free()
	await frames(2)


func _test_scaling() -> void:
	# Pantalla de móvil apaisado (20:9) y una de PC ultrapanorámica
	for sz in [Vector2(2400, 1080), Vector2(1280, 1024)]:
		var cc = CC.instantiate()
		cc.change_scene_enabled = false
		add_child(cc)
		await frames(2)
		cc.set_anchors_preset(Control.PRESET_TOP_LEFT)
		cc.size = sz
		await frames(2)
		var r: Rect2 = Rect2(cc.room.position, cc.room.size * cc.room.scale)
		var inside: bool = r.position.x >= -0.5 and r.position.y >= -0.5 and r.end.x <= sz.x + 0.5 and r.end.y <= sz.y + 0.5
		check(inside and (absf(r.size.x - sz.x) < 1.0 or absf(r.size.y - sz.y) < 1.0), "pantalla %dx%d: la sala entera visible y centrada" % [sz.x, sz.y])
		cc.queue_free()
		await frames(2)
