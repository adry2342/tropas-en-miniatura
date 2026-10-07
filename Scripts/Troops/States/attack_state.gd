class_name TroopAttackState
extends State

@export var troop: CharacterBody2D


func physics_update(delta: float) -> void:
	if not troop:
		return
	
	troop.velocity = Vector2.ZERO
	
	if not is_instance_valid(troop.target):
		transitioned.emit(self, "IdleState")
		return
	
	var distance = troop.global_position.distance_to(troop.target.global_position)
	if distance > troop.get_attack_range():
		transitioned.emit(self, "MoveState")
		return
	
	if troop.attack_cooldown > 0:
		troop.attack_cooldown -= delta
	else:
		troop.attack()
