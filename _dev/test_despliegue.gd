extends Node
## Pruebas de la cuadrícula de despliegue rediseñada (5x5, zona enemiga espejo, resaltado y
## recolocación al cambiar el tamaño de la ventana). Escribe capturas en _dev/shots/.

const BATTLE := preload("res://Scenes/Battle/battle.tscn")
const TROOP := preload("res://Scenes/Troops/troop.tscn")

var fails := 0
var passes := 0


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
	DirAccess.make_dir_recursive_absolute("res://_dev/shots")
	get_viewport().get_texture().get_image().save_png("res://_dev/shots/%s.png" % file)


func spawn(pos: Vector2) -> Node:
	var t = TROOP.instantiate()
	t.team = t.Team.PLAYER
	t.setup(UnitFactory.make_recruit())
	add_child(t)
	t.global_position = pos
	return t


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	GameStateManager.reset_run()
	GameStateManager.current_stage = 12
	GameStateManager.current_node_type = "Batalla Élite"
	var bt = BATTLE.instantiate()
	add_child(bt)
	await frames(4)
	var grid = bt.find_child("DeploymentGrid", true, false)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	print("Viewport: ", vp, " celda: ", grid.cell_size, " zona: ", grid.get_player_rect(), " enemiga: ", grid.get_enemy_rect())
	check(grid.grid_cells.size() == 25, "25 casillas (5x5)")
	check(grid.cell_size.x >= 76.0, "casillas de al menos el tamaño de una tropa (%d px)" % int(grid.cell_size.x))
	var pr: Rect2 = grid.get_player_rect()
	var er: Rect2 = grid.get_enemy_rect()
	check(pr.position.y >= 44.0, "la cuadrícula no pisa la cabecera")
	check(pr.end.y <= vp.y - 162.0 - 4.0, "la cuadrícula no pisa la barra de Ejército")
	check(is_equal_approx(pr.position.x, vp.x - er.end.x) and is_equal_approx(pr.position.y, er.position.y), "zona enemiga simétrica")
	check(er.position.x - pr.end.x >= 200.0, "tierra de nadie de al menos 200 px (%d)" % int(er.position.x - pr.end.x))
	var enemies: Array = bt.get_enemies()
	var all_in := enemies.all(func(e): return DeploymentGrid.index_of(grid.enemy_cells, e.global_position) >= 0)
	check(not enemies.is_empty() and all_in, "%d enemigos en casillas de la zona enemiga" % enemies.size())
	var prep = null
	for ch in bt.get_children():
		if "start_button" in ch:
			prep = ch
	var banner: Control = prep.get_node("Control/Banner")
	check(banner.get_global_rect().size.y <= 34.0, "cabecera compacta (%d px de alto)" % int(banner.get_global_rect().size.y))
	check(not banner.get_global_rect().intersects(Rect2(pr.position, pr.size)), "la cabecera no se superpone a la cuadrícula")
	check(not prep.start_button.get_global_rect().intersects(er) and not prep.start_button.get_global_rect().intersects(pr), "el botón de combatir no tapa ninguna zona")

	# Tropas y resaltado
	var a = spawn(grid.grid_cells[4])
	var b = spawn(grid.grid_cells[12])
	await frames(3)
	a.is_dragging = true
	a._drag_origin = grid.grid_cells[4]
	get_viewport().warp_mouse(grid.grid_cells[18])
	a.global_position = grid.grid_cells[18] + Vector2(6, -4)
	await frames(3)
	check(grid._hover_index == 18 and not grid._hover_swap, "al arrastrar se resalta la casilla libre de destino")
	await shot("despliegue_hover_libre")
	get_viewport().warp_mouse(grid.grid_cells[12] + Vector2(10, 8))
	a.global_position = grid.grid_cells[12] + Vector2(10, 8)
	await frames(3)
	check(grid._hover_index == 12 and grid._hover_swap, "sobre una casilla ocupada se resalta como intercambio")
	await shot("despliegue_hover_swap")
	a.is_dragging = false
	a._place_on_grid()
	await frames(2)
	check(a.global_position == grid.grid_cells[12] and b.global_position == grid.grid_cells[4], "el intercambio funciona con la nueva cuadrícula")
	await frames(2)
	check(grid._hover_index == -1, "sin arrastre no hay resaltado")

	# Cambio de tamaño de ventana: todo conserva su casilla
	var a_idx: int = grid.cell_index_of(a.global_position)
	var enemy_idx: Array = enemies.map(func(e): return DeploymentGrid.index_of(grid.enemy_cells, e.global_position))
	get_window().size = Vector2i(1600, 720)
	await get_tree().create_timer(1.0).timeout
	await frames(4)
	var vp2: Vector2 = get_viewport().get_visible_rect().size
	print("Viewport tras redimensionar: ", vp2, " zona: ", grid.get_player_rect(), " enemiga: ", grid.get_enemy_rect())
	if not vp2.is_equal_approx(vp):
		check(grid.cell_index_of(a.global_position) == a_idx, "tras redimensionar la tropa sigue en su casilla")
		var still: bool = true
		for i in enemies.size():
			if DeploymentGrid.index_of(grid.enemy_cells, enemies[i].global_position) != enemy_idx[i]:
				still = false
		check(still, "tras redimensionar los enemigos siguen en sus casillas espejo")
		check(grid.get_enemy_rect().end.x > vp2.x - 60.0, "la zona enemiga sigue pegada al borde derecho")
		check(bt.find_child("EnemyHeatmap", true, false) != null, "el mapa de calor se rehace")
		await shot("despliegue_ancho")
	else:
		print("AVISO: la ventana no cambió de tamaño en este entorno; se omite la prueba")
	DisplayServer.window_set_size(Vector2i(1152, 648))
	await frames(8)

	# Combate: la cuadrícula se desvanece
	EventBus.battle_fight_started.emit()
	await get_tree().create_timer(0.6).timeout
	check(not grid.visible, "al combatir la cuadrícula desaparece")
	await shot("despliegue_combate")
	print("TEST DONE: %d fallos (%d ok)" % [fails, passes])
	get_tree().quit()
