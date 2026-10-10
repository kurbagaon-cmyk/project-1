extends CharacterBody3D

# Hareket ayarları
@export var mouse_sensitivity = 0.08
@export var walk_speed = 10.0
@export var run_speed = 18.0
@export var jump_strength = 4.5
@export var turn_speed = 10.0

# Can/Kan
@export var max_health = 100.0
var current_health = 100.0
@export var max_blood = 100.0
var current_blood = 100.0

@onready var hud = get_tree().get_first_node_in_group("hud")
@onready var death_menu = get_tree().get_first_node_in_group("death_menu")

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var speed = 10.0

# Node referansları
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@export var mesh: Node3D
@export var anim_player: AnimationPlayer
@onready var attack_hitbox: Area3D = $AttackHitbox

var camera_yaw = 0.0
var camera_pitch = 0.0
var can_attack = true

# --- KAMERA ZOOM (Skyrim tarzı FP/TP) ---
@export var camera_distance = 4.0       # başlangıç mesafesi (TP)
@export var min_distance = 0.0          # 0 = tam FP
@export var max_distance = 6.0
@export var zoom_step = 0.5
@export var fp_threshold = 0.8          # bu mesafenin altına inince FP moduna geç

var is_first_person = false

# Silah tanımları
enum Weapon { FANGS, KNIFE, CLAW }
var current_weapon = Weapon.FANGS

var weapon_stats = {
	Weapon.FANGS: {"damage": 15.0, "range": 0.8, "duration": 0.15, "cooldown": 0.4},
	Weapon.KNIFE: {"damage": 10.0, "range": 1.2, "duration": 0.2, "cooldown": 0.3},
	Weapon.CLAW:  {"damage": 20.0, "range": 1.0, "duration": 0.25, "cooldown": 0.6}
}

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	attack_hitbox.monitoring = false
	attack_hitbox.body_entered.connect(_on_attack_hit)
	spring_arm.spring_length = camera_distance
	if hud:
		hud.update_health(current_health, max_health)
		hud.update_blood(current_blood, max_blood)

func _input(event):
	if event is InputEventMouseMotion:
		camera_yaw -= event.relative.x * mouse_sensitivity * 0.017453
		camera_pitch -= event.relative.y * mouse_sensitivity * 0.017453
		camera_pitch = clamp(camera_pitch, deg_to_rad(-60), deg_to_rad(60))
		camera_pivot.rotation = Vector3(camera_pitch, camera_yaw, 0)

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			attack()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_camera(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_camera(zoom_step)

	if event.is_action_pressed("weapon_1"):
		switch_weapon(Weapon.FANGS)
	elif event.is_action_pressed("weapon_2"):
		switch_weapon(Weapon.KNIFE)
	elif event.is_action_pressed("weapon_3"):
		switch_weapon(Weapon.CLAW)

func zoom_camera(amount: float):
	camera_distance = clamp(camera_distance + amount, min_distance, max_distance)
	spring_arm.spring_length = camera_distance

	var should_be_first_person = camera_distance <= fp_threshold
	if should_be_first_person != is_first_person:
		is_first_person = should_be_first_person
		if mesh:
			mesh.visible = not is_first_person

func switch_weapon(weapon: Weapon):
	current_weapon = weapon
	var stats = weapon_stats[weapon]
	attack_hitbox.position.z = -stats["range"]

func attack():
	if not can_attack:
		return
	var stats = weapon_stats[current_weapon]
	can_attack = false
	if anim_player:
		anim_player.play("Sword_Attack")
	attack_hitbox.monitoring = true

	await get_tree().create_timer(stats["duration"]).timeout
	attack_hitbox.monitoring = false

	await get_tree().create_timer(stats["cooldown"]).timeout
	can_attack = true

func _on_attack_hit(body):
	if body == self:
		return
	if body.has_method("take_damage"):
		var stats = weapon_stats[current_weapon]
		body.take_damage(stats["damage"])

func take_damage(amount: float):
	current_health -= amount
	current_health = max(current_health, 0)
	if hud:
		hud.update_health(current_health, max_health)
	if current_health <= 0:
		die()

func die():
	if death_menu:
		death_menu.show_death_screen()

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_strength

	if Input.is_action_pressed("run"):
		speed = run_speed
	else:
		speed = walk_speed

	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (camera_pivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	direction.y = 0
	direction = direction.normalized()

	if direction.length() > 0.01:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		if mesh and not is_first_person:
			var target_angle = atan2(direction.x, direction.z)
			mesh.rotation.y = lerp_angle(mesh.rotation.y, target_angle, turn_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	# Animasyon seçimi
	if anim_player:
		if not is_on_floor():
			anim_player.play("Jump")
		elif direction.length() > 0.01:
			if Input.is_action_pressed("run"):
				anim_player.play("Sprint")
			else:
				anim_player.play("Walk")
		else:
			anim_player.play("Idle")

	move_and_slide()

func _unhandled_input(event):
	if event.is_action_pressed("test_damage"):
		take_damage(10)
	if event.is_action_pressed("test_blood"):
		current_blood = max(current_blood - 10, 0)
		if hud:
			hud.update_blood(current_blood, max_blood)
