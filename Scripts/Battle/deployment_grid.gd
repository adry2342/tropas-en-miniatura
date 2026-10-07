class_name DeploymentGrid
extends Node2D
## Cuadrícula de despliegue de la fase de planificación.
##  - Zona del jugador a la izquierda y zona enemiga ESPEJO a la derecha (mismas filas y columnas).
##  - La distribución se calcula a partir del tamaño real de la pantalla: ocupa toda la altura libre
##    entre la cabecera y la barra de Ejército y llega casi hasta los bordes laterales.
##  - Las casillas se ordenan por filas (índice = fila * columns + columna). La columna 0 es la
##    retaguardia; la última columna es el frente (la más cercana a la tierra de nadie).
##  - Si cambia el tamaño de la ventana durante la planificación se recalcula y emite
##    `layout_changed` para que la batalla recoloque tropas, enemigos y mapa de calor.

signal layout_changed(old_cells: Array[Vector2], old_enemy_cells: Array[Vector2])

@export var columns: int = 5
@export var rows: int = 5
@export var top_margin: float = 54.0       ## Hueco para la cabecera compacta y los rótulos de zona
@export var bottom_reserved: float = 172.0 ## Barra de Ejército (162 px) + aire
@export var side_margin: float = 24.0      ## Distancia de cada zona al borde lateral
@export var min_center_gap: float = 200.0  ## Tierra de nadie mínima entre ambas zonas
@export var min_cell: float = 64.0
@export var max_cell: float = 104.0

# ---------------------------------------------------------------- paleta (mapa táctico militar)
const ZONE_BG := Color(0.07, 0.085, 0.06, 0.62)
const ZONE_BORDER := Color(0.78, 0.7, 0.44, 0.55)
const TILE_A := Color(0.45, 0.52, 0.31, 0.34)
const TILE_B := Color(0.38, 0.45, 0.26, 0.34)
const TILE_EDGE := Color(0.92, 0.88, 0.65, 0.16)
const BRACKET := Color(0.98, 0.82, 0.4, 0.95)
const FRONT_LINE := Color(0.98, 0.82, 0.4, 0.45)
const HOVER_FREE := Color(0.55, 0.9, 0.4, 0.42)
const HOVER_FREE_EDGE := Color(0.78, 1.0, 0.6, 0.95)
const HOVER_SWAP := Color(1.0, 0.68, 0.22, 0.4)
const HOVER_SWAP_EDGE := Color(1.0, 0.8, 0.4, 0.95)
const ENEMY_BG := Color(0.12, 0.05, 0.04, 0.3)
const ENEMY_BORDER := Color(0.9, 0.32, 0.26, 0.5)
const ENEMY_TILE := Color(0.6, 0.22, 0.17, 0.13)
const ENEMY_BRACKET := Color(1.0, 0.42, 0.34, 0.9)
const CAPTION_ALLY := Color(0.96, 0.86, 0.55, 0.9)
const CAPTION_ENEMY := Color(1.0, 0.55, 0.48, 0.9)

var cell_size: Vector2 = Vector2(80, 80)
var grid_origin: Vector2 = Vector2.ZERO   ## Esquina superior izquierda de la zona del jugador
var enemy_origin: Vector2 = Vector2.ZERO  ## Esquina superior izquierda de la zona enemiga
var grid_cells: Array[Vector2] = []       ## Centros de las casillas del jugador (globales)
var enemy_cells: Array[Vector2] = []      ## Centros de las casillas enemigas (espejo horizontal)

var _screen_size: Vector2 = Vector2.ZERO
var _hover_index: int = -1
var _hover_swap: bool = false
var _tile_style := StyleBoxFlat.new()
var _fading: bool = false


func _ready() -> void:
	add_to_group("deployment_grid")
	z_index = -2 # Por debajo del mapa de calor (-1), las tropas y los textos
	_tile_style.anti_aliasing = true
	_generate_grid_positions()
	get_viewport().size_changed.connect(_on_viewport_resized)

	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.battle_fight_started.connect(_on_battle_fight_started)


func _on_battle_fight_started() -> void:
	# Se desvanece en vez de desaparecer de golpe
	_fading = true
	_hover_index = -1
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.35)
	t.tween_callback(hide)


# ================================================================ distribución

