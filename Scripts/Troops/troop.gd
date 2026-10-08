extends CharacterBody2D
## Tropa en el tablero. Todo sale de su TroopCard (SPEC v2): las estadísticas se calculan con
## TroopStats.compute(card) y los efectos especiales los gestiona Effects (Scripts/Systems/effects.gd).

signal died(troop: CharacterBody2D)

const BULLET_SCENE = preload("res://Scenes/Battle/bullet.tscn")
const DEFAULT_TEXTURE = preload("res://Assets/Sprites/sprite-personaje-basico.png")
const SPRITE_HEIGHT := 80.0
const BOSS_SCALE := 1.8
const CLICK_DRAG_TOLERANCE := 6.0
const MISS_TEXT_COOLDOWN := 0.45
const BURN_TICK := 0.5
const CAMO_ALPHA := 0.4
const NAME_LABEL_HALF_W := 40.0
const PLAYER_TINT := Color.WHITE
const ENEMY_TINT := Color(1.0, 0.7, 0.7)
const BURN_TINT := Color(1.0, 0.55, 0.2)

## Emojis que la fuente no dibuja (salen como caja): se sustituyen por otros que sí (igual que la UI).
const EMOJI_FALLBACK := {"🪖": "🎖️", "⛓️": "🔗"}

enum Team { PLAYER, ENEMY }

@export var team: Team = Team.PLAYER:
	set(value):
		team = value
		if is_node_ready():
			update_visuals()
			update_health_bar()

## Estado persistente de la tropa. Se asigna con setup(card).
var card: TroopCard = null
## Estadísticas finales (TroopStats.compute). Se recalculan en refresh_from_card().
var stats: Dictionary = {}
var effects: Effects = null

var health: float = 100.0
var target: Node2D = null
var attack_cooldown: float = 0.0
const DAMAGE_TEXT_INTERVAL := 0.22
var _dmg_pending: float = 0.0
var last_damage: float = 0.0 # último golpe recibido (diagnóstico y pruebas)
var _dmg_text_t: float = 0.0
var stray_hits: int = 0      # balas desviadas que acabaron dando a un enemigo
var friendly_hits: int = 0   # balas desviadas que dieron a un compañero (fuego amigo)
var ammo: int = 0
var reloading: bool = false
var reload_left: float = 0.0

# --- v7.3: varias armas en combate ---
# Todas las armas del arsenal van equipadas. La tropa usa la PRINCIPAL (card.equipped_weapon).
# Si se le vacía el cargador BAJO FUEGO y otra arma tiene balas y alcanza al objetivo, cambia a esa en
# vez de recargar. Cuando pasa el peligro (o la de reserva también se vacía) vuelve a la principal y la recarga.
const WEAPON_SWAP_TIME := 0.35     # s sin disparar al cambiar de arma
const UNDER_FIRE_WINDOW := 2.5     # s desde el último disparo recibido para estar "bajo fuego"
const CALM_RETURN_TIME := 3.0      # s sin recibir disparos para volver a la principal
const MIN_RELOAD_TO_CANCEL := 0.6  # si la recarga de la principal acaba en menos, no se interrumpe
## Índice (en card.weapons) del arma que está usando ahora.
var active_weapon: int = 0
## Balas que quedan en cada arma (índice → balas). La activa se lleva en `ammo`.
var weapon_ammo: Dictionary = {}
var _weapon_stats: Dictionary = {}  # índice → TroopStats.compute(card, arma)
var weapon_swaps: int = 0           # cambios de arma en este combate (estadísticas y pruebas)
var since_hit: float = 999.0        # s desde el último disparo recibido
var _calm_check_t: float = 0.0
var statuses: Dictionary = {}   # "burn": {dps, left, tick}
var buffs: Dictionary = {}      # clave -> {stat, value, left}
var camo_left: float = 0.0      # >0 = camuflada: los enemigos no la eligen como objetivo
var still_time: float = 0.0     # segundos sin moverse (paciencia del francotirador)
var is_battle_started: bool = false
var is_dead: bool = false

## Pruebas: -1 = azar, 0 = siempre falla, 1 = siempre acierta. Igual para críticos y esquiva.
var force_hit: int = -1
var force_hit_pattern: Array = []   # pruebas: acierto/fallo por perdigón (true/false), tiene prioridad
var force_crit: int = -1
var force_lethal: int = -1 # pruebas: 1 = el próximo disparo es letal, 0 = nunca, -1 = azar
var lethals: int = 0
var force_dodge: int = -1
## false = no busca objetivo, no se mueve ni dispara (maniquí de pruebas); sigue recibiendo daño y efectos.
var ai_enabled: bool = true

## Contadores (estadísticas del combate y pruebas)
var shots_fired: int = 0
var pellets_fired: int = 0
var hits: int = 0
var misses: int = 0
var crits: int = 0
var reloads: int = 0
var dodges: int = 0
var kills: int = 0
var burn_damage_taken: float = 0.0
var grenades_thrown: int = 0

## Nivel (compatibilidad: sale del card)
var level: int:
	get:
		return card.level if card else 1

var is_dragging: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _drag_origin: Vector2 = Vector2.ZERO
var _grab_radius: float = 40.0
var _miss_text_cd: float = 0.0
var _sprite_height: float = SPRITE_HEIGHT
var _hurt_flash: float = 0.0


func _ready() -> void:
	add_to_group("troops")
	if card == null:
		card = UnitFactory.make_recruit() # respaldo: una tropa nunca se queda sin card
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.battle_fight_started.connect(_on_battle_fight_started)
		bus.roster_changed.connect(_on_roster_changed)
		bus.troop_leveled.connect(_on_troop_leveled)
	_style_bars()
	refresh_from_card()
	if team == Team.PLAYER:
		call_deferred("_snap_to_grid")


## Configura la tropa con su card (llamar antes o después de añadirla al árbol).
func setup(new_card: TroopCard) -> void:
	card = new_card
	refresh_from_card()


