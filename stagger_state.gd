extends AIState

@export var sersemleme_suresi: float = 0.5

var anim: AnimationPlayer
var sayac: float = 0.0

func enter() -> void:
	enemy.velocity = Vector3.ZERO
	sayac = sersemleme_suresi
	
	if anim == null:
		anim = enemy.find_child("AnimationPlayer", true, false)
	if anim:
		anim.play("Hit_Chest")
	
	print("DÜŞMAN SERSEMLEDİ")

func physics_update(delta: float) -> void:
	sayac -= delta
	if sayac <= 0.0:
		# Oyuncu hâlâ görünüyorsa ChaseState, yoksa IdleState
		if player:
			state_machine.transition_to($"../ChaseState")
		else:
			state_machine.transition_to($"../IdleState")

func check_transitions() -> void:
	pass
