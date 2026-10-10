extends AIState

@export var min_idle_time: float = 2.0
@export var max_idle_time: float = 5.0

var idle_timer: float = 0.0
var anim: AnimationPlayer

func enter() -> void:
	print("IDLE ENTER")
	if anim == null:
		anim = enemy.find_child("AnimationPlayer", true, false)
	if anim:
		anim.play("Idle")
	enemy.velocity = Vector3.ZERO
	idle_timer = randf_range(min_idle_time, max_idle_time)

func physics_update(delta: float) -> void:
	idle_timer -= delta
	check_transitions()

func check_transitions() -> void:
	if player:
		state_machine.transition_to($"../ChaseState")
		return
	if idle_timer <= 0.0:
		state_machine.transition_to($"../PatrolState")