## Recalcula estadísticas, etiqueta, sprite y barras. Fuera de combate deja la vida al máximo.
func refresh_from_card() -> void:
	if card == null:
		return
	_compute_weapon_stats()
	_sprite_height = SPRITE_HEIGHT * (BOSS_SCALE if card.is_boss else 1.0)
	if not is_battle_started:
		active_weapon = primary_weapon_index()
		stats = _stats_for(active_weapon)
		health = get_max_health()
		weapon_ammo.clear()
		for i in _weapon_stats:
			weapon_ammo[i] = int(_weapon_stats[i].magazine)
		ammo = int(stats.magazine)
		reloading = false
		reload_left = 0.0
		weapon_swaps = 0
		since_hit = 999.0
	else:
		if not _weapon_stats.has(active_weapon):
			active_weapon = primary_weapon_index()
		stats = _stats_for(active_weapon)
		ammo = mini(ammo, int(stats.magazine)) if int(stats.magazine) > 0 else 0
		health = minf(health, get_max_health())
	_apply_sprite()
	_update_name_label()
	update_health_bar()
	_update_reload_bar()
	update_visuals()


## Estadísticas de cada arma del arsenal (todas equipadas).
func _compute_weapon_stats() -> void:
	_weapon_stats.clear()
	if card.weapons.is_empty():
		_weapon_stats[0] = TroopStats.compute(card)
		return
	for i in card.weapons.size():
		if card.weapons[i] != null:
			_weapon_stats[i] = TroopStats.compute(card, card.weapons[i])
	if _weapon_stats.is_empty():
		_weapon_stats[0] = TroopStats.compute(card)


func _stats_for(i: int) -> Dictionary:
	return _weapon_stats.get(i, _weapon_stats.values()[0])


## Arma principal (la que el jugador marcó en el arsenal).
func primary_weapon_index() -> int:
	if card == null or card.weapons.is_empty():
		return 0
	var i := clampi(card.equipped_weapon, 0, card.weapons.size() - 1)
	return i if _weapon_stats.has(i) else int(_weapon_stats.keys()[0])


## Arma que está usando ahora mismo.
func get_active_weapon() -> WeaponData:
	return stats.get("weapon") as WeaponData


## ¿Le están disparando? (le han dado o esquivado hace poco, o un enemigo le apunta y le alcanza)
func is_under_fire() -> bool:
	return since_hit <= UNDER_FIRE_WINDOW or _is_targeted()


func _is_targeted() -> bool:
	for t in get_tree().get_nodes_in_group("troops"):
		if t == self or not is_instance_valid(t) or t.is_dead or t.team == team or t.get("target") != self:
			continue
		if t.global_position.distance_to(global_position) <= float(t.get_attack_range()) + 10.0:
			return true
	return false


## Cambia a otra arma con balas que alcance al objetivo (la de más DPS). false si no hay ninguna.
func try_swap_weapon() -> bool:
	if _weapon_stats.size() < 2:
		return false
	var dist: float = global_position.distance_to(target.global_position) if _is_valid_target(target) else -1.0
	var best := -1
	var best_dps := -1.0
	for i in _weapon_stats:
		if i == active_weapon:
			continue
		var st: Dictionary = _weapon_stats[i]
		if int(st.magazine) > 0 and int(weapon_ammo.get(i, 0)) <= 0:
			continue
		if dist >= 0.0 and (dist > float(st.attack_range) * (1.0 + get_buff_total("range_pct")) or dist < float(st.min_range)):
			continue
		if float(st.dps) > best_dps:
			best_dps = float(st.dps)
			best = i
	if best < 0:
		return false
	set_active_weapon(best)
	return true


## Pone en la mano el arma `i` (guarda las balas de la anterior). Tarda WEAPON_SWAP_TIME en disparar.
func set_active_weapon(i: int, announce: bool = true) -> void:
	if not _weapon_stats.has(i) or i == active_weapon:
		return
	weapon_ammo[active_weapon] = ammo
	active_weapon = i
	stats = _weapon_stats[i]
	ammo = int(weapon_ammo.get(i, int(stats.magazine)))
	reloading = false
	reload_left = 0.0
	attack_cooldown = maxf(attack_cooldown, WEAPON_SWAP_TIME)
	weapon_swaps += 1
	if announce and is_inside_tree():
		var w: WeaponData = stats.weapon
		show_text("🔄 %s %s" % [EMOJI_FALLBACK.get(w.emoji, w.emoji), w.display_name], Color(0.75, 0.9, 1.0), 12, -12.0)
	_update_name_label()
	_update_reload_bar()


## Cargador vacío: cambia de arma si le disparan y tiene otra con balas; si no, recarga
## (si iba con la de reserva, vuelve antes a la principal para recargar esa).
func _on_magazine_empty() -> void:
	if _weapon_stats.size() > 1 and is_under_fire() and try_swap_weapon():
		return
	var prim := primary_weapon_index()
	if active_weapon != prim:
		set_active_weapon(prim)
		if int(stats.magazine) <= 0 or ammo > 0:
			return
	_start_reload()


## Pasado el peligro, vuelve a la principal (y la recarga si está vacía).
func _tick_weapon_return(delta: float) -> void:
	since_hit += delta
	if active_weapon == primary_weapon_index() or reloading:
		return
	_calm_check_t -= delta
	if _calm_check_t > 0.0:
		return
	_calm_check_t = 0.5
	if since_hit > CALM_RETURN_TIME and not _is_targeted():
		set_active_weapon(primary_weapon_index())
		if int(stats.magazine) > 0 and ammo <= 0:
			_start_reload()


## Le disparan mientras recarga la principal: si otra arma tiene balas, la saca en vez de esperar.
func _on_shot_at() -> void:
	since_hit = 0.0
	if not is_battle_started or is_dead or not reloading or reload_left < MIN_RELOAD_TO_CANCEL:
		return
	if ammo <= 0 and try_swap_weapon():
		reloads = maxi(0, reloads - 1) # la recarga no llegó a hacerse


## Alias de compatibilidad (SPEC 8).
func refresh_stats() -> void:
	refresh_from_card()


func _on_roster_changed() -> void:
	if not is_battle_started and not is_dead:
		refresh_from_card()


func _on_troop_leveled(leveled: TroopCard) -> void:
	if not is_battle_started and not is_dead and leveled == card:
		refresh_from_card()


func _on_battle_fight_started() -> void:
	if is_battle_started or has_meta("is_drag_preview"):
		return
	is_dragging = false
	refresh_from_card() # vida al máximo y cargador lleno
	is_battle_started = true
	home_y = global_position.y
	_field = Rect2()
	effects = Effects.new(self)
	effects.on_fight_start()


# ================================================================ arrastre / cuadrícula / clic