func _generate_grid_positions() -> void:
	_screen_size = get_viewport_rect().size
	var avail_h: float = _screen_size.y - top_margin - bottom_reserved
	var avail_w: float = (_screen_size.x - 2.0 * side_margin - min_center_gap) * 0.5
	var cell: float = floorf(minf(avail_h / float(rows), avail_w / float(columns)))
	cell = clampf(cell, min_cell, max_cell)
	cell_size = Vector2(cell, cell)
	var zone: Vector2 = get_zone_size()
	var y: float = top_margin + maxf(0.0, (avail_h - zone.y) * 0.5)
	grid_origin = Vector2(side_margin, y)
	enemy_origin = Vector2(_screen_size.x - side_margin - zone.x, y)

	grid_cells.clear()
	enemy_cells.clear()
	for r in range(rows):
		for c in range(columns):
			var pos: Vector2 = grid_origin + Vector2((c + 0.5) * cell, (r + 0.5) * cell)
			grid_cells.append(pos)
			enemy_cells.append(Vector2(_screen_size.x - pos.x, pos.y))
	queue_redraw()


func _on_viewport_resized() -> void:
	if not is_visible_in_tree() or _fading:
		return
	if get_viewport_rect().size.is_equal_approx(_screen_size):
		return
	var old_cells: Array[Vector2] = grid_cells.duplicate()
	var old_enemy: Array[Vector2] = enemy_cells.duplicate()
	_generate_grid_positions()
	layout_changed.emit(old_cells, old_enemy)


func get_zone_size() -> Vector2:
	return Vector2(columns * cell_size.x, rows * cell_size.y)


func get_player_rect() -> Rect2:
	return Rect2(grid_origin, get_zone_size())


func get_enemy_rect() -> Rect2:
	return Rect2(enemy_origin, get_zone_size())


func get_enemy_cells() -> Array[Vector2]:
	return enemy_cells.duplicate()


## Índice de la casilla cuyo centro coincide con `pos` en `cells` (-1 si no está en ninguna).
static func index_of(cells: Array[Vector2], pos: Vector2, tolerance: float = 1.0) -> int:
	for i in range(cells.size()):
		if cells[i].distance_to(pos) < tolerance:
			return i
	return -1


func cell_index_of(pos: Vector2) -> int:
	return index_of(grid_cells, pos)


# ================================================================ consultas de casillas

func get_snapped_position(global_pos: Vector2) -> Vector2:
	if grid_cells.is_empty():
		return global_pos
	var closest_pos = grid_cells[0]
	var min_dist = global_pos.distance_to(closest_pos)
	for cell_pos in grid_cells:
		var dist = global_pos.distance_to(cell_pos)
		if dist < min_dist:
			min_dist = dist
			closest_pos = cell_pos
	return closest_pos


## Tropa del jugador que ocupa esa casilla (null si está libre). Ignora a `ignore`,
## a las tropas que se están arrastrando y a las previsualizaciones de la reserva.
func get_occupant(cell_pos: Vector2, ignore: Node = null) -> Node:
	for unit in get_tree().get_nodes_in_group("troops"):
		if unit == ignore or not is_instance_valid(unit) or unit.is_queued_for_deletion():
			continue
		if unit.team != unit.Team.PLAYER or unit.has_meta("is_drag_preview") or unit.is_dragging:
			continue
		if unit.global_position.distance_to(cell_pos) < 1.0:
			return unit
	return null


## Casilla libre más cercana a la posición dada. Devuelve Vector2.INF si no queda ninguna.
func get_nearest_free_position(global_pos: Vector2, ignore: Node = null) -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_dist: float = INF
	for cell_pos in grid_cells:
		if get_occupant(cell_pos, ignore) != null:
			continue
		var dist: float = global_pos.distance_to(cell_pos)
		if dist < best_dist:
			best_dist = dist
			best = cell_pos
	return best


# ================================================================ resaltado al arrastrar

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or _fading:
		return
	var dragged: Node = _find_dragged_troop()
	var idx: int = -1
	var swap: bool = false
	if dragged != null:
		var mouse: Vector2 = get_global_mouse_position()
		if get_player_rect().grow(cell_size.x * 0.5).has_point(mouse):
			var from_bench: bool = dragged.has_meta("is_drag_preview")
			var target: Vector2 = get_snapped_position(mouse)
			if from_bench:
				# Desde la reserva se coloca en la casilla libre más cercana (nunca intercambia)
				target = get_nearest_free_position(mouse)
			if target != Vector2.INF:
				idx = cell_index_of(target)
				swap = not from_bench and get_occupant(target, dragged) != null
	if idx != _hover_index or swap != _hover_swap:
		_hover_index = idx
		_hover_swap = swap
		queue_redraw()


