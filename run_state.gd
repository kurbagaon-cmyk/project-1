extends State

func enter() -> void:
	var player = owner
	if player.anim:
		player.anim.play("Walk")

func exit() -> void:
	pass

func physics_update(delta: float) -> void:
	var player = owner
	
	# Hareket
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (player.camera_pivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	direction.y = 0
	direction = direction.normalized()
	
	var speed = player.run_speed if Input.is_action_pressed("run") else player.walk_speed
	
	if direction.length() > 0.01:
		player.velocity.x = direction.x * speed
		player.velocity.z = direction.z * speed
		
		# Karakteri hareket yönüne döndür
		if player.mesh:
			var target_angle = atan2(direction.x, direction.z)
			player.mesh.rotation.y = lerp_angle(player.mesh.rotation.y, target_angle, player.turn_speed * delta)
		
		# Animasyon
		if player.anim:
			if Input.is_action_pressed("run"):
				player.anim.play("Sprint")
			else:
				player.anim.play("Walk")
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, speed)
		player.velocity.z = move_toward(player.velocity.z, 0, speed)
	
	player.move_and_slide()
	
	# Durdu → Idle
	if input_dir.length() < 0.1:
		state_machine.transition_to($"../IdleState")
		return
	
	# Zıplama
	if player._zipla_basildi() and player.is_on_floor():
		state_machine.transition_to($"../JumpState")
		return
	
	# Saldırı
	if player.get_meta("attack_pressed", false):
		player.set_meta("attack_pressed", false)
		state_machine.transition_to($"../AttackState")
		return

func update(delta: float) -> void:
	pass