func _input(event: InputEvent) -> void:
	if is_battle_started or team != Team.PLAYER or has_meta("is_drag_preview"):
		return
	# Con un menú modal abierto (submenú de personaje) no se arrastra nada
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm and gsm.ui_blocking:
		is_dragging = false
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mouse_pos = get_global_mouse_position()
			if global_position.distance_to(mouse_pos) <= _grab_radius:
				is_dragging = true
				_press_position = mouse_pos
				_drag_origin = global_position
				get_viewport().set_input_as_handled()
		elif is_dragging:
			is_dragging = false
			get_viewport().set_input_as_handled()
			# Soltada sobre la reserva: la tropa vuelve a la reserva con su card (nivel, objetos, habilidades)
			if gsm and _is_over_return_zone():
				gsm.return_troop_to_bench(self)
				return
			_place_on_grid()
			# Un clic sin arrastrar abre el submenú del personaje
			if get_global_mouse_position().distance_to(_press_position) < CLICK_DRAG_TOLERANCE:
				var bus = get_node_or_null("/root/EventBus")
				if bus:
					bus.troop_inspect_requested.emit(self)
	elif event is InputEventMouseMotion and is_dragging:
		global_position = get_global_mouse_position()
		get_viewport().set_input_as_handled()


func _get_grid() -> Node:
	var scene := get_tree().current_scene
	return scene.find_child("DeploymentGrid", true, false) if scene else null


func _is_over_return_zone() -> bool:
	var screen_pos: Vector2 = get_viewport().get_mouse_position()
	for zone in get_tree().get_nodes_in_group("troop_return_zone"):
		if zone is Control and zone.is_visible_in_tree() and zone.get_global_rect().has_point(screen_pos):
			return true
	return false


## Al soltar tras un arrastre: casilla más cercana; si está ocupada, las dos tropas intercambian sitio.
func _place_on_grid() -> void:
	var grid = _get_grid()
	if not grid or not grid.has_method("get_snapped_position"):
		return
	var cell: Vector2 = grid.get_snapped_position(global_position)
	var occupant = grid.get_occupant(cell, self)
	if occupant:
		occupant.global_position = _drag_origin
	global_position = cell


## Ajuste inicial a la cuadrícula: casilla libre más cercana (nunca una ocupada).
func _snap_to_grid() -> void:
	if team != Team.PLAYER or has_meta("is_drag_preview") or not is_inside_tree():
		return
	var grid = _get_grid()
	if grid and grid.has_method("get_nearest_free_position"):
		var free_pos: Vector2 = grid.get_nearest_free_position(global_position, self)
		if free_pos != Vector2.INF:
			global_position = free_pos


# ================================================================ aspecto

func _apply_sprite() -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D")
	if not sprite:
		return
	var tex: Texture2D = card.specialty.texture if card and card.specialty and card.specialty.texture else DEFAULT_TEXTURE
	sprite.texture = tex
	if tex:
		var factor: float = _sprite_height / float(tex.get_height())
		sprite.scale = Vector2(factor, factor)
	var shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape:
		shape.scale = Vector2.ONE * (BOSS_SCALE if card and card.is_boss else 1.0)
	_layout_overlays()


func has_custom_sprite() -> bool:
	return card != null and card.specialty != null and card.specialty.texture != null


## Distancia del centro al borde superior de las barras (para colocar textos encima).
func overlay_top() -> float:
	return _sprite_height * 0.5 + 10.0


func _layout_overlays() -> void:
	# Barra de vida montada sobre la coronilla y el nombre justo encima: así la tropa ocupa
	# poco más que su casilla (80 px) y la etiqueta apenas pisa a la fila de arriba.
	var top: float = -_sprite_height * 0.5 + 4.0
	var bar: Control = get_node_or_null("HealthBar")
	if bar:
		bar.offset_left = -26.0
		bar.offset_right = 26.0
		bar.offset_top = top - 6.0
		bar.offset_bottom = top
	var rbar: Control = get_node_or_null("ReloadBar")
	if rbar:
		rbar.offset_left = -26.0
		rbar.offset_right = 26.0
		rbar.offset_top = top + 1.0
		rbar.offset_bottom = top + 4.0
	# Nombre y nivel en dos líneas cortas sobre las piernas de la propia tropa: quedan dentro de
	# su casilla (80 px) y no pisan a las tropas de la fila de arriba, de abajo ni de los lados.
	var label: Label = get_node_or_null("NameLabel")
	if label:
		var bottom: float = _sprite_height * 0.5
		label.offset_left = -NAME_LABEL_HALF_W
		label.offset_right = NAME_LABEL_HALF_W
		label.offset_top = bottom - 27.0
		label.offset_bottom = bottom - 2.0 # sin tocar la barra de vida de la fila de abajo
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_constant_override("outline_size", 5)
		label.add_theme_constant_override("line_spacing", -4)
	for n in [bar, rbar, label]:
		if n:
			n.z_index = 10 # por encima de los sprites vecinos
	_grab_radius = maxf(32.0, _sprite_height * 0.5)


## Etiqueta en dos líneas cortas, dentro de la casilla: "Nombre" / "Nv.X 🔫".
func _update_name_label() -> void:
	var label: Label = get_node_or_null("NameLabel")
	if not label or not card:
		return
	var w: WeaponData = stats.get("weapon") as WeaponData if not stats.is_empty() else card.get_weapon()
	if w == null:
		w = card.get_weapon()
	var emoji: String = w.emoji if w else ""
	emoji = EMOJI_FALLBACK.get(emoji, emoji)
	var nombre: String = ("☠ " + card.unit_name) if card.is_boss else card.unit_name
	label.text = "%s\nNv.%d %s" % [nombre, card.level, emoji]
	var col: Color = card.specialty.color if card.specialty else Color(1, 1, 1)
	label.add_theme_color_override("font_color", col)


const AMMO_COLOR := Color(0.95, 0.88, 0.55)   # balas que quedan en el cargador
const RELOAD_COLOR := Color(1.0, 0.6, 0.15)   # progreso de la recarga
const AMMO_LOW_COLOR := Color(1.0, 0.4, 0.3)  # quedan pocas balas (≤ 25 %)

var _ammo_fill: StyleBoxFlat


func _style_bars() -> void:
	var rbar: ProgressBar = get_node_or_null("ReloadBar")
	if rbar:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.6)
		_ammo_fill = StyleBoxFlat.new()
		_ammo_fill.bg_color = AMMO_COLOR
		rbar.add_theme_stylebox_override("background", bg)
		rbar.add_theme_stylebox_override("fill", _ammo_fill)


