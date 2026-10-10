class_name EnemyStateMachine
extends Node

@export var initial_state: AIState

var current_state: AIState
var enemy: CharacterBody3D
var nav_agent: NavigationAgent3D

func _ready() -> void:
	enemy = get_parent() as CharacterBody3D
	if enemy == null:
		push_error("EnemyStateMachine: parent CharacterBody3D değil!")
		return
	
	nav_agent = enemy.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	
	for child in get_children():
		if child is AIState:
			child.state_machine = self
			child.enemy = enemy
			child.nav_agent = nav_agent
			print("✅ STATE BAĞLANDI: ", child.name)
	
	print("INITIAL STATE: ", initial_state)
	if initial_state:
		current_state = initial_state
		current_state.enter()
		print("✅ BAŞLANGIÇ ÇALIŞTI")
	else:
		push_error("❌ INITIAL STATE NULL!")
func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)
	else:
		print("❌ CURRENT STATE NULL")

func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)

func transition_to(target_state: AIState) -> void:
	if target_state == null:
		return
	if current_state == target_state:
		return
	if current_state:
		current_state.exit()
	current_state = target_state
	current_state.enter()
