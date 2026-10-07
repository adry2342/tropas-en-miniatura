extends Node2D
## Proyectil de combate. El acierto ya se tiró al disparar (troop.gd):
## - acierto: va hacia el objetivo y le hace daño al llegar (con `pierce` sigue y atraviesa más enemigos);
## - fallo: sale desviado. Si una BALA desviada se cruza con alguien en su trayectoria le da igualmente
##   (cuenta como acierto); si es un compañero del tirador, es fuego amigo. Solo las balas: ni las
##   explosiones, ni las llamas, ni el cuerpo a cuerpo dañan a los aliados.
##   Los explosivos fallados estallan donde caen (solo dañan a enemigos).
## El aspecto depende del tipo (BALA según familia, GRANADA en arco, COHETE, LLAMA).

const PIERCE_RADIUS := 16.0
const MISS_EXTRA_TRAVEL := 140.0
const GRENADE_MIN_TIME := 0.35
const EXPLOSION_EDGE := 0.35     # fracción del daño que llega al borde del radio de una explosión
const STRAY_RADIUS := 13.0        # medio cuerpo: una bala desviada a menos de esto impacta
const STRAY_SAFE_TRAVEL := 18.0   # no se comprueba nada justo al salir del cañón

var kind: int = WeaponData.Projectile.BALA
var family: int = WeaponData.Family.PISTOLA
var speed: float = 650.0
var shooter_team: int = 0
var info: Dictionary = {}          # {damage, crit, headshot, burn_dps, burn_duration, attacker}
var target: Node2D = null          # objetivo (solo si acierta)
var target_pos: Vector2 = Vector2.ZERO
var is_miss: bool = false
var aoe_radius: float = 0.0
var pierce: int = 0
var visual_spread: float = 0.0
var cosmetic: bool = false         # solo visual (bocanadas extra del lanzallamas)
var shooter: Node2D = null         # quien disparó (nunca se da a sí mismo)

var _dir: Vector2 = Vector2.RIGHT
var _start: Vector2
var _travel: float = 0.0
var _max_travel: float = 0.0
var _hit_done: bool = false
var _already_hit: Array = []
var _life: float = 0.0
var _flight_time: float = 0.5
var _arc_height: float = 40.0
var _ground: Vector2
var _height: float = 0.0
var _finished: bool = false


func _ready() -> void:
	_start = global_position
	_ground = global_position
	_dir = (target_pos - _start).normalized().rotated(visual_spread)
	if _dir == Vector2.ZERO:
		_dir = Vector2.RIGHT
	rotation = _dir.angle()
	var dist := _start.distance_to(target_pos)
	_max_travel = dist + MISS_EXTRA_TRAVEL
	if kind == WeaponData.Projectile.LLAMA:
		_max_travel = dist + 25.0
	if kind == WeaponData.Projectile.GRANADA:
		_flight_time = maxf(GRENADE_MIN_TIME, dist / maxf(speed, 50.0))
		_arc_height = clampf(dist * 0.35, 25.0, 90.0)
		rotation = 0.0
	z_index = 6


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_life += delta
	match kind:
		WeaponData.Projectile.GRANADA:
			_process_grenade(delta)
		WeaponData.Projectile.COHETE:
			_process_rocket(delta)
		_:
			_process_bullet(delta)
	queue_redraw()


func _target_alive() -> bool:
	return target != null and is_instance_valid(target) and not target.is_queued_for_deletion() and not target.is_dead


func _process_grenade(_delta: float) -> void:
	if not is_miss and _target_alive():
		target_pos = target.global_position # la granada "persigue" un poco el punto del objetivo
	var f := clampf(_life / _flight_time, 0.0, 1.0)
	_ground = _start.lerp(target_pos, f)
	_height = _arc_height * 4.0 * f * (1.0 - f)
	global_position = _ground + Vector2(0, -_height)
	rotation = _life * 10.0
	if f >= 1.0:
		_explode(target_pos)