func update_team_color() -> void:
	update_visuals()


## Tinte del equipo + quemadura (naranja) + camuflaje (semitransparente) + destello al recibir daño.
func update_visuals() -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D")
	if not sprite:
		return
	var col: Color = PLAYER_TINT if team == Team.PLAYER else ENEMY_TINT
	if statuses.has("burn"):
		col = col.lerp(BURN_TINT, 0.65)
	if _hurt_flash > 0.0:
		col = col.lerp(Color(1.6, 1.6, 1.6), 0.5)
	sprite.modulate = col
	sprite.flip_h = team == Team.ENEMY
	modulate.a = CAMO_ALPHA if camo_left > 0.0 else 1.0


func update_health_bar() -> void:
	var bar: ProgressBar = get_node_or_null("HealthBar")
	if not bar:
		return
	bar.step = 0.0 # sin redondeo a enteros: la barra refleja la vida exacta
	bar.max_value = get_max_health()
	bar.value = maxf(0.0, health)
	var fg := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fg == null or not bar.has_theme_stylebox_override("fill"):
		fg = StyleBoxFlat.new()
		bar.add_theme_stylebox_override("fill", fg)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.6)
		bar.add_theme_stylebox_override("background", bg)
	fg.bg_color = Color(0.35, 0.85, 0.35) if team == Team.PLAYER else Color(0.9, 0.3, 0.25)


## Barra fina bajo la vida, SIEMPRE visible si el arma tiene cargador: muestra las balas que quedan
## (se pone roja con pocas) y, mientras recarga, el progreso de la recarga en naranja.
func _update_reload_bar() -> void:
	var rbar: ProgressBar = get_node_or_null("ReloadBar")
	if not rbar:
		return
	var mag: int = int(stats.get("magazine", 0))
	rbar.visible = mag > 0 and not is_dead
	if not rbar.visible:
		return
	rbar.max_value = 1.0
	var col: Color = AMMO_COLOR
	if reloading:
		var total: float = maxf(0.01, float(stats.get("reload_time", 1.0)))
		rbar.value = clampf(1.0 - reload_left / total, 0.0, 1.0)
		col = RELOAD_COLOR
	else:
		var frac: float = clampf(float(ammo) / float(mag), 0.0, 1.0)
		rbar.value = frac
		col = AMMO_LOW_COLOR if frac <= 0.25 else AMMO_COLOR
	if _ammo_fill:
		_ammo_fill.bg_color = col


func _fx_parent() -> Node:
	var p := get_parent()
	return p if p else get_tree().current_scene


func show_text(txt: String, color: Color, size: int = 13, offset_y: float = 0.0) -> void:
	var pos := global_position + Vector2(0, -overlay_top() - 34.0 + offset_y)
	pos.y = maxf(pos.y, 12.0)
	CombatFX.text(_fx_parent(), pos, txt, color, size)


func show_heal_text(amount: float) -> void:
	show_text("+%d" % roundi(amount), Color(0.45, 1.0, 0.45), 13)


# ================================================================ getters (IA, estados y UI)

func get_max_health() -> float:
	return float(stats.get("max_health", 100.0))

func get_attack_range() -> float:
	return float(stats.get("attack_range", 150.0))

func get_move_speed() -> float:
	return float(stats.get("move_speed", 90.0))

## Cadencia actual (con los buffs temporales de venganza, oficial, adrenalina...).
func get_fire_rate() -> float:
	var bonus := 0.0
	for k in buffs:
		if buffs[k].stat == "fire_rate_pct":
			bonus += float(buffs[k].value)
	return float(stats.get("fire_rate", 1.0)) * (1.0 + bonus)

## Suma de los buffs temporales activos de una estadística (p. ej. "reload_pct" del Municionero).
func get_buff_total(stat: String) -> float:
	var total := 0.0
	for k in buffs:
		if buffs[k].stat == stat:
			total += float(buffs[k].value)
	return total

func get_attacks_per_second() -> float:
	return get_fire_rate()

## Daño de un impacto (arma × multiplicador de Daño).
func get_damage() -> float:
	return float(stats.get("hit_damage", 10.0))

func get_crit_chance() -> float:
	return float(stats.get("crit_chance", 0.0))

func get_next_level_cost() -> int:
	return card.get_level_up_cost() if card else 30

## Probabilidad de acertar a una distancia. Cada arma tiene una distancia óptima:
##  - más lejos, la precisión cae (accuracy_falloff por cada 100 px);
##  - más cerca, sube hasta +close_bonus a quemarropa (pistola, escopeta, fusil…). El francotirador
##    tiene close_bonus negativo: con la mira telescópica es torpe contra un enemigo encima.
static func hit_chance_for(s: Dictionary, dist: float, bonus: float = 0.0) -> float:
	var opt: float = maxf(1.0, float(s.optimal_range))
	var p: float = float(s.accuracy) + bonus
	if dist < opt:
		p += float(s.get("close_bonus", 0.0)) * (1.0 - dist / opt)
	else:
		p -= float(s.accuracy_falloff) * (dist - opt) / 100.0
	return clampf(p, TroopStats.MIN_ACCURACY, TroopStats.MAX_ACCURACY)


func hit_chance(dist: float, bonus: float = 0.0) -> float:
	return hit_chance_for(stats, dist, bonus)

## Compatibilidad con UI antigua: equipa un objeto en el card.
func equip_item(item: Resource) -> void:
	if card and item is ItemData and card.add_item(item):
		refresh_from_card()
		var bus = get_node_or_null("/root/EventBus")
		if bus:
			bus.roster_changed.emit()


# ================================================================ combate

func _physics_process(delta: float) -> void:
	if not is_battle_started or is_dead:
		velocity = Vector2.ZERO
		return
	_miss_text_cd -= delta
	_dmg_text_t -= delta
	if _dmg_pending > 0.0 and _dmg_text_t <= 0.0:
		_flush_damage_text()
	if _hurt_flash > 0.0:
		_hurt_flash -= delta
		if _hurt_flash <= 0.0:
			update_visuals()
	_tick_buffs(delta)
	_tick_burn(delta)
	if is_dead:
		return
	if camo_left > 0.0:
		camo_left -= delta
		if camo_left <= 0.0:
			update_visuals()
	if effects:
		effects.on_process(delta)
	if reloading:
		reload_left -= delta
		if reload_left <= 0.0:
			reloading = false
			ammo = int(stats.magazine)
			weapon_ammo[active_weapon] = ammo
		_update_reload_bar()
	_tick_weapon_return(delta)
	if attack_cooldown > 0.0:
		attack_cooldown -= delta
	if not ai_enabled:
		velocity = Vector2.ZERO
		return
	_ai_step(delta)


