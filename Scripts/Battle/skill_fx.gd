class_name SkillFX
extends RefCounted
## Efectos visuales y pequeños nodos de las habilidades generales (2026-10-10):
## tambor de la Ruleta rusa, mecha de la Cadena de pólvora, orbes de curación, cable trampa,
## granada cegadora y nube de gas. Todo dibujado por código, con el mismo trazo oscuro del juego.

const INK := Color(0.08, 0.07, 0.06, 0.95)



# ================================================================ Ruleta rusa

## Tambor del revólver sobre la cabeza del soldado: 6 recámaras, la del turno se ilumina; una flecha
## dice a quién apunta (a él o al enemigo) y, en el turno del enemigo, una línea roja une a los dos.
class RouletteDrum extends Node2D:
	var shooter: Node2D = null
	var enemy: Node2D = null
	var step: int = -1          # recámara del turno actual (0..5)
	var aim_self: bool = true
	var fired: bool = false     # ha salido la bala
	var _t: float = 0.0
	var _spin: float = 0.0
	var _shake: float = 0.0

	func _ready() -> void:
		top_level = true
		z_index = 20

	func set_step(i: int, at_self: bool) -> void:
		step = i
		aim_self = at_self
		_spin = 1.0
		queue_redraw()

	func bang() -> void:
		fired = true
		_shake = 1.0
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		_spin = maxf(0.0, _spin - delta * 5.0)
		_shake = maxf(0.0, _shake - delta * 3.0)
		if shooter == null or not is_instance_valid(shooter):
			queue_free()
			return
		global_position = shooter.global_position + Vector2(0, -shooter.overlay_top() - 40.0)
		queue_redraw()

	func _draw() -> void:
		var off := Vector2(randf_range(-3, 3), randf_range(-3, 3)) * _shake
		# Línea de tiro hacia el enemigo en su turno
		if not aim_self and enemy != null and is_instance_valid(enemy):
			var to := to_local(enemy.global_position)
			var col := Color(1.0, 0.25, 0.2, 0.85 if fired else 0.35 + 0.25 * sin(_t * 30.0))
			draw_dashed_line(off, to, col, 2.0 if not fired else 4.0, 9.0)
		# Tambor
		var R := 15.0
		draw_circle(off, R + 3.0, INK)
		draw_circle(off, R + 1.0, Color(0.42, 0.44, 0.48))
		draw_circle(off, R - 4.0, Color(0.33, 0.35, 0.38))
		var rot := -PI * 0.5 - _spin * 1.05
		for i in 6:
			var a := rot + TAU * float(i - maxi(step, 0)) / 6.0
			var c := off + Vector2.RIGHT.rotated(a) * (R - 5.0)
			var cur := i == step
			var fill := Color(0.12, 0.12, 0.13)
			if cur:
				fill = Color(1.0, 0.85, 0.3) if not fired else Color(1.0, 0.3, 0.15)
			elif i < step:
				fill = Color(0.24, 0.25, 0.27)
			draw_circle(c, 4.4, INK)
			draw_circle(c, 3.3, fill)
		draw_circle(off, 2.5, INK)
		# A quién apunta: cara (él) o diana (enemigo), a la derecha del tambor
		var tag := off + Vector2(R + 13.0, 0)
		draw_circle(tag, 9.0, INK)
		if aim_self:
			draw_circle(tag, 7.5, Color(0.95, 0.8, 0.6))
			draw_circle(tag + Vector2(-2.5, -1.5), 1.2, INK)
			draw_circle(tag + Vector2(2.5, -1.5), 1.2, INK)
			draw_arc(tag + Vector2(0, 3.5), 2.5, PI, TAU, 8, INK, 1.2)
		else:
			draw_circle(tag, 7.5, Color(0.95, 0.95, 0.95))
			draw_circle(tag, 5.0, Color(0.9, 0.2, 0.15))
			draw_circle(tag, 2.5, Color(0.95, 0.95, 0.95))
		if fired:
			var k := 1.0 - _shake
			draw_arc(off, R + 6.0 + 18.0 * k, 0.0, TAU, 24, Color(1.0, 0.8, 0.3, 1.0 - k), 3.0)


