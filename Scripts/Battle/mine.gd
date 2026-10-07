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
		if t.global_position.distance_to(global_position) <= trigger_radius:
			detonate()
			return


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
		CombatFX.apply_hit(e, {"damage": damage * lerpf(1.0, 0.35, f), "crit": false, "lethal": false,
				"attacker": att, "anti_armor": true, "mine": true})
	queue_free()


func _draw() -> void:
	if exploded:
		return
	draw_circle(Vector2.ZERO, 8.0, Color(0.16, 0.17, 0.12, 0.95))
	draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 20, Color(0.55, 0.55, 0.45, 0.9), 1.5, true)
	var on := fmod(_blink, 1.0) < 0.5
	draw_circle(Vector2.ZERO, 2.5, Color(1.0, 0.2, 0.15, 1.0 if on else 0.35))
