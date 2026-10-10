class_name StateMachine
extends Node

@export var initial_state: State

var current_state: State

func _ready() -> void:
	for child in get_children():
		if child is State:
			child.state_machine = self
	
	if initial_state:
		current_state = initial_state
		current_state.enter()
	else:
		push_error("Initial state atanmamış!")

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)

func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)

func transition_to(target_state: State) -> void:
	if target_state == null:
		print("❌ HATA: target_state null! Yol yanlış!")
		return
	if current_state == target_state:
		print("⚠️ Zaten bu state'teyiz")
		return
	if current_state:
		current_state.exit()
	current_state = target_state
	current_state.enter()
