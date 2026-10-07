extends Node2D

const GAME_OVER_PANEL_SCENE = preload("res://Scenes/UI/game_over_panel.tscn")
const PREP_UI_SCENE = preload("res://Scenes/UI/prep_ui.tscn")
const REWARD_SCREEN_SCENE = preload("res://Scenes/UI/reward_screen.tscn")
const ITEM_INV_UI_SCENE = preload("res://Scenes/UI/item_inventory_ui.tscn")
const TROOP_SCENE = preload("res://Scenes/Troops/troop.tscn")
const ROSTER_UI_SCRIPT = preload("res://Scripts/UI/troop_roster_ui.gd")
const DETAIL_PANEL_SCRIPT = preload("res://Scripts/UI/troop_detail_panel.gd")
const HEATMAP_SCRIPT = preload("res://Scripts/Battle/enemy_heatmap.gd")
const BACKGROUND_SCRIPT = preload("res://Scripts/Battle/battlefield_background.gd")
const RECRUIT_SHOP_SCENE = preload("res://Scenes/UI/recruit_shop.tscn")
const BOSS_HP_MULT := 2.1
const BOSS_DMG_MULT := 1.5
const ENEMY_VARIANCE := 0.15
# Equilibrado v3 (simulador de partida completa _dev/run_sim.tscn, informe _dev/balance_v3.md)
const PROV_HP_PER_ROUND := 0.04   # v4: curva más plana para partidas de ~30 rondas (antes 0.065)
const PROV_DMG_PER_ROUND := 0.035 # v4: antes 0.055
const PROV_MAX_ENEMIES := 6
const PROV_MIN_ENEMIES_EVERY := 10.0 # +1 enemigo mínimo cada N rondas
const PROV_MAX_ENEMIES_EVERY := 8.0 # +1 enemigo máximo cada N rondas
const PROV_ELITE_EXTRA_ENEMIES := 1
const PROV_ELITE_HP := 1.0
const PROV_ELITE_DMG := 1.0
const PROV_BOSS_ESCORT_EVERY := 7.0 # +1 escolta del jefe cada N rondas
const PROV_BOSS_MAX := 4
# v4 — Presupuesto de poder enemigo por ronda (Σ vida × DPS de la oleada). Cada oleada se genera
# con su composición aleatoria (número, armas, niveles, especialidades) y después se ESCALA para
# que su poder total sea power_budget(ronda) ±10 %. Así la dificultad sube de forma suave y
# predecible, y un ejército mejor jugado gana con más margen. Ajustado con _dev/run_sim.tscn
# para partidas de ~30 rondas (cuadrática suave: muro hacia la ronda 30–40).
const POWER_BASE := 600.0
const POWER_LINEAR := 125.0
const POWER_QUAD := 5.4
const POWER_JITTER := 0.1
const POWER_ELITE := 1.3
const POWER_SECTOR := 1.5
const POWER_FINAL := 3.2

var is_battle_over: bool = false
var is_battle_started: bool = false
var heatmap: Sprite2D = null # Mapa de calor que oculta a los enemigos durante la planificación
var intel_label: Label = null # Aviso en la zona enemiga cuando no hay radioperador
var _intel_t: float = 0.0
const RADIO_SPECIALTY := "comunicaciones"


func _ready() -> void:
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.battle_fight_started.connect(_on_fight_started)
	
	# Suelo del campo de batalla (capa más baja, se mantiene en el combate)
	var ground = BACKGROUND_SCRIPT.new()
	ground.name = "BattlefieldBackground"
	add_child(ground)
	
	var prep_ui = PREP_UI_SCENE.instantiate()
	add_child(prep_ui)
	
	# Ejército (abajo, centrado; incluye la reserva) y submenú de personaje
	add_child(ROSTER_UI_SCRIPT.new())
	add_child(DETAIL_PANEL_SCRIPT.new())
	add_child(RECRUIT_SHOP_SCENE.instantiate())
	# Monedero del combate: las monedas de cada baja vuelan hasta él
	var purse := CoinPurseHud.new()
	purse.name = "CoinPurseHud"
	add_child(purse)
	
	_setup_enemy_wave()
	_hide_enemies_behind_heatmap()
	_restore_persisted_troops()
	
	var grid = get_grid()
	if grid and grid.has_signal("layout_changed"):
		grid.layout_changed.connect(_on_grid_layout_changed)
	
	for troop in get_tree().get_nodes_in_group("troops"):
		_connect_troop(troop)
	
	get_tree().node_added.connect(_on_node_added)


