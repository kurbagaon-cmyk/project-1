extends CharacterBody3D

@export var walk_speed: float = 5.0
@export var run_speed: float = 9.0
@export var jump_strength: float = 5.0
@export var mouse_sensitivity: float = 0.08
@onready var mesh: Node3D = $Mesh
@export var turn_speed: float = 10.0
@onready var camera_pivot: Node3D = $CameraPivot
@onready var anim: AnimationPlayer = $Mesh/AnimationPlayer
@export var lock_on_menzil: float = 15.0
@export var lock_on_kamera_hizi: float = 8.0
@export var lock_on_mesafe: float = 6.5
@export var normal_mesafe: float = 4.0
@export var attack_duration: float = 0.5
var attack_aktif: bool = false
var locked_enemy: Node3D = null
var lock_on_offset_yaw: float = 0.0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var camera_yaw = 0.0
var camera_pitch = 0.0
var shake_siddet: float = 0.0
var orijinal_kamera_pozisyonu: Vector3

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if camera_pivot:
		orijinal_kamera_pozisyonu = camera_pivot.position
	# TEST
	if $Hitbox:
		$Hitbox.area_entered.connect(_test_hitbox_area)
		$Hitbox.body_entered.connect(_test_hitbox_body)
	if $Hitbox:
		$Hitbox.monitoring = false

func _test_hitbox_area(area):
	var dusman = area.get_parent()
	if dusman and dusman.has_method("take_damage"):
		dusman.take_damage(15)
		hit_pause()       # ← zaman donar
		ekran_salla()     # ← kamera sarsılır

func _test_hitbox_body(body):
	if body.has_method("take_damage"):
		body.take_damage(15)

func _input(event):
	if event is InputEventMouseMotion:
		var fare_x = event.relative.x * mouse_sensitivity * 0.017453
		var fare_y = event.relative.y * mouse_sensitivity * 0.017453
		
		if get_locked_enemy():
			lock_on_offset_yaw -= fare_x
			lock_on_offset_yaw = clamp(lock_on_offset_yaw, deg_to_rad(-180), deg_to_rad(180))
			camera_pitch -= fare_y
			camera_pitch = clamp(camera_pitch, deg_to_rad(-60), deg_to_rad(20))
		else:
			camera_yaw -= fare_x
			camera_pitch -= fare_y
			camera_pitch = clamp(camera_pitch, deg_to_rad(-60), deg_to_rad(60))
			camera_pivot.rotation = Vector3(camera_pitch, camera_yaw, 0)
	
	if event.is_action_pressed("lock_on"):
		toggle_lock_on()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			attack()
func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_strength
	
	var speed = run_speed if Input.is_action_pressed("run") else walk_speed
	
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (camera_pivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	direction.y = 0
	direction = direction.normalized()
	
	if direction.length() > 0.01:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	
	# Karakteri hareket yönüne döndür
	if direction.length() > 0.01 and mesh:
		var target_angle = atan2(direction.x, direction.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, target_angle, turn_speed * delta)
	
	# Animasyon
	if anim:
		if attack_aktif:
			pass   # ← Saldırı oynuyor, dokunma!
		elif not is_on_floor():
			anim.play("Jump")
		elif direction.length() > 0.01:
			if Input.is_action_pressed("run"):
				anim.play("Sprint")
			else:
				anim.play("Walk")
		else:
			anim.play("Sword_Idle")
		# LOCK-ON kamera
	var locked = get_locked_enemy()
	if locked:
		var to_enemy = locked.global_position - global_position
		to_enemy.y = 0
		var lock_angle = atan2(to_enemy.x, to_enemy.z)
		var hedef_yaw = lock_angle + lock_on_offset_yaw
		camera_yaw = lerp_angle(camera_yaw, hedef_yaw, lock_on_kamera_hizi * delta)
		camera_pitch = lerp(camera_pitch, deg_to_rad(-15), lock_on_kamera_hizi * delta)
		camera_pivot.rotation = Vector3(camera_pitch, camera_yaw, 0)
	move_and_slide()
func toggle_lock_on():
	if locked_enemy and is_instance_valid(locked_enemy):
		locked_enemy = null
		lock_on_offset_yaw = 0.0
		$CameraPivot/SpringArm3D.spring_length = normal_mesafe
	else:
		locked_enemy = find_nearest_enemy(lock_on_menzil)
		if locked_enemy:
			lock_on_offset_yaw = 0.0
			$CameraPivot/SpringArm3D.spring_length = lock_on_mesafe

func find_nearest_enemy(max_range: float) -> Node3D:
	var enemies = get_tree().get_nodes_in_group("enemy")
	var nearest: Node3D = null
	var nearest_dist = max_range
	for enemy in enemies:
		if not enemy is Node3D:
			continue
		if not is_instance_valid(enemy):
			continue
		var dist = global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest = enemy
			nearest_dist = dist
	return nearest
func get_locked_enemy() -> Node3D:
	if locked_enemy and is_instance_valid(locked_enemy):
		return locked_enemy
	locked_enemy = null
	return null
func kilic_goster(goster: bool) -> void:
	var Sword = find_child("Sword", true, false)
	if Sword:
		Sword.visible = goster
		Sword.invisible = hide
func attack():
	if attack_aktif:
		return
	
	attack_aktif = true
	print("⚔️ SALDIRI!")
	
	# Animasyon
	if anim:
		anim.play("Sword_Attack")
	
	# Hitbox'ı AÇ (animasyon hazırlık süresinden sonra)
	await get_tree().create_timer(0.2).timeout
	if $Hitbox:
		$Hitbox.monitoring = true
		print("🎯 HITBOX AÇILDI")
	
	# Hitbox'ı KAPAT (vuruş süresi bitti)
	await get_tree().create_timer(0.2).timeout
	if $Hitbox:
		$Hitbox.monitoring = false
		print("🎯 HITBOX KAPANDI")
	
	# Cooldown
	await get_tree().create_timer(0.1).timeout
	attack_aktif = false
func _process(delta: float) -> void:
	if shake_siddet > 0.0:
		camera_pivot.position = orijinal_kamera_pozisyonu + Vector3(
			randf_range(-shake_siddet, shake_siddet),
			randf_range(-shake_siddet, shake_siddet),
			randf_range(-shake_siddet, shake_siddet)
		)
		shake_siddet = move_toward(shake_siddet, 0.0, 0.15 * delta)
	else:
		camera_pivot.position = orijinal_kamera_pozisyonu

func ekran_salla(siddet: float = 0.15) -> void:
	shake_siddet = siddet
func hit_pause() -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(0.08, true, false, true).timeout
	Engine.time_scale = 1.0
