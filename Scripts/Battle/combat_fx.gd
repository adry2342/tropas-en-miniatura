class_name CombatFX
extends RefCounted
## Efectos visuales cortos del combate (textos flotantes, explosiones, destellos) y el reparto de impactos.
## Todo se libera solo: cada nodo hace un tween y termina con queue_free.

const MAX_TEXTS := 45 # tope de textos flotantes vivos a la vez (rendimiento)

static var _active_texts: int = 0


## Círculo dibujado (relleno o anillo) que se puede animar con tweens.
class FxCircle extends Node2D:
	var color: Color = Color.WHITE
	var filled: bool = true
	var width: float = 3.0
	var radius: float = 10.0:
		set(v):
			radius = v
			queue_redraw()

	func _draw() -> void:
		if filled:
			draw_circle(Vector2.ZERO, radius, color)
		else:
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, color, width, true)


## Texto flotante corto que sube y se desvanece.
static func text(parent: Node, pos: Vector2, txt: String, color: Color, size: int = 13, duration: float = 0.7) -> void:
	if parent == null or not is_instance_valid(parent) or _active_texts >= MAX_TEXTS:
		return
	var label := Label.new()
	label.text = txt
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", size)
	label.size = Vector2(120, 20)
	label.position = pos - Vector2(60, 10) + Vector2(randf_range(-6, 6), 0)
	label.z_index = 100
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	_active_texts += 1
	label.tree_exiting.connect(func(): CombatFX._active_texts -= 1)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 26.0, duration).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, duration * 0.45).set_delay(duration * 0.55)
	tw.chain().tween_callback(label.queue_free)


## Explosión: destello relleno + onda (anillo) del tamaño del radio de daño, que se desvanecen.
static func explosion(parent: Node, pos: Vector2, radius: float) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var scorch := FxScorch.new()
	scorch.radius = radius
	scorch.position = pos
	scorch.z_index = 1
	parent.add_child(scorch)
	var fx := FxExplosion.new()
	fx.radius = radius
	fx.position = pos
	fx.z_index = 20
	parent.add_child(fx)


static func _poly_circle(ci: CanvasItem, c: Vector2, r: float, col: Color, seg: int = 64) -> void:
	if r <= 0.5 or col.a <= 0.0:
		return
	var pts := PackedVector2Array()
	for i in seg:
		pts.append(c + Vector2.from_angle(TAU * i / seg) * r)
	ci.draw_colored_polygon(pts, col)


## Mancha de quemado en el suelo: aparece con la explosión y se va despacio.
class FxScorch extends Node2D:
	var radius: float = 60.0
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= 1.8:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var a := clampf(_t / 0.15, 0.0, 1.0) * clampf(1.0 - (_t - 0.6) / 1.2, 0.0, 1.0) * 0.28
		draw_set_transform(Vector2(0, radius * 0.1), 0.0, Vector2(1.0, 0.42))
		CombatFX._poly_circle(self, Vector2.ZERO, radius * 0.6, Color(0.07, 0.05, 0.04, a))
		CombatFX._poly_circle(self, Vector2.ZERO, radius * 0.35, Color(0.05, 0.03, 0.02, a))