func _on_fight_started() -> void:
	is_battle_started = true
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm:
		gsm.begin_round_tracking()
	_reveal_enemies()
	# Instantánea del despliegue: casillas, niveles y objetos de TODAS las tropas (también las que mueran)
	_save_active_player_troops()


func _restore_persisted_troops() -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	if not gsm or gsm.deployed_troops_data.is_empty():
		return
	
	print("Restaurando tropas desplegadas en rondas anteriores: ", gsm.deployed_troops_data.size())
	
	var grid = get_grid()
	for troop_saved in gsm.deployed_troops_data:
		var saved_card: TroopCard = troop_saved.get("card")
		if saved_card == null:
			continue
		var new_troop = TROOP_SCENE.instantiate()
		new_troop.team = new_troop.Team.PLAYER
		new_troop.setup(saved_card)
		add_child(new_troop)
		# Se restaura por ÍNDICE de casilla: así sobrevive a cambios de tamaño de ventana o de cuadrícula
		var cell: int = int(troop_saved.get("cell", -1))
		if grid and cell >= 0 and cell < grid.grid_cells.size():
			new_troop.global_position = grid.grid_cells[cell]
		else:
			new_troop.global_position = troop_saved.get("position", Vector2(160, 240))


func _process(delta: float) -> void:
	if is_battle_started and not is_battle_over:
		_check_battle_status()
	elif not is_battle_started:
		_intel_t -= delta
		if _intel_t <= 0.0:
			_intel_t = 0.25
			update_intel()


## true si hay un Radioperador del jugador DESPLEGADO en el tablero (no en la reserva).
func has_radio_operator() -> bool:
	for t in get_tree().get_nodes_in_group("troops"):
		if not is_instance_valid(t) or t.is_queued_for_deletion() or t.has_meta("is_drag_preview"):
			continue
		if "team" in t and t.team == t.Team.PLAYER and t.card and t.card.specialty \
				and t.card.specialty.id == RADIO_SPECIALTY:
			return true
	return false


## Inteligencia de la planificación (v4): el mapa de calor del enemigo solo se ve con un
## Radioperador desplegado. Sin él, la zona enemiga es una incógnita.
func update_intel() -> void:
	var radio := has_radio_operator()
	if is_instance_valid(heatmap):
		heatmap.visible = radio
	if intel_label == null or not is_instance_valid(intel_label):
		intel_label = Label.new()
		intel_label.name = "IntelLabel"
		intel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		intel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		intel_label.add_theme_font_size_override("font_size", 15)
		intel_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		intel_label.add_theme_constant_override("outline_size", 5)
		intel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		intel_label.z_index = 5
		add_child(intel_label)
	var grid = get_grid()
	var er: Rect2 = grid.get_enemy_rect() if grid and grid.has_method("get_enemy_rect") else Rect2(760, 60, 360, 400)
	intel_label.size = Vector2(er.size.x, 60)
	if radio:
		intel_label.text = "📡 Informe de radio: posiciones aproximadas"
		intel_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.95, 0.9))
		intel_label.position = Vector2(er.position.x, er.end.y - 52)
	else:
		intel_label.text = "📡 Sin radioperador en el tablero\nno sabes dónde está el enemigo"
		intel_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.78, 0.85))
		intel_label.position = Vector2(er.position.x, er.get_center().y - 30)


func _setup_enemy_wave() -> void:
	randomize()
	
	var gsm = get_node_or_null("/root/GameStateManager")
	var stage = gsm.current_stage if gsm else 1
	var node_type = gsm.current_node_type if gsm else "Batalla Normal"
	var is_boss = (node_type == "Jefe Final")
	var is_subboss = (node_type == "Jefe de Sector")
	var is_elite = (node_type == "Batalla Élite")
	var diff: Dictionary = difficulty_for(stage, is_elite)
	
	# Eliminar enemigos previos si existían en la escena
	if has_node("EnemyTroop"):
		$EnemyTroop.queue_free()
	
	for child in get_children():
		if child.is_in_group("troops") and child.has_method("get_max_health") and child.team == child.Team.ENEMY:
			child.queue_free()
	
	# 2. Cantidad de enemigos
	var enemy_count: int = 1
	if is_boss or is_subboss:
		enemy_count = diff.boss_count # Jefe + escoltas
	else:
		enemy_count = randi_range(diff.min_enemies, diff.max_enemies)
	
	print("Generando oleada procedimental [%s] - Etapa: %d | Enemigos: %d" % [node_type, stage, enemy_count])
	
	# Cuadrícula enemiga (invisible): espejo de la del jugador. Cada enemigo ocupa una casilla distinta.
	var enemy_cells: Array[Vector2] = get_enemy_cells()
	enemy_cells.shuffle()
	
	# 3. Generar la oleada: cada enemigo es un TroopCard único (UnitFactory); luego se escala al presupuesto
	var cards: Array[TroopCard] = []
	for i in range(enemy_count):
		var leader: bool = (is_boss or is_subboss) and i == 0
		var enemy_card: TroopCard = UnitFactory.make_enemy(stage, is_elite, leader)
		if leader and is_subboss:
			apply_subboss(enemy_card, diff, stage)
		else:
			apply_difficulty(enemy_card, diff, leader)
		cards.append(enemy_card)
	normalize_wave(cards, power_budget(stage, node_type) * randf_range(1.0 - POWER_JITTER, 1.0 + POWER_JITTER), stage if is_subboss else 0)
	for i in range(cards.size()):
		var leader: bool = (is_boss or is_subboss) and i == 0
		var enemy_card: TroopCard = cards[i]
		var enemy = TROOP_SCENE.instantiate()
		enemy.team = enemy.Team.ENEMY
		enemy.setup(enemy_card)
		add_child(enemy)
		# Casilla aleatoria libre de la cuadrícula enemiga
		enemy.global_position = enemy_cells[i % enemy_cells.size()]
		enemy.name = "Jefe_Enemigo" if leader else "Enemigo_%d" % (i + 1)