func _process_rocket(delta: float) -> void:
	if not is_miss and _target_alive():
		target_pos = target.global_position
	var to := target_pos - global_position
	var step := speed * delta
	if to.length() <= step + 6.0:
		global_position = target_pos
		_explode(target_pos)
		return
	_dir = to.normalized()
	rotation = _dir.angle()
	global_position += _dir * step
	if int(_life * 30.0) % 2 == 0:
		CombatFX.flash(get_parent(), global_position - _dir * 12.0, Color(0.7, 0.7, 0.7, 0.45), 6.0, 0.3)


func _process_bullet(delta: float) -> void:
	var step := speed * delta
	# Fase 1: acierto en vuelo hacia el objetivo
	if not is_miss and not _hit_done:
		if _target_alive():
			var to := target.global_position - global_position
			if to.length() <= step + 8.0:
				global_position = target.global_position
				_hit_done = true
				_already_hit.append(target)
				if not cosmetic:
					CombatFX.apply_hit(target, info)
				if kind == WeaponData.Projectile.LLAMA or pierce <= 0:
					_finish()
					return
				return
			_dir = to.normalized().rotated(visual_spread * 0.3)
			rotation = _dir.angle()
		else:
			is_miss = true # el objetivo murió por el camino: sigue recto sin dañar
	global_position += _dir * step
	_travel += step
	# Bala desviada: le da a lo primero que se cruce (enemigo = acierto; aliado = fuego amigo)
	if is_miss and not _hit_done and not cosmetic and kind == WeaponData.Projectile.BALA \
			and _travel >= STRAY_SAFE_TRAVEL and _try_stray_hit():
		return
	# Fase 2: tras el primer impacto, atraviesa enemigos (pierce)
	if _hit_done and pierce > 0 and not cosmetic:
		for e in CombatFX.enemies_in_radius(get_tree(), global_position, PIERCE_RADIUS - 12.0, shooter_team):
			if e in _already_hit:
				continue
			_already_hit.append(e)
			var extra := info.duplicate()
			extra["crit"] = false
			extra["headshot"] = false
			extra["lethal"] = false
			extra["pierced"] = true
			CombatFX.apply_hit(e, extra)
			pierce -= 1
			if pierce <= 0:
				_finish()
				return
	var limit := _max_travel if not _hit_done else _max_travel + 300.0
	if _start.distance_to(global_position) >= limit or _life > 3.0:
		_finish()


## Busca una tropa viva en la trayectoria de la bala desviada y la golpea. Devuelve true si impactó.
func _try_stray_hit() -> bool:
	var victim = null
	var best := STRAY_RADIUS + 1.0
	for t in get_tree().get_nodes_in_group("troops"):
		if not is_instance_valid(t) or t == shooter or t.is_queued_for_deletion() or not ("team" in t):
			continue
		if t.has_meta("is_drag_preview") or t.is_dead:
			continue
		var d: float = t.global_position.distance_to(global_position)
		if d <= STRAY_RADIUS and d < best:
			best = d
			victim = t
	if victim == null:
		return false
	_hit_done = true
	var stray := info.duplicate()
	stray["crit"] = false
	stray["headshot"] = false
	stray["lethal"] = false
	stray["stray"] = true
	if victim.team == shooter_team:
		# Fuego amigo: sin efectos del atacante (robo de vida, rachas…) para no premiarlo
		stray["friendly_fire"] = true
		stray["attacker"] = null
		if victim.has_method("show_text"):
			victim.show_text("¡Fuego amigo!", Color(1.0, 0.55, 0.3), 12, -10.0)
		var att = info.get("attacker")
		if att != null and is_instance_valid(att) and "friendly_hits" in att:
			att.friendly_hits += 1
	else:
		# Se desvió pero le dio a un enemigo: cuenta como acierto
		var att2 = info.get("attacker")
		if att2 != null and is_instance_valid(att2) and att2.has_method("register_stray_hit"):
			att2.register_stray_hit()
	CombatFX.flash(get_parent(), global_position, Color(1, 0.95, 0.7, 0.8), 7.0, 0.12)
	CombatFX.apply_hit(victim, stray)
	_finish()
	return true