# ================================================================ IA de movimiento (v4)
# Cada tropa:
#  - elige objetivo priorizando a los enemigos de SU carril (la fila donde la desplegaste) y no
#    cambia de objetivo a cada fotograma;
#  - busca una distancia de combate propia de su arma (el cuchillo pega el cuerpo, la pistola y
#    la escopeta se acercan, el fusil se queda a media distancia, el francotirador y la bazuca
#    disparan desde lejos) y se aproxima en arco desde su carril, no en línea recta al centro;
#  - se separa de sus compañeros para no amontonarse;
#  - las armas ligeras disparan mientras avanzan (con menos precisión); las pesadas se paran.

const RETARGET_TIME := 0.35
const LANE_WEIGHT := 0.9          # cuánto pesa la distancia vertical al carril al elegir objetivo
const TARGET_STICKINESS := 0.8    # el objetivo nuevo debe ser un 20 % "mejor" para cambiar
const LANE_HOLD := 0.65           # cuánto se aferra a su carril al acercarse (0 = va directo)
const SEPARATION_RADIUS := 52.0
const SEPARATION_GAIN := 1.1
const MOVE_ACCURACY_PENALTY := 0.12
const FIELD_MARGIN := 16.0
const SUPPRESS_ACCURACY := 0.15   # precisión que pierde una tropa suprimida
const SUPPRESS_SPEED := 0.75      # y su velocidad

var home_y: float = 0.0           # carril (y de su casilla al empezar el combate)
var is_moving: bool = false
var suppressed_left: float = 0.0  # >0 = bajo fuego de supresión (Soldado)
var marked_left: float = 0.0      # >0 = marcada por un radioperador (recibe más daño)
var marked_bonus: float = 0.0
var _retarget_t: float = 0.0
static var _field: Rect2 = Rect2()


## Dirección hacia "su" retaguardia: los jugadores empiezan a la izquierda y los enemigos a la derecha.
func back_dir() -> float:
	return -1.0 if team == Team.PLAYER else 1.0


func is_melee() -> bool:
	return float(stats.get("attack_range", 150.0)) <= 60.0


## Distancia a la que quiere combatir: ligeras se acercan más (disparan mientras avanzan);
## pesadas y de precisión se paran antes; el cuerpo a cuerpo pega el cuerpo.
func engage_distance() -> float:
	var rng_: float = get_attack_range()
	if is_melee():
		return rng_ * 0.7
	var opt: float = minf(float(stats.get("optimal_range", rng_)), rng_)
	var t: float = 0.3 if bool(stats.get("fire_on_move", false)) else 0.6
	return maxf(float(stats.get("min_range", 0.0)) + 20.0, lerpf(opt, rng_, t))


func get_effective_speed() -> float:
	return get_move_speed() * (1.0 + get_buff_total("move_speed_pct")) * (SUPPRESS_SPEED if suppressed_left > 0.0 else 1.0)


## Frenético (adrenalina o venganza): corre y dispara más rápido; se dibuja con un aura y estelas.
func is_frenzied() -> bool:
	return buffs.has("adrenalina") or buffs.has("venganza")


static func field_rect(tree: SceneTree) -> Rect2:
	var g = tree.get_first_node_in_group("deployment_grid") if tree else null
	if g and g.has_method("get_player_rect"):
		var pr: Rect2 = g.get_player_rect()
		var er: Rect2 = g.get_enemy_rect()
		var r := pr.merge(er).grow(FIELD_MARGIN)
		return r
	return Rect2(16, 40, 1120, 460)


func _ai_step(delta: float) -> void:
	var had_marks := suppressed_left > 0.0 or marked_left > 0.0 or is_frenzied() or is_moving
	if suppressed_left > 0.0:
		suppressed_left -= delta
	if marked_left > 0.0:
		marked_left -= delta
	if had_marks or suppressed_left > 0.0 or marked_left > 0.0:
		queue_redraw()
	_retarget_t -= delta
	if not _is_valid_target(target) or _retarget_t <= 0.0:
		find_target()
		_retarget_t = RETARGET_TIME + randf() * 0.15
	var speed := get_effective_speed()
	var sep := _separation()
	var vel := Vector2.ZERO
	if target == null:
		if sep.length() > 0.25:
			vel = sep.limit_length(1.0) * speed * 0.6
		_move(vel, delta)
		return
	var tpos: Vector2 = target.global_position
	var dist := global_position.distance_to(tpos)
	var rng_: float = get_attack_range()
	var min_r: float = float(stats.get("min_range", 0.0))
	var engage := engage_distance()
	# Aproximación en arco desde su carril hasta su distancia de combate (v4.1: sin pasos atrás)
	if dist > engage + 6.0:
		var hold := 0.0 if is_melee() else LANE_HOLD
		var anchor := Vector2(global_position.x, lerpf(global_position.y, home_y, hold))
		var from_t: Vector2 = anchor - tpos
		if from_t.length() < 1.0:
			from_t = Vector2(back_dir(), 0.0)
		var desired: Vector2 = tpos + from_t.normalized() * engage
		vel = global_position.direction_to(desired) * speed
	# 3) Separación de los compañeros
	if sep.length() > 0.0:
		if vel == Vector2.ZERO:
			if sep.length() > 0.3:
				vel = sep.limit_length(1.0) * speed * 0.5
		else:
			vel = (vel + sep * speed * SEPARATION_GAIN).limit_length(speed)
	_move(vel, delta)
	# Disparo. Camuflado: no dispara mientras dure el camuflaje, y quien tiene camuflaje no
	# dispara en marcha: espera a estar a su distancia de combate.
	var in_range: bool = dist <= rng_ and dist >= min_r
	if camo_left > 0.0:
		return
	var stealthy: bool = effects != null and effects.has("camuflaje")
	var may_fire_moving: bool = bool(stats.get("fire_on_move", false)) and not stealthy
	if stealthy and dist > engage + 10.0:
		return
	if in_range and attack_cooldown <= 0.0 and not reloading and (not is_moving or may_fire_moving):
		attack()