## Jefe de Sector (cada 10 rondas): vida FIJA (Economy.subboss_hp) y daño sin variación aleatoria,
## para que el jugador sepa qué obstáculo le espera en las rondas 10, 20, 30…
static func apply_subboss(card: TroopCard, diff: Dictionary, stage: int) -> void:
	card.is_boss = true
	card.unit_name = "Cmdte. " + card.unit_name
	card.base_damage *= float(diff.dmg_mult) * BOSS_DMG_MULT
	var target: float = Economy.subboss_hp(stage)
	var b: float = card.base_health
	var with_base: float = float(TroopStats.compute(card).max_health)
	card.base_health = 0.0
	var flat: float = float(TroopStats.compute(card).max_health) # parte fija (objetos/habilidades +vida)
	card.base_health = b * maxf(0.05, (target - flat) / maxf(1.0, with_base - flat))


## Poder objetivo de una oleada (Σ vida × DPS) para la ronda y tipo de combate.
static func power_budget(round_number: int, node_type: String = "Batalla Normal") -> float:
	var x: float = maxf(0.0, float(round_number - 1))
	var p: float = POWER_BASE + POWER_LINEAR * x + POWER_QUAD * x * x
	match node_type:
		"Batalla Élite": p *= POWER_ELITE
		"Jefe de Sector": p *= POWER_SECTOR
		"Jefe Final": p *= POWER_FINAL
	return p


static func card_power(card: TroopCard) -> float:
	var st := TroopStats.compute(card)
	return float(st.max_health) * float(st.dps)


## Escala vida y daño de toda la oleada para que su poder total sea `target`. Se reparte por
## igual (×√k a vida y a daño), así se conserva la composición. Si `subboss_stage` > 0, el jefe
## de sector (cards[0]) recupera su vida FIJA y compensa con el daño.
static func normalize_wave(cards: Array[TroopCard], target: float, subboss_stage: int = 0) -> void:
	# Dos pasadas: la vida plana de objetos/habilidades no escala, la 2.ª corrige el resto
	for _pass in 2:
		var total := 0.0
		for c in cards:
			total += card_power(c)
		if total <= 0.0 or target <= 0.0:
			return
		var k: float = sqrt(target / total)
		for c in cards:
			c.base_health *= k
			c.base_damage *= k
	if subboss_stage > 0 and not cards.is_empty():
		var leader: TroopCard = cards[0]
		var want: float = card_power(leader)
		_fix_subboss_hp(leader, subboss_stage)
		var now: float = card_power(leader)
		if now > 0.0:
			leader.base_damage *= clampf(want / now, 0.25, 4.0)


static func _fix_subboss_hp(card: TroopCard, stage: int) -> void:
	var target: float = Economy.subboss_hp(stage)
	var b: float = card.base_health
	var with_base: float = float(TroopStats.compute(card).max_health)
	card.base_health = 0.0
	var flat: float = float(TroopStats.compute(card).max_health)
	card.base_health = b * maxf(0.05, (target - flat) / maxf(1.0, with_base - flat))


