class_name TroopMoveState
extends State

@export var troop: CharacterBody2D


func physics_update(_delta: float) -> void:
	if not troop:
		return
	
	if not is_instance_valid(troop.target):
		transitioned.emit(self, "IdleState")
		return
	
	var distance = troop.global_position.distance_to(troop.target.global_position)
	if distance <= troop.get_attack_range():
		transitioned.emit(self, "AttackState")
		return
	
	troop.velocity = troop.global_position.direction_to(troop.target.global_position) * troop.get_move_speed()
	troop.move_and_slide()
