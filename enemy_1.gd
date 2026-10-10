extends CharacterBody3D

@export var max_health = 50.0
var current_health = 50.0

@export var chase_speed = 8.0
@export var attack_range = 1.5
@export var attack_damage = 10.0
@export var attack_cooldown = 1.0

# Görüş ayarları
@export var vision_angle_degrees = 180.0                                                                                                  
@export var vision_range = 15.0

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var detection_area: Area3D = $DetectionArea
@onready var vision_ray: RayCast3D = $VisionRay

enum State { IDLE, SUSPICIOUS, CHASE, ATTACK, DEAD }
var current_state = State.IDLE

var player: Node3D = null
var can_attack = true
var suspicion_timer = 0.0

func _ready():
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)
	for body in detection_area.get_overlapping_bodies():
		_on_body_entered(body)

func _on_body_entered(body):
	if body.is_in_group("player"):
		player = body

func _on_body_exited(body):
	if body == player:
		player = null
		current_state = State.IDLE

# Bu fonksiyon, oyuncuyu "gerçekten görüp görmediğimizi" kontrol eder
func can_see_player() -> bool:
	if not player:
		return false

	var distance = global_position.distance_to(player.global_position)
	if distance > vision_range:
		return false

	# Açı kontrolü: düşmanın baktığı yön ile oyuncuya olan yön arasındaki fark
	var to_player = (player.global_position - global_position).normalized()
	var facing = -transform.basis.z  # karakterin "ileri" yönü Godot'ta -Z'dir
	var angle = rad_to_deg(facing.angle_to(to_player))
	if angle > vision_angle_degrees / 2.0:
		return false

	# Engel kontrolü: araya duvar giriyor mu?
	vision_ray.target_position = vision_ray.to_local(player.global_position + Vector3.UP * 0.9)
	vision_ray.force_raycast_update()
	if vision_ray.is_colliding():
		var collider = vision_ray.get_collider()
		if collider != player:
			return false  # araya bir şey girmiş, göremiyor

	return true

func take_damage(amount: float):
	current_health -= amount
	current_health = max(current_health, 0)
	if current_health <= 0:
		die()

func die():
	current_state = State.DEAD
	queue_free()

func _physics_process(delta):
	if current_state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	var sees_player = can_see_player()

	match current_state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0, chase_speed)
			velocity.z = move_toward(velocity.z, 0, chase_speed)
			if sees_player:
				current_state = State.CHASE

		State.CHASE:
			if not player:
				current_state = State.IDLE
			elif sees_player:
				var distance = global_position.distance_to(player.global_position)
				if distance <= attack_range:
					current_state = State.ATTACK
				else:
					chase_player(delta)
			else:
				# Görüşü kaybetti, biraz daha kovalamaya devam etsin (opsiyonel basitlik)
				current_state = State.IDLE

		State.ATTACK:
			if not player or not sees_player:
				current_state = State.CHASE
			else:
				var distance = global_position.distance_to(player.global_position)
				if distance > attack_range:
					current_state = State.CHASE
				else:
					attack_player()

	move_and_slide()

func chase_player(delta):
	nav_agent.target_position = player.global_position
	var next_path_position = nav_agent.get_next_path_position()
	var direction = (next_path_position - global_position)
	direction.y = 0
	direction = direction.normalized()

	velocity.x = direction.x * chase_speed
	velocity.z = direction.z * chase_speed

	if direction.length() > 0.01:
		var target_angle = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)

func attack_player():
	velocity.x = 0
	velocity.z = 0
	if can_attack:
		can_attack = false
		if player.has_method("take_damage"):
			player.take_damage(attack_damage)
		await get_tree().create_timer(attack_cooldown).timeout
		can_attack = true