## Marcas de estado en el suelo: retícula roja = marcado por radio; anillo azul = suprimido.
func _draw() -> void:
	if not is_battle_started or is_dead:
		return
	var foot := Vector2(0, _sprite_height * 0.42)
	if marked_left > 0.0:
		var r := 22.0 * (1.8 if card and card.is_boss else 1.0)
		draw_arc(foot, r, 0.0, TAU, 28, Color(1.0, 0.25, 0.2, 0.85), 2.0, true)
		for k in 4:
			var d := Vector2.RIGHT.rotated(k * PI * 0.5)
			draw_line(foot + d * (r - 6.0), foot + d * (r + 5.0), Color(1.0, 0.25, 0.2, 0.9), 2.0)
	if suppressed_left > 0.0:
		draw_arc(foot, 16.0, 0.0, TAU, 24, Color(0.6, 0.75, 1.0, 0.55), 2.0, true)
	if is_frenzied():
		# Aura roja que late + estelas de velocidad detrás cuando corre
		var t := Time.get_ticks_msec() / 1000.0
		var pulse := 0.5 + 0.5 * sin(t * 14.0)
		var r := _sprite_height * 0.42
		draw_circle(Vector2(0, -_sprite_height * 0.1), r, Color(1.0, 0.25, 0.1, 0.10 + 0.10 * pulse))
		draw_arc(Vector2(0, -_sprite_height * 0.1), r + 2.0 * pulse, 0.0, TAU, 32, Color(1.0, 0.45, 0.15, 0.55 + 0.3 * pulse), 2.0, true)
		if is_moving and velocity.length() > 1.0:
			var back := -velocity.normalized()
			var side := Vector2(-back.y, back.x)
			for k in 3:
				var o := side * (float(k) - 1.0) * 12.0 + Vector2(0, -_sprite_height * 0.15)
				var l := 14.0 + 10.0 * fmod(t * 6.0 + k * 0.37, 1.0)
				draw_line(o + back * 16.0, o + back * (16.0 + l), Color(1.0, 0.8, 0.5, 0.75), 2.0)
	elif is_moving and float(stats.get("modifiers", {}).get("move_speed_pct", 0.0)) >= 0.15 and velocity.length() > 1.0:
		# Velocista: estelas suaves al correr
		var back2 := -velocity.normalized()
		for k in 2:
			var o2 := Vector2(-back2.y, back2.x) * (float(k) - 0.5) * 12.0 + Vector2(0, -_sprite_height * 0.15)
			draw_line(o2 + back2 * 16.0, o2 + back2 * 28.0, Color(1, 1, 1, 0.45), 1.5)


func _move(vel: Vector2, delta: float) -> void:
	is_moving = vel.length() > 4.0
	if not is_moving:
		velocity = Vector2.ZERO
		still_time += delta
		return
	still_time = 0.0
	if _field.size == Vector2.ZERO or Engine.get_physics_frames() % 120 == 0:
		_field = field_rect(get_tree())
	# No salir del campo de batalla
	var nxt := global_position + vel * delta
	if nxt.x < _field.position.x or nxt.x > _field.end.x:
		vel.x = 0.0
	if nxt.y < _field.position.y or nxt.y > _field.end.y:
		vel.y = 0.0
	velocity = vel
	move_and_slide()


## Empuje para separarse de los compañeros cercanos (suma de vectores, más fuerte cuanto más cerca).
func _separation() -> Vector2:
	var push := Vector2.ZERO
	for t in get_tree().get_nodes_in_group("troops"):
		if t == self or not is_instance_valid(t) or t.is_dead or t.has_meta("is_drag_preview"):
			continue
		if not ("team" in t) or t.team != team:
			continue
		var d: Vector2 = global_position - t.global_position
		var l := d.length()
		if l >= SEPARATION_RADIUS:
			continue
		if l < 0.5:
			d = Vector2(0, 1 if get_instance_id() > t.get_instance_id() else -1)
			l = 0.5
		push += d / l * (1.0 - l / SEPARATION_RADIUS)
	return push


func _closest_enemy(max_dist: float) -> Node:
	var best: Node = null
	var bd := max_dist
	for t in get_tree().get_nodes_in_group("troops"):
		if not _is_valid_target(t):
			continue
		var d := global_position.distance_to(t.global_position)
		if d < bd:
			bd = d
			best = t
	return best


func _is_valid_target(t) -> bool:
	return t != null and is_instance_valid(t) and not t.is_queued_for_deletion() \
			and "team" in t and t.team != team and not t.is_dead and t.camo_left <= 0.0 \
			and not t.has_meta("is_drag_preview")


## Peligrosidad de un enemigo (para el Tirador de élite): su DPS, más si dispara de lejos o cura.
func threat_value() -> float:
	var v: float = float(stats.get("dps", 1.0)) * (1.0 + get_attack_range() / 400.0)
	if card and card.specialty and card.specialty.id in ["medico", "comunicaciones"]:
		v *= 1.5
	return v


## Puntuación de un posible objetivo (menor = mejor): distancia + desvío respecto a su carril.
## Los marcados por un radioperador atraen el fuego.
func target_score(t: Node) -> float:
	var d := global_position.distance_to(t.global_position)
	var sc: float = d + LANE_WEIGHT * absf(t.global_position.y - home_y)
	if t.marked_left > 0.0:
		sc *= 0.7
	return sc


## Elige objetivo: el mejor por carril y distancia (o el más peligroso a tiro, si es Tirador de élite).
## Mantiene el actual salvo que otro sea claramente mejor. Ignora a los camuflados.
func find_target() -> void:
	var cur_valid := _is_valid_target(target)
	var best: Node = null
	var best_sc := INF
	var elite: bool = effects != null and effects.has("tirador_elite")
	var rng_ := get_attack_range()
	var best_threat: Node = null
	var best_tv := -1.0
	for unit in get_tree().get_nodes_in_group("troops"):
		if unit == self or not _is_valid_target(unit):
			continue
		var sc := target_score(unit)
		if sc < best_sc:
			best_sc = sc
			best = unit
		if elite and global_position.distance_to(unit.global_position) <= rng_:
			var tv: float = unit.threat_value() * (1.5 if unit.marked_left > 0.0 else 1.0)
			if tv > best_tv:
				best_tv = tv
				best_threat = unit
	if best_threat != null:
		best = best_threat
		best_sc = 0.0
	if cur_valid and best != target and best != null and best_threat == null:
		if best_sc > target_score(target) * TARGET_STICKINESS:
			return # se queda con el actual
	target = best