# ================================================================ Cadena de pólvora

## Mecha encendida sobre un cuerpo: chisporrotea y late cada vez más rápido hasta explotar.
class Fuse extends Node2D:
	var life: float = 0.6
	var _t: float = 0.0

	func _ready() -> void:
		z_index = 7

	func _process(delta: float) -> void:
		_t += delta
		if _t >= life:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := _t / maxf(life, 0.01)
		var pulse := 0.5 + 0.5 * sin(_t * (14.0 + 40.0 * k))
		draw_circle(Vector2.ZERO, 10.0 + 10.0 * k, Color(1.0, 0.45, 0.1, 0.15 + 0.3 * pulse))
		draw_circle(Vector2.ZERO, 4.0 + 3.0 * pulse, Color(1.0, 0.85, 0.35, 0.9))
		for i in 4:
			var a := randf() * TAU
			var l := randf_range(5.0, 12.0)
			draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(a) * l, Color(1.0, 0.9, 0.5, 0.9), 1.5)


static func fuse(parent: Node, pos: Vector2, life: float) -> void:
	if parent == null:
		return
	var f := Fuse.new()
	f.life = life
	parent.add_child(f)
	f.global_position = pos


# ================================================================ Te llevas parte de mí

## Orbe verde que vuela del caído al aliado y le cura al llegar.
class HealOrb extends Node2D:
	var target: Node2D = null
	var amount: float = 0.0
	var _from: Vector2
	var _t: float = 0.0
	var _dur: float = 0.55
	var _bend: float = 0.0

	func _ready() -> void:
		z_index = 9
		_from = global_position
		_bend = randf_range(-40.0, 40.0)

	func _process(delta: float) -> void:
		_t += delta
		if target == null or not is_instance_valid(target) or target.is_dead:
			queue_free()
			return
		var k := clampf(_t / _dur, 0.0, 1.0)
		var to := target.global_position
		var mid := (_from + to) * 0.5 + Vector2(0, -60.0) + Vector2(_bend, 0)
		global_position = _from.lerp(mid, k).lerp(mid.lerp(to, k), k)
		queue_redraw()
		if k >= 1.0:
			target.heal(amount)
			CombatFX.flash(get_parent(), to, Color(0.4, 1.0, 0.5, 0.5), 20.0, 0.3)
			queue_free()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 9.0, Color(0.4, 1.0, 0.5, 0.25))
		draw_circle(Vector2.ZERO, 5.0, INK)
		draw_circle(Vector2.ZERO, 3.8, Color(0.5, 1.0, 0.55))


static func heal_orb(parent: Node, from: Vector2, target: Node2D, amount: float) -> void:
	if parent == null:
		return
	var o := HealOrb.new()
	o.target = target
	o.amount = amount
	parent.add_child(o)
	o.global_position = from


# ================================================================ Cable trampa