## Aplica la dificultad de la ronda (±15 % de variación) al card de un enemigo. El jefe, además, ×BOSS_HP_MULT vida y ×BOSS_DMG_MULT daño.
static func apply_difficulty(enemy_card: TroopCard, diff: Dictionary, is_boss_leader: bool = false) -> void:
	var variance: float = randf_range(1.0 - ENEMY_VARIANCE, 1.0 + ENEMY_VARIANCE)
	enemy_card.base_health *= float(diff.hp_mult) * variance * (BOSS_HP_MULT if is_boss_leader else 1.0)
	enemy_card.base_damage *= float(diff.dmg_mult) * variance * (BOSS_DMG_MULT if is_boss_leader else 1.0)
	if is_boss_leader:
		enemy_card.is_boss = true


## Dificultad incremental de una ronda. Sube poco a poco y no tiene tope de rondas.
static func difficulty_for(round_number: int, is_elite: bool = false) -> Dictionary:
	var r: int = maxi(round_number, 1) - 1
	# PROVISIONAL (pre-balance QA): los enemigos ya suben de nivel con UnitFactory, así que el
	# multiplicador por ronda es suave (antes +10 % vida / +7 % daño y entre 1 + r/4 y 2 + r/2 enemigos, tope 8).
	var hp_mult: float = 1.0 + r * PROV_HP_PER_ROUND
	var dmg_mult: float = 1.0 + r * PROV_DMG_PER_ROUND
	var min_enemies: int = 1 + int(r / PROV_MIN_ENEMIES_EVERY)
	var max_enemies: int = 2 + int(r / PROV_MAX_ENEMIES_EVERY)
	if is_elite:
		hp_mult *= PROV_ELITE_HP
		dmg_mult *= PROV_ELITE_DMG
		max_enemies += PROV_ELITE_EXTRA_ENEMIES
	max_enemies = mini(max_enemies, PROV_MAX_ENEMIES)
	min_enemies = mini(min_enemies, max_enemies)
	return {
		"hp_mult": hp_mult,
		"dmg_mult": dmg_mult,
		"min_enemies": min_enemies,
		"max_enemies": max_enemies,
		"boss_count": mini(1 + int((r + 1) / PROV_BOSS_ESCORT_EVERY), PROV_BOSS_MAX), # Jefe + escoltas que crecen con la ronda
	}


## Planificación: los enemigos no se ven; en su lugar hay un mapa de calor de dónde pueden estar.
func _hide_enemies_behind_heatmap() -> void:
	var points: Array[Vector2] = []
	for enemy in get_enemies():
		enemy.visible = false
		points.append(enemy.global_position)
	if points.is_empty():
		return
	var cells := get_enemy_cells()
	var area := Rect2(cells[0], Vector2.ZERO)
	for c in cells:
		area = area.expand(c)
	for p in points:
		area = area.expand(p)
	heatmap = HEATMAP_SCRIPT.new()
	heatmap.name = "EnemyHeatmap"
	add_child(heatmap)
	heatmap.build(points, area)
	update_intel()


## Combate: se quita el mapa de calor (se desvanece solo) y aparecen los enemigos.
func _reveal_enemies() -> void:
	for enemy in get_enemies():
		enemy.visible = true
		enemy.modulate.a = 0.0
		enemy.create_tween().tween_property(enemy, "modulate:a", 1.0, 0.3)
	heatmap = null
	if is_instance_valid(intel_label):
		intel_label.queue_free()
		intel_label = null


func get_enemies() -> Array:
	var list: Array = []
	for child in get_children():
		if child.is_in_group("troops") and not child.is_queued_for_deletion() \
				and "team" in child and child.team == child.Team.ENEMY:
			list.append(child)
	return list


func get_grid() -> Node:
	return find_child("DeploymentGrid", true, false)


## Casillas de la zona enemiga: la cuadrícula del jugador reflejada en horizontal (mismas filas y
## columnas, al otro lado). La dibuja DeploymentGrid en tono rojizo; los enemigos se reparten por ella.
func get_enemy_cells() -> Array[Vector2]:
	var cells: Array[Vector2] = []
	var player_grid = get_grid()
	if player_grid and player_grid.has_method("get_enemy_cells"):
		cells = player_grid.get_enemy_cells()
	elif player_grid and not player_grid.grid_cells.is_empty():
		var screen_width: float = get_viewport_rect().size.x
		for cell in player_grid.grid_cells:
			cells.append(Vector2(screen_width - cell.x, cell.y))
	if cells.is_empty():
		cells.append(Vector2(900.0, 300.0)) # Sin cuadrícula del jugador: una única posición de respaldo
	return cells