func attack() -> void:
	if not _is_valid_target(target) or reloading:
		return
	if int(stats.magazine) > 0 and ammo <= 0:
		_on_magazine_empty()
		return
	var bonus: Dictionary = effects.on_before_shot() if effects else {}
	var w: WeaponData = stats.weapon
	var dist := global_position.distance_to(target.global_position)
	var acc_bonus: float = float(bonus.get("accuracy", 0.0))
	if is_moving:
		acc_bonus -= MOVE_ACCURACY_PENALTY
	if suppressed_left > 0.0:
		acc_bonus -= SUPPRESS_ACCURACY
	var p := hit_chance(dist, acc_bonus)
	var crit_c: float = float(stats.crit_chance) + float(bonus.get("crit_chance", 0.0))
	var base_dmg: float = float(stats.hit_damage) * (1.0 + float(bonus.get("damage_pct", 0.0)))
	shots_fired += 1
	var shot_hits := 0
	# Impacto letal: probabilidad muy baja por disparo (no por perdigón); va en el primer perdigón que acierte
	# v4.1: la probabilidad se reparte por segundo de fuego (antes por disparo: un subfusil a 4,5 disp/s
	# sacaba letales 4,5 veces más que un rifle y los enemigos "morían antes de tiempo")
	var lethal_p: float = Economy.LETHAL_CHANCE / maxf(1.0, get_fire_rate())
	var lethal_pending: bool = (randf() < lethal_p) if force_lethal < 0 else (force_lethal == 1)
	for i in int(stats.pellets):
		pellets_fired += 1
		var hit: bool = (randf() < p) if force_hit < 0 else (force_hit == 1)
		if i < force_hit_pattern.size():
			hit = bool(force_hit_pattern[i])
		var crit: bool = hit and ((randf() < crit_c) if force_crit < 0 else (force_crit == 1))
		var dmg: float = base_dmg * (float(stats.crit_multiplier) if crit else 1.0)
		if hit:
			hits += 1
			shot_hits += 1
		else:
			misses += 1
		if crit:
			crits += 1
		var lethal: bool = hit and lethal_pending
		if lethal:
			lethal_pending = false
			lethals += 1
		_fire_pellet(w, hit, crit, dmg, dist, lethal)
	# "¡Fallo!" solo si no acertó NINGÚN perdigón (una escopeta que da con el central no ha fallado)
	if shot_hits == 0:
		_show_miss()
	if w.projectile == WeaponData.Projectile.LLAMA:
		_fire_cosmetic_flame(dist)
	attack_cooldown = 1.0 / maxf(0.05, get_fire_rate())
	if int(stats.magazine) > 0:
		ammo -= 1
		weapon_ammo[active_weapon] = ammo
		if ammo <= 0:
			_on_magazine_empty()
		_update_reload_bar()


func _hit_info(dmg: float, crit: bool, w: WeaponData, lethal: bool = false) -> Dictionary:
	return {
		"damage": dmg,
		"crit": crit,
		"lethal": lethal,
		"headshot": crit and w.family == WeaponData.Family.PRECISION,
		"burn_dps": float(stats.burn_dps),
		"burn_duration": float(stats.burn_duration),
		"attacker": self,
		"anti_armor": effects != null and effects.has("carga_hueca") and (w.aoe_radius > 0.0),
	}


func _fire_pellet(w: WeaponData, hit: bool, crit: bool, dmg: float, dist: float, lethal: bool = false) -> void:
	var info := _hit_info(dmg, crit, w, lethal)
	var dir := global_position.direction_to(target.global_position)
	if w.projectile == WeaponData.Projectile.NINGUNO:
		# Cuerpo a cuerpo: impacto instantáneo con destello
		if hit:
			CombatFX.flash(_fx_parent(), target.global_position - dir * 8.0, Color(1, 1, 0.85, 0.9), 12.0)
			CombatFX.apply_hit(target, info)
		else:
			CombatFX.flash(_fx_parent(), global_position + dir.rotated(0.6) * 30.0, Color(0.8, 0.8, 0.8, 0.5), 8.0)
		return
	var b = BULLET_SCENE.instantiate()
	b.kind = w.projectile
	b.family = w.family
	b.speed = maxf(150.0, w.projectile_speed)
	if w.projectile == WeaponData.Projectile.LLAMA:
		b.speed = minf(b.speed, 260.0) # chorro más lento para que se vea
	b.shooter_team = team
	b.shooter = self
	b.info = info
	b.aoe_radius = float(stats.aoe_radius)
	b.pierce = int(stats.pierce) if w.projectile == WeaponData.Projectile.BALA else 0
	if int(stats.pellets) > 1:
		b.visual_spread = randf_range(-0.12, 0.12)
	if hit:
		b.target = target
		b.target_pos = target.global_position
	else:
		var dev := randf_range(0.25, 0.45) * (1.0 if randf() < 0.5 else -1.0)
		b.is_miss = true
		b.target_pos = global_position + dir.rotated(dev) * dist
	b.position = global_position + dir * 14.0
	_fx_parent().add_child(b)


## Bocanadas extra (solo visuales) para que el lanzallamas parezca un chorro.
func _fire_cosmetic_flame(dist: float) -> void:
	for i in 3:
		var b = BULLET_SCENE.instantiate()
		b.kind = WeaponData.Projectile.LLAMA
		b.cosmetic = true
		b.is_miss = true
		b.speed = randf_range(190.0, 270.0)
		b.shooter_team = team
		b.shooter = self
		var dir := global_position.direction_to(target.global_position)
		b.target_pos = global_position + dir.rotated(randf_range(-0.28, 0.28)) * minf(dist, get_attack_range()) * randf_range(0.55, 1.0)
		b.position = global_position + dir * 14.0
		_fx_parent().add_child(b)


## Lanza una granada (objeto Granada): vuela en arco y explota donde esté el objetivo.
func throw_grenade(tgt: Node2D, dmg: float, radius: float) -> void:
	var b = BULLET_SCENE.instantiate()
	b.kind = WeaponData.Projectile.GRANADA
	b.speed = 320.0
	b.shooter_team = team
	b.shooter = self
	b.info = {"damage": dmg, "crit": false, "headshot": false, "burn_dps": 0.0, "burn_duration": 0.0, "attacker": self, "grenade": true}
	b.aoe_radius = radius
	b.target = tgt
	b.target_pos = tgt.global_position
	b.position = global_position + Vector2(0, -10)
	_fx_parent().add_child(b)
	grenades_thrown += 1
	show_text("¡Granada!", Color(0.75, 0.9, 0.45), 11, 6.0)


