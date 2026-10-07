class_name TroopDieState
extends State

@export var troop: CharacterBody2D


func enter() -> void:
	if troop:
		troop.velocity = Vector2.ZERO
		troop.died.emit(troop)
		troop.queue_free()