## Cable tendido entre dos estacas, cruzando el carril. El primer enemigo que lo cruza cae al suelo.
class Tripwire extends Node2D:
	var team: int = 0
	var owner_troop: Node = null
	var a: Vector2 = Vector2(0, -40)
	var b: Vector2 = Vector2(0, 40)
	var stun: float = 1.5
	var downed: float = 4.0
	var lethal: float = 0.08
	var visible_to_player: bool = true
	var _snapped: float = -1.0
	var _armed: float = 0.0

	func _ready() -> void:
		z_index = 1
		visible = visible_to_player

	func _physics_process(delta: float) -> void:
		if _snapped >= 0.0:
			_snapped += delta
			queue_redraw()
			if _snapped > 0.6:
				queue_free()
			return
		_armed += delta
		if _armed < 0.5:
			return
		for t in get_tree().get_nodes_in_group("troops"):
			if not is_instance_valid(t) or t.is_dead or not ("team" in t) or t.team == team or t.has_meta("summon"):
				continue
			var lp := to_local(t.global_position + Vector2(0, 18.0))
			var q := Geometry2D.get_closest_point_to_segment(lp, a, b)
			if lp.distance_to(q) <= 9.0:
				_trip(t)
				return

	func _trip(t: Node) -> void:
		_snapped = 0.0
		visible = true
		t.knockdown(stun, downed, lethal)
		t.show_text("🧵 ¡Al suelo!", Color(1.0, 0.85, 0.5), 12, -4.0)
		CombatFX.flash(get_parent(), t.global_position + Vector2(0, 18), Color(1, 0.9, 0.6, 0.6), 18.0, 0.25)

	func _draw() -> void:
		for p in [a, b]:
			draw_rect(Rect2(p + Vector2(-3, -9), Vector2(6, 14)), INK)
			draw_rect(Rect2(p + Vector2(-2, -8), Vector2(4, 12)), Color(0.55, 0.42, 0.25))
		if _snapped < 0.0:
			draw_line(a + Vector2(0, -4), b + Vector2(0, -4), Color(0.85, 0.85, 0.8, 0.85), 1.5)
		else:
			var k := clampf(_snapped / 0.3, 0.0, 1.0)
			var m := (a + b) * 0.5
			draw_line(a + Vector2(0, -4), a.lerp(m, 1.0 - k) + Vector2(6, 6) * k, Color(0.85, 0.85, 0.8, 1.0 - k * 0.5), 1.5)
			draw_line(b + Vector2(0, -4), b.lerp(m, 1.0 - k) + Vector2(-6, 6) * k, Color(0.85, 0.85, 0.8, 1.0 - k * 0.5), 1.5)


# ================================================================ Granadas especiales

## Granada cegadora: destello blanco enorme y anillos, sin fuego.
class Flashbang extends Node2D:
	var radius: float = 80.0
	var _t: float = 0.0

	func _ready() -> void:
		z_index = 8

	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.6:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := _t / 0.6
		draw_circle(Vector2.ZERO, radius * (0.4 + 0.8 * k), Color(1, 1, 0.92, 0.75 * (1.0 - k)))
		draw_circle(Vector2.ZERO, radius * 0.35 * (1.0 - k), Color(1, 1, 1, 1.0 - k))
		draw_arc(Vector2.ZERO, radius * (0.6 + 0.5 * k), 0.0, TAU, 48, Color(0.8, 0.9, 1.0, 0.8 * (1.0 - k)), 2.0)
		for i in 8:
			var a := TAU * i / 8.0 + 0.2
			draw_line(Vector2.RIGHT.rotated(a) * radius * 0.2, Vector2.RIGHT.rotated(a) * radius * (0.5 + 0.6 * k), Color(1, 1, 0.85, 0.7 * (1.0 - k)), 2.0)


## Nube de gas verde que se queda un rato y se disipa.
class GasCloud extends Node2D:
	var radius: float = 75.0
	var life: float = 3.0
	var _t: float = 0.0
	var _puffs: Array = []

	func _ready() -> void:
		z_index = 5
		for i in 9:
			_puffs.append([Vector2.RIGHT.rotated(randf() * TAU) * randf_range(0.0, radius * 0.7), randf_range(0.35, 0.55) * radius, randf() * TAU])

	func _process(delta: float) -> void:
		_t += delta
		if _t > life:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var grow := clampf(_t / 0.35, 0.0, 1.0)
		var fade := clampf((life - _t) / 1.2, 0.0, 1.0)
		for pf in _puffs:
			var c: Vector2 = pf[0] + Vector2(sin(_t * 1.3 + pf[2]), cos(_t * 1.1 + pf[2])) * 4.0
			draw_circle(c * grow, pf[1] * grow, Color(0.45, 0.8, 0.25, 0.22 * fade))
		draw_arc(Vector2.ZERO, radius * grow, 0.0, TAU, 40, Color(0.5, 0.95, 0.3, 0.35 * fade), 1.5)


static func blast(parent: Node, pos: Vector2, radius: float, style: String) -> void:
	if parent == null:
		return
	match style:
		"flash":
			var f := Flashbang.new()
			f.radius = radius
			parent.add_child(f)
			f.global_position = pos
		"gas":
			var g := GasCloud.new()
			g.radius = radius
			parent.add_child(g)
			g.global_position = pos
		_:
			CombatFX.explosion(parent, pos, radius)