## La ventana cambió de tamaño en la planificación: cada tropa y cada enemigo conserva su casilla.
func _on_grid_layout_changed(old_cells: Array[Vector2], old_enemy_cells: Array[Vector2]) -> void:
	if is_battle_started:
		return
	var grid = get_grid()
	for troop in get_tree().get_nodes_in_group("troops"):
		if not is_instance_valid(troop) or troop.has_meta("is_drag_preview") or not ("team" in troop):
			continue
		var is_enemy: bool = troop.team == troop.Team.ENEMY
		var src: Array[Vector2] = old_enemy_cells if is_enemy else old_cells
		var dst: Array[Vector2] = grid.enemy_cells if is_enemy else grid.grid_cells
		var idx: int = DeploymentGrid.index_of(src, troop.global_position)
		if idx >= 0 and idx < dst.size():
			troop.global_position = dst[idx]
	# El mapa de calor se rehace sobre las nuevas posiciones
	if is_instance_valid(heatmap):
		heatmap.name = "EnemyHeatmapOld" # libera el nombre para el nuevo
		heatmap.queue_free()
		heatmap = null
		_hide_enemies_behind_heatmap()


func _on_node_added(node: Node) -> void:
	if node.is_in_group("troops"):
		_connect_troop(node)


func _connect_troop(troop: Node) -> void:
	if troop.has_signal("died") and not troop.died.is_connected(_on_troop_died):
		troop.died.connect(_on_troop_died)


func _on_troop_died(_troop: Node) -> void:
	if is_battle_over:
		return

	# Registrar bajas y emitir eventos si la batalla ha empezado
	if is_battle_started and is_instance_valid(_troop):
		var troop = _troop
		var gsm = get_node_or_null("/root/GameStateManager")

		if troop.team == troop.Team.ENEMY and gsm:
			# Leer card y posición ANTES de que se libere
			var enemy_card: TroopCard = troop.card
			var enemy_pos: Vector2 = troop.global_position
			var coins: int = gsm.register_enemy_kill(enemy_card, gsm.current_node_type)
			EventBus.enemy_reward.emit(enemy_pos, coins)
			# Texto flotante dorado "+%d 💰" sobre el enemigo (un poco por encima)
			CombatFX.text(self, enemy_pos + Vector2(0, -20), "+%d 💰" % coins, Color(1.0, 0.85, 0.2), 16)
		elif troop.team == troop.Team.PLAYER and gsm:
			gsm.register_player_loss()

	call_deferred("_check_battle_status")


func _check_battle_status() -> void:
	if is_battle_over or not is_inside_tree(): # puede llegar diferida tras salir del árbol
		return
	
	var player_count: int = 0
	var enemy_count: int = 0
	
	for troop in get_tree().get_nodes_in_group("troops"):
		if not is_instance_valid(troop) or troop.is_queued_for_deletion():
			continue
		
		if troop.team == troop.Team.PLAYER:
			player_count += 1
		elif troop.team == troop.Team.ENEMY:
			enemy_count += 1
	
	if is_battle_started:
		if player_count == 0 and enemy_count == 0:
			_trigger_game_over(false)
		elif player_count == 0:
			_trigger_game_over(false)
		elif enemy_count == 0:
			_show_reward_screen()


func _save_active_player_troops() -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	if not gsm:
		return
	
	var active_player_troops: Array = []
	for troop in get_tree().get_nodes_in_group("troops"):
		if is_instance_valid(troop) and not troop.is_queued_for_deletion() and troop.team == troop.Team.PLAYER and not troop.has_meta("is_drag_preview"):
			active_player_troops.append(troop)
	
	gsm.save_deployed_troops(active_player_troops)
	# Además de la posición se guarda el índice de casilla (más robusto entre rondas)
	var grid = get_grid()
	if grid and grid.has_method("cell_index_of"):
		for entry in gsm.deployed_troops_data:
			entry["cell"] = grid.cell_index_of(entry.get("position", Vector2.INF))


func _show_reward_screen() -> void:
	is_battle_over = true
	var gsm = get_node_or_null("/root/GameStateManager")

	# Aplicar recompensas de victoria UNA sola vez
	if gsm:
		gsm.apply_victory_rewards(gsm.current_node_type)

	# Derrotar al jefe gana la partida
	if gsm and gsm.is_boss_stage():
		var panel = GAME_OVER_PANEL_SCENE.instantiate()
		add_child(panel)
		panel.setup(true)
		return
	var reward_screen = REWARD_SCREEN_SCENE.instantiate()
	add_child(reward_screen)


func _trigger_game_over(is_victory: bool) -> void:
	is_battle_over = true
	
	var game_over_panel = GAME_OVER_PANEL_SCENE.instantiate()
	add_child(game_over_panel)
	game_over_panel.setup(is_victory)