## Una bala que se desvió acabó dando a un enemigo: deja de contar como fallo.
func register_stray_hit() -> void:
	hits += 1
	stray_hits += 1
	misses = maxi(0, misses - 1)


func _show_miss() -> void:
	if _miss_text_cd > 0.0:
		return
	_miss_text_cd = MISS_TEXT_COOLDOWN
	show_text("¡Fallo!", Color(0.75, 0.75, 0.75), 12)


func _start_reload() -> void:
	if reloading or int(stats.magazine) <= 0:
		return
	reloading = true
	reload_left = maxf(0.2, float(stats.reload_time) * (1.0 + get_buff_total("reload_pct")))
	reloads += 1
	_update_reload_bar()


## Llamado por CombatFX.apply_hit cuando un impacto de esta tropa llega a su víctima.
func on_hit_landed(victim: Node, info: Dictionary, killed: bool) -> void:
	if effects:
		effects.on_hit(victim, info)
	if killed:
		kills += 1
		if effects:
			effects.on_kill(victim)


## Recibe un impacto: esquiva → armadura → vida. Devuelve true si muere.
func receive_hit(info: Dictionary) -> bool:
	if is_dead:
		return false
	_on_shot_at()
	# Impacto letal: no se puede esquivar. Mata al instante salvo a los jefes, que reciben ×3.
	if info.get("lethal", false):
		var boss: bool = card != null and card.is_boss
		var lethal_dmg: float = float(info.get("damage", 0.0)) * Economy.LETHAL_BOSS_MULT if boss else health + 1.0
		show_text("☠ ¡IMPACTO LETAL!%s" % (" ×3" if boss else ""), Color(1.0, 0.25, 0.2), 16, -14.0)
		return take_damage(lethal_dmg)
	var dodged: bool = (randf() < float(stats.get("dodge", 0.0))) if force_dodge < 0 else (force_dodge == 1)
	if dodged:
		dodges += 1
		show_text("¡Esquiva!", Color(0.5, 0.9, 1.0), 12)
		return false
	var armor: float = 0.0 if info.get("anti_armor", false) else float(stats.get("armor", 0.0))
	var amount: float = float(info.get("damage", 0.0)) * (1.0 - armor)
	if info.get("anti_armor", false) and card != null and card.is_boss:
		amount *= Effects.ANTI_ARMOR_BOSS_MULT # Zapador (carga hueca) contra jefes
	if marked_left > 0.0:
		amount *= 1.0 + marked_bonus # marcado por un radioperador
	if info.get("crit", false):
		var txt := "¡En la cabeza!" if info.get("headshot", false) else "¡Crítico!"
		show_text(txt, Color(1.0, 0.85, 0.2), 14, -26.0) # el número sale aparte, en blanco
	if float(info.get("burn_dps", 0.0)) > 0.0:
		apply_burn(float(info.burn_dps), maxf(float(info.get("burn_duration", 0.0)), 1.0))
	return take_damage(amount)


## Daño directo a la vida (sin esquiva ni armadura). Devuelve true si muere.
func take_damage(amount: float) -> bool:
	if is_dead:
		return false
	last_damage = amount
	health -= amount
	_dmg_pending += amount
	if health <= 0.0 or _dmg_pending >= get_max_health() * 0.25:
		_flush_damage_text()
	update_health_bar()
	if health <= 0.0:
		if Effects.try_stabilize(self): # un Médico cercano lo estabiliza (una vez por combate)
			update_health_bar()
			return false
		die()
		return true
	_hurt_flash = 0.08
	update_visuals()
	if effects:
		effects.on_damaged(amount)
	return false


## Número de daño blanco sobre la cabeza ("-12"). Los impactos seguidos (subfusil, llamas) se
## agrupan cada DAMAGE_TEXT_INTERVAL para que no se amontonen los textos.
func _flush_damage_text() -> void:
	if _dmg_pending < 0.5:
		_dmg_pending = 0.0
		return
	var pos := global_position + Vector2(randf_range(-8, 8), -overlay_top() - 20.0)
	pos.y = maxf(pos.y, 22.0) # las tropas de la fila de arriba no lo pierden por el borde
	CombatFX.text(_fx_parent(), pos, "-%d" % roundi(_dmg_pending), Color(1, 1, 1), 13, 0.6)
	_dmg_pending = 0.0
	_dmg_text_t = DAMAGE_TEXT_INTERVAL


func heal(amount: float, show_popup: bool = true) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var real := minf(amount, get_max_health() - health)
	if real <= 0.0:
		return 0.0
	health += real
	update_health_bar()
	if show_popup and real >= 0.5:
		show_heal_text(real)
	return real


func apply_burn(dps: float, duration: float) -> void:
	var b: Dictionary = statuses.get("burn", {"dps": 0.0, "left": 0.0, "tick": 0.0})
	b.dps = maxf(float(b.dps), dps)
	b.left = maxf(float(b.left), duration)
	statuses["burn"] = b
	update_visuals()


func _tick_burn(delta: float) -> void:
	if not statuses.has("burn"):
		return
	var b: Dictionary = statuses.burn
	b.left -= delta
	b.tick += delta
	if b.tick >= BURN_TICK:
		b.tick -= BURN_TICK
		var dmg: float = float(b.dps) * BURN_TICK
		burn_damage_taken += dmg
		take_damage(dmg)
	if b.left <= 0.0 and statuses.has("burn"):
		statuses.erase("burn")
		update_visuals()


func add_buff(key: String, stat: String, value: float, duration: float) -> void:
	buffs[key] = {"stat": stat, "value": value, "left": duration}


func _tick_buffs(delta: float) -> void:
	if buffs.is_empty():
		return
	for k in buffs.keys():
		buffs[k].left -= delta
		if buffs[k].left <= 0.0:
			buffs.erase(k)


func die() -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0
	remove_from_group("troops")
	CombatFX.flash(_fx_parent(), global_position, Color(1, 1, 1, 0.5), 26.0, 0.3)
	for t in get_tree().get_nodes_in_group("troops"):
		if is_instance_valid(t) and t != self and "team" in t and t.team == team and t.effects:
			t.effects.on_ally_died(self)
	died.emit(self)
	queue_free()
