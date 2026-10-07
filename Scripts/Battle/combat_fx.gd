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
	var core := FxCircle.new()
	core.color = Color(1.0, 0.62, 0.15, 0.55)
	core.radius = radius * 0.35
	core.position = pos
	core.z_index = 20
	parent.add_child(core)
	var tw := core.create_tween()
	tw.set_parallel(true)
	tw.tween_property(core, "radius", radius, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(core, "modulate:a", 0.0, 0.45).set_delay(0.1)
	tw.chain().tween_callback(core.queue_free)

	var ring := FxCircle.new()
	ring.filled = false
	ring.width = 3.0
	ring.color = Color(1.0, 0.9, 0.5, 0.9)
	ring.radius = radius * 0.5
	ring.position = pos
	ring.z_index = 21
	parent.add_child(ring)
	var tw2 := ring.create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(ring, "radius", radius, 0.2).set_ease(Tween.EASE_OUT)
	tw2.tween_property(ring, "modulate:a", 0.0, 0.5).set_delay(0.15)
	tw2.chain().tween_callback(ring.queue_free)


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
