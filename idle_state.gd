extends State

func enter() -> void:
	var player = owner
	if player.anim:
		player.anim.play("Sword_Idle")

func exit() -> void:
	pass

func physics_update(delta: float) -> void:
	var player = owner
	
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() > 0.1:
		state_machine.transition_to($"../RunState")
		return
	
	if Input.is_action_just_pressed("ui_accept") and player.is_on_floor():
		state_machine.transition_to($"../JumpState")
		return
	
	if player.get_meta("attack_pressed", false):
		player.set_meta("attack_pressed", false)
		state_machine.transition_to($"../AttackState")
		return

func update(delta: float) -> void:
	pass