func _find_dragged_troop() -> Node:
	for unit in get_tree().get_nodes_in_group("troops"):
		if not is_instance_valid(unit) or unit.team != unit.Team.PLAYER:
			continue
		if unit.has_meta("is_drag_preview") or unit.is_dragging:
			return unit
	return null


# ================================================================ dibujo

func _draw() -> void:
	if not is_visible_in_tree() or grid_cells.is_empty():
		return
	var cell: float = cell_size.x
	var font: Font = ThemeDB.fallback_font

	# --- Zona enemiga (espejo): mismo trazado, tono rojizo y sin detalle extra
	var er: Rect2 = get_enemy_rect()
	_draw_zone_backdrop(er, ENEMY_BG, ENEMY_BORDER)
	for r in range(rows):
		for c in range(columns):
			_draw_tile(Rect2(enemy_origin + Vector2(c * cell, r * cell), cell_size), ENEMY_TILE, Color(0, 0, 0, 0))
	_draw_brackets(er, ENEMY_BRACKET)
	_draw_front_line(er.position.x - 10.0, er)

	# --- Zona del jugador
	var pr: Rect2 = get_player_rect()
	_draw_zone_backdrop(pr, ZONE_BG, ZONE_BORDER)
	for r in range(rows):
		for c in range(columns):
			var tint: Color = TILE_A if (r + c) % 2 == 0 else TILE_B
			# El frente (última columna) un pelín más cálido para orientar al jugador
			if c == columns - 1:
				tint = tint.lerp(Color(0.62, 0.55, 0.3, tint.a), 0.35)
			_draw_tile(Rect2(grid_origin + Vector2(c * cell, r * cell), cell_size), tint, TILE_EDGE)
	_draw_brackets(pr, BRACKET)
	_draw_front_line(pr.end.x + 10.0, pr)

	# --- Casilla de destino mientras se arrastra
	if _hover_index >= 0 and _hover_index < grid_cells.size():
		var center: Vector2 = grid_cells[_hover_index]
		var rect := Rect2(center - cell_size * 0.5, cell_size)
		if _hover_swap:
			_draw_tile(rect, HOVER_SWAP, HOVER_SWAP_EDGE, 2)
		else:
			_draw_tile(rect, HOVER_FREE, HOVER_FREE_EDGE, 2)

	# --- Rótulos de zona
	if font:
		var fs: int = 12
		draw_string(font, Vector2(pr.position.x + 2.0, pr.position.y - 7.0), "▸ TU ZONA",
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CAPTION_ALLY)
		draw_string(font, Vector2(er.position.x, er.position.y - 7.0), "ZONA ENEMIGA ◂",
				HORIZONTAL_ALIGNMENT_RIGHT, er.size.x - 2.0, fs, CAPTION_ENEMY)


func _draw_zone_backdrop(rect: Rect2, bg: Color, border: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.anti_aliasing = true
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 6
	draw_style_box(sb, rect.grow(6.0))


func _draw_tile(rect: Rect2, fill: Color, edge: Color, edge_w: int = 1) -> void:
	_tile_style.bg_color = fill
	_tile_style.border_color = edge
	_tile_style.set_border_width_all(edge_w if edge.a > 0.0 else 0)
	_tile_style.set_corner_radius_all(6)
	draw_style_box(_tile_style, rect.grow(-3.0))


## Escuadras en las cuatro esquinas de la zona (estilo visor táctico).
func _draw_brackets(rect: Rect2, color: Color) -> void:
	var r: Rect2 = rect.grow(6.0)
	var l: float = 20.0
	var w: float = 3.0
	var corners := [
		[r.position, Vector2(1, 0), Vector2(0, 1)],
		[Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1)],
		[r.end, Vector2(-1, 0), Vector2(0, -1)],
	]
	for k in corners:
		var p: Vector2 = k[0]
		draw_line(p, p + k[1] * l, color, w, true)
		draw_line(p, p + k[2] * l, color, w, true)


## Línea discontinua que marca el frente de una zona.
func _draw_front_line(x: float, rect: Rect2) -> void:
	draw_dashed_line(Vector2(x, rect.position.y + 4.0), Vector2(x, rect.end.y - 4.0), FRONT_LINE, 2.0, 8.0, true, true)
