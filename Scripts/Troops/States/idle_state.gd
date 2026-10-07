class_name TroopIdleState
extends State

@export var troop: CharacterBody2D


func physics_update(_delta: float) -> void:
	if not troop:
		return
	
	troop.velocity = Vector2.ZERO
	troop.find_target()
	
	if is_instance_valid(troop.target):
		var distance = troop.global_position.distance_to(troop.target.global_position)
		if distance <= troop.get_attack_range():
			transitioned.emit(self, "AttackState")
		else:
			transitioned.emit(self, "MoveState")