## Explosión: fogonazo blanco, bola de fuego que se vuelve humo y sube, onda expansiva fina hasta
## el radio de daño y chispas. Va dentro de un CanvasGroup: las bocanadas se funden en UNA sola
## nube (sin "aros" de transparencias superpuestas) y se desvanece entera de golpe.
class FxExplosion extends CanvasGroup:
	const DURATION := 0.85
	var radius: float = 60.0
	var t: float = 0.0
	var puffs: Array = []   # [offset, radio, retraso, deriva]
	var sparks: Array = []  # [dirección, distancia, largo]
	var _cloud: Node2D
	var _over: Node2D

	func _ready() -> void:
		for i in 7:
			var a := TAU * i / 7.0 + randf_range(-0.3, 0.3)
			var d := randf_range(0.18, 0.42) * radius
			puffs.append([Vector2.from_angle(a) * d * Vector2(1.0, 0.7), randf_range(0.3, 0.42) * radius, randf_range(0.0, 0.06), randf_range(14.0, 30.0)])
		puffs.append([Vector2.ZERO, 0.52 * radius, 0.0, 22.0])
		for i in 12:
			sparks.append([Vector2.from_angle(randf() * TAU), randf_range(0.8, 1.2) * radius, randf_range(5.0, 11.0)])
		_cloud = _Painter.new(self, 0)
		add_child(_cloud)
		# Onda, fogonazo y chispas van FUERA del grupo (encima y con su propio brillo)
		_over = _Painter.new(self, 1)
		_over.z_index = 21
		get_parent().add_child.call_deferred(_over)

	func _process(delta: float) -> void:
		t += delta
		if is_instance_valid(_over):
			_over.position = position
			_over.queue_redraw()
		if t >= DURATION:
			if is_instance_valid(_over):
				_over.queue_free()
			queue_free()
			return
		var u := t / DURATION
		self_modulate.a = 1.0 if u < 0.5 else clampf(1.0 - (u - 0.5) / 0.5, 0.0, 1.0)
		_cloud.queue_redraw()

	## Estado de cada bocanada: [centro, radio, calor (1 fuego → 0 humo)] o null si aún no salió.
	func _puff_state(pf: Array):
		var lt: float = t - float(pf[2])
		if lt <= 0.0:
			return null
		var k := clampf(lt / (DURATION - float(pf[2])), 0.0, 1.0)
		var grow := 1.0 - pow(1.0 - clampf(lt / 0.15, 0.0, 1.0), 3.0)
		var r: float = float(pf[1]) * (0.35 + 0.65 * grow) * (1.0 + 0.35 * k)
		var c: Vector2 = pf[0] * (0.5 + 0.7 * grow) + Vector2(0, -float(pf[3]) * k * k)
		return [c, r, clampf(1.0 - k * 2.0, 0.0, 1.0)]

	## Tres pasadas (contorno, cuerpo, brillo) para que la nube tenga UN solo contorno exterior.
	func draw_cloud(ci: CanvasItem) -> void:
		var st: Array = []
		for pf in puffs:
			var p = _puff_state(pf)
			if p != null:
				st.append(p)
		for p in st:
			CombatFX._poly_circle(ci, p[0], p[1], Color(0.24, 0.2, 0.2).lerp(Color(0.62, 0.16, 0.04), p[2]))
		for p in st:
			CombatFX._poly_circle(ci, p[0] + Vector2(0, -p[1] * 0.06), p[1] * 0.86, Color(0.45, 0.43, 0.42).lerp(Color(1.0, 0.55, 0.12), p[2]))
		for p in st:
			CombatFX._poly_circle(ci, p[0] + Vector2(-p[1] * 0.2, -p[1] * 0.3), p[1] * 0.42, Color(0.6, 0.58, 0.56).lerp(Color(1.0, 0.9, 0.5), p[2]))

	func draw_over(ci: CanvasItem) -> void:
		# Onda expansiva: anillo fino y redondo que llega justo al radio de daño
		var wave := clampf(t / 0.2, 0.0, 1.0)
		var wr := radius * (1.0 - pow(1.0 - wave, 3.0))
		var wa := 0.8 * (1.0 - clampf((t - 0.1) / 0.22, 0.0, 1.0))
		if wa > 0.0 and wr > 1.0:
			ci.draw_arc(Vector2.ZERO, wr, 0.0, TAU, 64, Color(1.0, 0.93, 0.72, wa), lerpf(3.5, 1.5, wave), true)
		# Fogonazo blanco (muy corto)
		var fl := 1.0 - clampf(t / 0.08, 0.0, 1.0)
		CombatFX._poly_circle(ci, Vector2.ZERO, radius * 0.4, Color(1.0, 0.98, 0.88, fl))
		# Chispas
		var st := clampf(t / 0.32, 0.0, 1.0)
		if st < 1.0:
			for sp in sparks:
				var dir: Vector2 = sp[0]
				var p0: Vector2 = dir * float(sp[1]) * (1.0 - pow(1.0 - st, 2.0))
				ci.draw_line(p0, p0 - dir * float(sp[2]) * (1.0 - st) * 1.6, Color(1.0, 0.85, 0.4, 1.0 - st), 2.0, true)


## Nodo que pinta una capa de la explosión (0 = nube dentro del grupo, 1 = efectos encima).
class _Painter extends Node2D:
	var fx
	var layer: int = 0

	func _init(owner_fx, l: int) -> void:
		fx = owner_fx
		layer = l

	func _draw() -> void:
		if not is_instance_valid(fx):
			return
		if layer == 0:
			fx.draw_cloud(self)
		else:
			fx.draw_over(self)


## Destello pequeño (golpe cuerpo a cuerpo, chispa de impacto, bocanada de humo).
static func flash(parent: Node, pos: Vector2, color: Color = Color(1, 1, 0.8, 0.9), radius: float = 10.0, duration: float = 0.18) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var c := FxCircle.new()
	c.color = color
	c.radius = radius * 0.4
	c.position = pos
	c.z_index = 22
	parent.add_child(c)
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "radius", radius, duration)
	tw.tween_property(c, "modulate:a", 0.0, duration)
	tw.chain().tween_callback(c.queue_free)


## Aplica un impacto a una tropa y avisa al atacante (on_hit / on_kill). Devuelve true si la mató.
static func apply_hit(victim, info: Dictionary) -> bool:
	if victim == null or not is_instance_valid(victim) or victim.is_queued_for_deletion():
		return false
	if not victim.has_method("receive_hit") or victim.is_dead:
		return false
	var killed: bool = victim.receive_hit(info)
	var attacker = info.get("attacker")
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("on_hit_landed"):
		attacker.on_hit_landed(victim, info, killed)
	return killed


## Enemigos (de `shooter_team`) vivos dentro de un radio.
static func enemies_in_radius(tree: SceneTree, pos: Vector2, radius: float, shooter_team: int) -> Array:
	var out: Array = []
	for t in tree.get_nodes_in_group("troops"):
		if not is_instance_valid(t) or t.is_queued_for_deletion() or not ("team" in t) or t.team == shooter_team:
			continue
		if t.has_meta("is_drag_preview") or t.is_dead:
			continue
		if t.global_position.distance_to(pos) <= radius + 12.0: # +12 ≈ medio cuerpo
			out.append(t)
	return out
