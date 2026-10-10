class_name Mine
extends Node2D
## Mina del Zapador (v4). Se coloca al empezar el combate delante de su casilla y estalla cuando
## un enemigo pasa por encima. Las del jugador se ven (pequeño disco con luz roja); las enemigas
## no se ven hasta que estallan. El daño cae hacia el borde como el resto de explosiones y nunca
## daña a los compañeros de quien la puso.

const ARM_TIME := 0.6

var team: int = 0
var damage: float = 40.0
var radius: float = 70.0
var trigger_radius: float = 30.0
var owner_troop: Node = null
var visible_to_player: bool = true
var _armed_t: float = 0.0
var _blink: float = 0.0
var exploded: bool = false
## Habilidad Trampas (2026-10-10): en vez de explotar es un CEPO que muerde al primero que lo pisa
## (daño pequeño y se queda clavado `root_time` s).
var trap_mode: bool = false
var root_time: float = 2.0


func _ready() -> void:
	z_index = 1
	add_to_group("mines")
	visible = visible_to_player


func _physics_process(delta: float) -> void:
	if exploded:
		return
	_armed_t += delta
	_blink += delta
	queue_redraw()
	if _armed_t < ARM_TIME:
		return
	for t in get_tree().get_nodes_in_group("troops"):
		if not is_instance_valid(t) or t.is_dead or t.has_meta("is_drag_preview") or not ("team" in t):
			continue
		if t.team == team:
			continue
		if t.has_meta("summon"):
			continue
		if t.global_position.distance_to(global_position) <= trigger_radius:
			if trap_mode:
				_bite(t)
			else:
				detonate()
			return


func _bite(t: Node) -> void:
	exploded = true
	var att = owner_troop if is_instance_valid(owner_troop) else null
	CombatFX.flash(get_parent(), global_position, Color(1.0, 0.85, 0.6, 0.7), 16.0, 0.2)
	t.show_text("🪤 ¡Cepo!", Color(1.0, 0.75, 0.4), 12, -4.0)
	if t.has_method("root"):
		t.root(root_time)
	CombatFX.apply_hit(t, {"damage": damage, "lethal": false, "attacker": att, "trap": true})
	queue_free()


func detonate() -> void:
	if exploded:
		return
	exploded = true
	visible = true
	CombatFX.explosion(get_parent(), global_position, radius)
	CombatFX.text(get_parent(), global_position + Vector2(0, -24), "💥 ¡Mina!", Color(1.0, 0.6, 0.2), 13)
	var att = owner_troop if is_instance_valid(owner_troop) else null
	for e in CombatFX.enemies_in_radius(get_tree(), global_position, radius, team):
		var f := clampf(e.global_position.distance_to(global_position) / radius, 0.0, 1.0)
		CombatFX.apply_hit(e, {"damage": damage * lerpf(1.0, 0.35, f), "lethal": false,
				"attacker": att, "anti_armor": true, "mine": true})
	queue_free()


func _draw() -> void:
	if exploded:
		return
	if trap_mode:
		# Cepo: aro metálico con dientes y placa central
		draw_circle(Vector2.ZERO, 11.0, Color(0.08, 0.07, 0.06, 0.95))
		draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 24, Color(0.62, 0.62, 0.58), 2.5, true)
		for i in 10:
			var a := TAU * i / 10.0
			var o := Vector2.RIGHT.rotated(a)
			draw_line(o * 9.0, o * 5.0, Color(0.8, 0.8, 0.75), 1.5)
		draw_circle(Vector2.ZERO, 3.0, Color(0.5, 0.35, 0.2))
		return
	draw_circle(Vector2.ZERO, 8.0, Color(0.16, 0.17, 0.12, 0.95))
	draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 20, Color(0.55, 0.55, 0.45, 0.9), 1.5, true)
	var on := fmod(_blink, 1.0) < 0.5
	draw_circle(Vector2.ZERO, 2.5, Color(1.0, 0.2, 0.15, 1.0 if on else 0.35))