func _explode(pos: Vector2) -> void:
	if _finished:
		return
	_finished = true
	var radius := maxf(aoe_radius, 20.0)
	CombatFX.explosion(get_parent(), pos, radius)
	# El impacto letal solo afecta al objetivo principal de la explosión, no a todo el radio.
	# v4: la onda pierde fuerza hacia el borde (EXPLOSION_EDGE en el límite del radio), así un
	# cohete no borra a todo un grupo de golpe.
	for e in CombatFX.enemies_in_radius(get_tree(), pos, radius, shooter_team):
		var primary: bool = is_instance_valid(target) and e == target
		var hit := info.duplicate()
		if not primary:
			hit["lethal"] = false
			var f := clampf(e.global_position.distance_to(pos) / radius, 0.0, 1.0)
			hit["damage"] = float(info.get("damage", 0.0)) * lerpf(1.0, EXPLOSION_EDGE, f)
		CombatFX.apply_hit(e, hit)
	queue_free()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if kind == WeaponData.Projectile.LLAMA:
		CombatFX.flash(get_parent(), global_position, Color(1.0, 0.5, 0.1, 0.6), 12.0, 0.2)
	queue_free()


func _draw() -> void:
	var fade := 1.0
	if is_miss and kind == WeaponData.Projectile.BALA:
		fade = clampf(1.0 - _travel / maxf(_max_travel, 1.0), 0.15, 1.0)
	match kind:
		WeaponData.Projectile.GRANADA:
			# sombra en el suelo + granada verde oliva
			draw_set_transform(Vector2(0, _height).rotated(-rotation), -rotation, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.3))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_circle(Vector2.ZERO, 6.0, Color(0.2, 0.25, 0.12))
			draw_circle(Vector2.ZERO, 4.5, Color(0.38, 0.45, 0.2))
			draw_rect(Rect2(-1.5, -8.0, 3.0, 3.0), Color(0.6, 0.6, 0.55))
		WeaponData.Projectile.COHETE:
			var flick := 0.7 + 0.3 * sin(_life * 60.0)
			draw_colored_polygon(PackedVector2Array([Vector2(-10, -4), Vector2(-20 * flick, 0), Vector2(-10, 4)]), Color(1.0, 0.6, 0.1, 0.9))
			draw_rect(Rect2(-10, -3.5, 16, 7), Color(0.42, 0.45, 0.38))
			draw_colored_polygon(PackedVector2Array([Vector2(6, -3.5), Vector2(12, 0), Vector2(6, 3.5)]), Color(0.85, 0.2, 0.15))
		WeaponData.Projectile.LLAMA:
			var t := clampf(_life / 0.4, 0.0, 1.0)
			var r := lerpf(6.0, 18.0, t)
			var col := Color(1.0, 0.85, 0.3).lerp(Color(0.95, 0.3, 0.05), t)
			col.a = lerpf(0.9, 0.3, t)
			draw_circle(Vector2.ZERO, r, col)
			draw_circle(Vector2.ZERO, r * 0.45, Color(1.0, 0.95, 0.6, col.a))
		_:
			match family:
				WeaponData.Family.PRECISION:
					draw_line(Vector2(-22, 0), Vector2(4, 0), Color(0.7, 0.95, 1.0, 0.35 * fade), 4.0)
					draw_line(Vector2(-18, 0), Vector2(4, 0), Color(1, 1, 1, fade), 2.0)
				WeaponData.Family.ESCOPETA:
					draw_circle(Vector2.ZERO, 3.0, Color(1.0, 0.85, 0.4, fade))
				WeaponData.Family.PESADA, WeaponData.Family.AUTOMATICA:
					draw_line(Vector2(-14, 0), Vector2(3, 0), Color(1.0, 0.65, 0.2, fade), 3.0)
				_:
					draw_line(Vector2(-10, 0), Vector2(2, 0), Color(1.0, 0.95, 0.45, fade), 3.0)
