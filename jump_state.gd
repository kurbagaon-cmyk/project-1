extends State

func enter() -> void:
	var player = owner
	if player.anim:
		player.anim.play("Jump")
	# Zıplama kuvveti
	player.velocity.y = player.jump_strength

func exit() -> void:
	pass

func physics_update(delta: float) -> void:
	var player = owner
	
	# Havada hareket kontrolü
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (player.camera_pivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	direction.y = 0
	direction = direction.normalized()
	
	var hava_hizi = player.walk_speed * 0.7   # havada %70 hız
	
	if direction.length() > 0.01:
		player.velocity.x = direction.x * hava_hizi
		player.velocity.z = direction.z * hava_hizi
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, 10 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0, 10 * delta)
	
	player.move_and_slide()
	
	# Yere indi mi?
	if player.is_on_floor() and player.velocity.y <= 0:
		var input_dir2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if input_dir2.length() > 0.1:
			state_machine.transition_to($"../RunState")
		else:
			state_machine.transition_to($"../IdleState")
