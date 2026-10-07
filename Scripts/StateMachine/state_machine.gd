class_name StateMachine
extends Node

signal state_changed(current_state_name: String)

@export var initial_state: State

var current_state: State
var states: Dictionary = {}


func _ready() -> void:
	for child in get_children():
		if child is State:
			states[child.name.to_lower()] = child
			child.transitioned.connect(_on_child_transitioned)
	
	if initial_state:
		initial_state.enter()
		current_state = initial_state


func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)


func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)


func transition_to(new_state_name: String) -> void:
	var target_state: State = states.get(new_state_name.to_lower())
	if not target_state:
		push_warning("State '%s' does not exist in StateMachine!" % new_state_name)
		return
	
	if current_state:
		current_state.exit()
	
	current_state = target_state
	current_state.enter()
	state_changed.emit(current_state.name)


func _on_child_transitioned(state: State, new_state_name: String) -> void:
	if state != current_state:
		return
	
	transition_to(new_state_name)
