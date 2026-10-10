# state.gd
class_name State
extends Node

# Reference to the state machine (set by the StateMachine)
var state_machine: StateMachine

# Called when entering this state
func enter() -> void:
	pass

# Called when leaving this state
func exit() -> void:
	pass

# Called every physics frame while this state is active
func physics_update(delta: float) -> void:
	pass

# Called every frame while this state is active
func update(delta: float) -> void:
	pass
