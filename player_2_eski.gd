extends CharacterBody3D

# ============================================================
# EXPORT
# ============================================================
@export var mouse_sensitivity = 0.08
@export var walk_speed = 10.0
@export var run_speed = 18.0
@export var jump_strength = 4.5
@export var turn_speed = 10.0
@export var max_health = 100.0
@export var max_blood = 100.0
@export var cinematic_distance: float = 2.5

@export var spring_arm: SpringArm3D
@export var mesh: Node3D
@export var anim_player: AnimationPlayer
@export var attack_hitbox: Area3D
@export var facing_pivot: Node3D

@export var camera_distance = 4.0
@export var lock_on_mesafe = 6.5
@export var normal_mesafe = 4.0
@export var min_distance = 0.0
@export var max_distance = 6.0
@export var zoom_step = 0.5
@export var fp_threshold = 0.8

@export var lock_on_menzil = 15.0
@export var lock_on_kamera_hizi = 8.0
@export var combat_range = 12.0

# DODGE
@export var dodge_hizi: float = 15.0
@export var dodge_suresi: float = 0.3
@export var dodge_iframe_suresi: float = 0.4
@export var dodge_cooldown: float = 0.5

# ============================================================
# STATE
# ============================================================
var saldiri_kilidi: bool = false
var vurulan_hedefler: Array = []

var dodge_aktif: bool = false
var dodge_bekleme: float = 0.0
var dodge_yonu: Vector3 = Vector3.ZERO
var iframe_aktif: bool = false

# COMBO
var combo_sayisi: int = 0
var combo_zamanlayici: float = 0.0
var combo_suresi: float = 2.0
var combo_adimi: int = 0

var counter_aktif: bool = false
var counter_suresi: float = 1.5
var counter_zamanlayici: float = 0.0

# GENEL
var current_health = 100.0
var current_blood = 100.0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var speed = 10.0

var camera_yaw = 0.0
var camera_pitch = 0.0
var lock_on_offset_yaw = 0.0
var is_first_person = false
var locked_enemy: Node3D = null
var shake_siddet: float = 0.0
var orijinal_kamera_pozisyonu: Vector3
var in_combat: bool = false

# ============================================================
# SİLAH
# ============================================================
enum Weapon { FANGS, DAGGERS, SWORD }
var current_weapon = Weapon.FANGS

var weapon_stats = {
	Weapon.FANGS:   {"damage": 15.0, "range": 1.5, "hit_delay": 0.3, "duration": 0.4, "cooldown": 0.4, "anim": "Sword_Attack"},
	Weapon.DAGGERS: {"damage": 12.0, "range": 1.8, "hit_delay": 0.3, "duration": 0.4, "cooldown": 0.25, "anim": "Sword_Attack_RM"},
	Weapon.SWORD:   {"damage": 22.0, "range": 2.2, "hit_delay": 0.4, "duration": 0.4, "cooldown": 0.5, "anim": "Sword_Attack"}
}

var combo_animasyonlari = {
	Weapon.FANGS:   ["Sword_Attack", "Sword_Attack_RM", "Sword_Attack"],
	Weapon.DAGGERS: ["Sword_Attack_RM", "Sword_Attack", "Sword_Attack_RM"],
	Weapon.SWORD:   ["Sword_Attack", "Sword_Attack_RM", "Sword_Attack"]
}

var combo_hasar_carpanlari = [1.0, 1.0, 1.5]

# ============================================================
# NODE REF
# ============================================================
@onready var camera_pivot: Node3D = $CameraPivot
@onready var vurus_sesi: AudioStreamPlayer3D = $VurusSesi
@onready var sword_trail: MeshInstance3D = $SwordTrail
@onready var combo_label: Label = get_tree().current_scene.get_node_or_null("CanvasLayer/ComboLabel")

# ============================================================
# READY
# ============================================================
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if attack_hitbox:
		attack_hitbox.monitoring = false
		attack_hitbox.body_entered.connect(_on_attack_hit)
	
	if spring_arm:
		spring_arm.spring_length = camera_distance
	
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.update_health(current_health, max_health)
		hud.update_blood(current_blood, max_blood)
	
	if camera_pivot:
		orijinal_kamera_pozisyonu = camera_pivot.position
	
	kilic_goster(false)

# ============================================================
# INPUT
# ============================================================
func _input(event):
	if event is InputEventMouseMotion:
		var fare_x = event.relative.x * mouse_sensitivity * 0.017453
		var fare_y = event.relative.y * mouse_sensitivity * 0.017453
		
		if locked_enemy and is_instance_valid(locked_enemy):
			lock_on_offset_yaw -= fare_x
			lock_on_offset_yaw = clamp(lock_on_offset_yaw, deg_to_rad(-180), deg_to_rad(180))
			camera_pitch -= fare_y
			camera_pitch = clamp(camera_pitch, deg_to_rad(-60), deg_to_rad(20))
		else:
			camera_yaw -= fare_x
			camera_pitch -= fare_y
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
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dodge()

	if event.is_action_pressed("weapon_1"):
		current_weapon = Weapon.FANGS
		kilic_goster(false)
	elif event.is_action_pressed("weapon_2"):
		current_weapon = Weapon.DAGGERS
		kilic_goster(false)
	elif event.is_action_pressed("weapon_3"):
		current_weapon = Weapon.SWORD
		kilic_goster(true)

	if event.is_action_pressed("lock_on"):
		toggle_lock_on()
	
	if event.is_action_pressed("dodge"):
		dodge()

# ============================================================
# LOCK-ON
# ============================================================
func toggle_lock_on():
	if locked_enemy and is_instance_valid(locked_enemy):
		locked_enemy = null
		lock_on_offset_yaw = 0.0
		camera_distance = normal_mesafe
		if spring_arm:
			spring_arm.spring_length = normal_mesafe
	else:
		locked_enemy = find_nearest_enemy(lock_on_menzil)
		if locked_enemy:
			lock_on_offset_yaw = 0.0
			camera_distance = lock_on_mesafe
			if spring_arm:
				spring_arm.spring_length = lock_on_mesafe
			var to_enemy = locked_enemy.global_position - global_position
			to_enemy.y = 0
			camera_yaw = atan2(to_enemy.x, to_enemy.z)
			camera_pitch = deg_to_rad(-15)
			camera_pivot.rotation = Vector3(camera_pitch, camera_yaw, 0)

func get_locked_enemy() -> Node3D:
	if locked_enemy and is_instance_valid(locked_enemy):
		var hp = locked_enemy.get_node_or_null("Health")
		if hp and hp.can <= 0:
			locked_enemy = null
			camera_distance = normal_mesafe
			if spring_arm:
				spring_arm.spring_length = normal_mesafe
			return null
		return locked_enemy
	locked_enemy = null
	return null

func find_nearest_enemy(max_range: float) -> Node3D:
	var enemies = get_tree().get_nodes_in_group("enemy")
	var nearest: Node3D = null
	var nearest_dist = max_range
	for enemy in enemies:
		if not enemy is Node3D:
			continue
		if not is_instance_valid(enemy):
			continue
		var hp = enemy.get_node_or_null("Health")
		if hp and hp.can <= 0:
			continue
		var dist = global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest = enemy
			nearest_dist = dist
	return nearest

# ============================================================
# COMBAT MODE
# ============================================================
func check_combat_mode() -> void:
	if locked_enemy and is_instance_valid(locked_enemy):
		in_combat = true
		return
	var nearest = find_nearest_enemy(combat_range)
	in_combat = nearest != null

# ============================================================
# KAMERA
# ============================================================
func zoom_camera(amount):
	camera_distance = clamp(camera_distance + amount, min_distance, max_distance)
	if spring_arm:
		spring_arm.spring_length = camera_distance
	var fp = camera_distance <= fp_threshold
	if fp != is_first_person:
		is_first_person = fp
		if mesh:
			mesh.visible = not is_first_person

# ============================================================
# SALDIRI
# ============================================================
func attack():
	if saldiri_kilidi or not attack_hitbox:
		return
	if dodge_aktif:
		return
	
	saldiri_kilidi = true
	vurulan_hedefler.clear()
	
	var stats = weapon_stats[current_weapon]
	attack_hitbox.position.z = -stats["range"]

	var nearest_enemy = get_locked_enemy()
	if not nearest_enemy:
		nearest_enemy = find_nearest_enemy(stats["range"] * 2.0)

	var target_angle = mesh.rotation.y if mesh else 0.0
	if nearest_enemy:
		var to_enemy = nearest_enemy.global_position - global_position
		to_enemy.y = 0
		target_angle = atan2(to_enemy.x, to_enemy.z)

	if mesh:
		mesh.rotation.y = target_angle
	if facing_pivot:
		facing_pivot.rotation.y = target_angle

	var combo_animlar = combo_animasyonlari[current_weapon]
	var anim_adi = combo_animlar[combo_adimi % combo_animlar.size()]
	
	if anim_player:
		anim_player.play(anim_adi)
	
	if sword_trail:
		sword_trail.trail_baslat()
	
	await get_tree().create_timer(stats["hit_delay"]).timeout
	attack_hitbox.monitoring = true
	for body in attack_hitbox.get_overlapping_bodies():
		_on_attack_hit(body)
	await get_tree().create_timer(stats["duration"]).timeout
	attack_hitbox.monitoring = false
	await get_tree().create_timer(stats["cooldown"]).timeout
	
	if sword_trail:
		sword_trail.trail_durdur()
	
	combo_adimi = (combo_adimi + 1) % 3
	saldiri_kilidi = false

# ============================================================
# DODGE
# ============================================================
func dodge():
	if dodge_aktif or dodge_bekleme > 0.0:
		return
	if saldiri_kilidi:
		return
	
	if locked_enemy and is_instance_valid(locked_enemy):
		var sm = locked_enemy.get_node_or_null("StateMachine")
		if sm and sm.current_state and sm.current_state.name == "AttackState":
			var atk_state = sm.current_state
			if "telegraph_aktif" in atk_state and atk_state.telegraph_aktif:
				counter_aktif = true
				counter_zamanlayici = counter_suresi
				_perfect_dodge_efekti()
				if sm.has_node("StaggerState"):
					sm.transition_to(sm.get_node("StaggerState"))
	
	dodge_aktif = true
	iframe_aktif = true
	
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var yon = Vector3.ZERO
	if input_dir.length() > 0.1:
		yon = (camera_pivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	else:
		yon = -global_transform.basis.z
	yon.y = 0
	yon = yon.normalized()
	dodge_yonu = yon
	
	if has_node("DodgeSesi"):
		$DodgeSesi.play()
	
	if mesh:
		var blink = create_tween()
		blink.set_loops(int(dodge_iframe_suresi / 0.08))
		blink.tween_property(mesh, "visible", false, 0.04)
		blink.tween_property(mesh, "visible", true, 0.04)
	
	_afterimage_dongusu()
	
	await get_tree().create_timer(dodge_iframe_suresi).timeout
	iframe_aktif = false
	if mesh:
		mesh.visible = true
	
	var kalan = max(dodge_suresi - dodge_iframe_suresi, 0.05)
	await get_tree().create_timer(kalan).timeout
	dodge_aktif = false
	
	dodge_bekleme = dodge_cooldown

func _perfect_dodge_efekti() -> void:
	ekran_salla(0.2)
	var efekt = get_tree().current_scene.get_node_or_null("VurusEfekti")
	if efekt:
		efekt.flash_goster(Color(1, 0.85, 0.1, 0.5), 0.12)
	Engine.time_scale = 0.15
	await get_tree().create_timer(0.15, true, false, true).timeout
	Engine.time_scale = 1.0

# ============================================================
# AFTERIMAGE
# ============================================================
func _afterimage_dongusu() -> void:
	var gecen = 0.0
	while gecen < dodge_suresi:
		afterimage_olustur()
		await get_tree().create_timer(0.08).timeout
		gecen += 0.08

func afterimage_olustur() -> void:
	if not mesh or not is_instance_valid(mesh):
		return
	
	var kopya = mesh.duplicate()
	kopya.global_transform = mesh.global_transform
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.1, 0.1, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	for child in kopya.find_children("*", "MeshInstance3D", true, false):
		child.material_override = mat
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	get_tree().current_scene.add_child(kopya)
	
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	await tween.finished
	if is_instance_valid(kopya):
		kopya.queue_free()

# ============================================================
# VURUŞ
# ============================================================
func _on_attack_hit(body):
	if body == self:
		return
	if body in vurulan_hedefler:
		return
	if not body.has_method("take_damage"):
		return
	
	vurulan_hedefler.append(body)
	
	var hasar: float = weapon_stats[current_weapon]["damage"]
	
	if counter_aktif:
		hasar *= 1.5
		counter_aktif = false
	
	var carpan = combo_hasar_carpanlari[combo_adimi % combo_hasar_carpanlari.size()]
	hasar *= carpan
	
	var kritik = randf() < 0.15
	if kritik:
		hasar *= 2.0
	
	var finisher = (combo_adimi == 2)
	
	body.take_damage(hasar)
	if body.has_method("hasar_sayisi_goster"):
		body.hasar_sayisi_goster(int(hasar), kritik or finisher)
	
	combo_artir()
	vurus_flash_goster(kritik or finisher)
	
	if finisher:
		ekran_salla(0.35)
		hit_pause_finisher()
	else:
		hit_pause()
		ekran_salla(0.25 if kritik else 0.15)
	
	if vurus_sesi:
		vurus_sesi.play()

func vurus_flash_goster(kritik: bool) -> void:
	var efekt = get_tree().current_scene.get_node_or_null("VurusEfekti")
	if not efekt:
		return
	if kritik:
		efekt.flash_goster(Color(1, 0.9, 0.3, 0.7), 0.1)
	else:
		efekt.flash_goster(Color(1, 1, 1, 0.4), 0.06)

func hit_pause() -> void:
	if Engine.time_scale < 0.5:
		return
	Engine.time_scale = 0.05
	await get_tree().create_timer(0.08, true, false, true).timeout
	Engine.time_scale = 1.0

func hit_pause_finisher() -> void:
	if Engine.time_scale < 0.5:
		return
	Engine.time_scale = 0.03
	await get_tree().create_timer(0.15, true, false, true).timeout
	Engine.time_scale = 1.0

# ============================================================
# HASAR ALMA
# ============================================================
func take_damage(amount):
	if iframe_aktif:
		return
	
	current_health = max(current_health - amount, 0)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.update_health(current_health, max_health)
	
	var efekt = get_tree().current_scene.get_node_or_null("VurusEfekti")
	if efekt:
		efekt.flash_goster(Color(1, 0, 0, 0.4), 0.15)
	
	if current_health <= 0:
		var death_menu = get_tree().get_first_node_in_group("death_menu")
		if death_menu:
			death_menu.show_death_screen()

# ============================================================
# FİZİK
# ============================================================
func _physics_process(delta):
	check_combat_mode()
	
	if dodge_bekleme > 0.0:
		dodge_bekleme -= delta
	
	if dodge_aktif:
		velocity.x = dodge_yonu.x * dodge_hizi
		velocity.z = dodge_yonu.z * dodge_hizi
		move_and_slide()
		return
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_strength

	speed = run_speed if Input.is_action_pressed("run") else walk_speed

	var locked = get_locked_enemy()
	if locked:
		var to_enemy = locked.global_position - global_position
		to_enemy.y = 0
		var lock_angle = atan2(to_enemy.x, to_enemy.z)
		
		if mesh:
			mesh.rotation.y = lock_angle
		if facing_pivot:
			facing_pivot.rotation.y = lock_angle
		
		var hedef_yaw = lock_angle + lock_on_offset_yaw
		camera_yaw = lerp_angle(camera_yaw, hedef_yaw, lock_on_kamera_hizi * delta)
		camera_pitch = lerp(camera_pitch, deg_to_rad(-15), lock_on_kamera_hizi * delta)
		camera_pivot.rotation = Vector3(camera_pitch, camera_yaw, 0)

	if not locked and in_combat:
		var nearest = find_nearest_enemy(combat_range)
		if nearest:
			var to_enemy = nearest.global_position - global_position
			to_enemy.y = 0
			var combat_angle = atan2(to_enemy.x, to_enemy.z)
			if mesh:
				mesh.rotation.y = lerp_angle(mesh.rotation.y, combat_angle, 8.0 * delta)
			if facing_pivot:
				facing_pivot.rotation.y = mesh.rotation.y if mesh else combat_angle

	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (camera_pivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	direction.y = 0
	direction = direction.normalized()

	if direction.length() > 0.01 and not saldiri_kilidi:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		if mesh and not is_first_person and not locked and not in_combat:
			mesh.rotation.y = lerp_angle(mesh.rotation.y, atan2(direction.x, direction.z), turn_speed * delta)
			if facing_pivot:
				facing_pivot.rotation.y = mesh.rotation.y
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	if anim_player:
		if saldiri_kilidi:
			pass
		elif not is_on_floor():
			anim_player.play("Jump")
		elif direction.length() > 0.01:
			if Input.is_action_pressed("run"):
				anim_player.play("Sprint")
			else:
				anim_player.play("Walk")
		else:
			anim_player.play("Sword_Idle")
	
	move_and_slide()

# ============================================================
# SCREEN SHAKE
# ============================================================
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
	
	if combo_zamanlayici > 0.0:
		combo_zamanlayici -= delta
		if combo_zamanlayici <= 0.0:
			combo_sifirla()
	
	if counter_zamanlayici > 0.0:
		counter_zamanlayici -= delta
		if counter_zamanlayici <= 0.0:
			counter_aktif = false

func ekran_salla(siddet: float = 0.15) -> void:
	shake_siddet = siddet

# ============================================================
# COMBO
# ============================================================
func combo_artir() -> void:
	if not combo_label:
		return
	combo_sayisi += 1
	combo_zamanlayici = combo_suresi
	
	if combo_sayisi >= 2:
		combo_label.text = str(combo_sayisi) + "x COMBO!"
		combo_label.modulate.a = 1.0
		
		if combo_sayisi >= 10:
			combo_label.modulate = Color(1, 0.2, 0.2)
		elif combo_sayisi >= 7:
			combo_label.modulate = Color(1, 0.5, 0.1)
		elif combo_sayisi >= 5:
			combo_label.modulate = Color(1, 0.9, 0.2)
		elif combo_sayisi >= 3:
			combo_label.modulate = Color(0.9, 0.9, 1)
		else:
			combo_label.modulate = Color(1, 1, 1)
		
		combo_label.scale = Vector2(1.3, 1.3)
		var tween = create_tween()
		tween.tween_property(combo_label, "scale", Vector2(1.0, 1.0), 0.15)

func combo_sifirla() -> void:
	combo_sayisi = 0
	combo_adimi = 0
	combo_zamanlayici = 0.0
	if combo_label:
		var tween = create_tween()
		tween.tween_property(combo_label, "modulate:a", 0.0, 0.3)

# ============================================================
# SİNEMATİK ZOOM
# ============================================================
func cinematic_zoom_in() -> void:
	if not spring_arm:
		return
	var tween = create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(spring_arm, "spring_length", cinematic_distance, 0.25)

func cinematic_zoom_out() -> void:
	if not spring_arm:
		return
	var tween = create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(spring_arm, "spring_length", camera_distance, 0.4)

# ============================================================
# KILIÇ GÖSTER/GİZLE
# ============================================================
func kilic_goster(goster: bool) -> void:
	var kilic = find_child("Kilic", true, false)
	if kilic:
		kilic.visible = goster

# ============================================================
# TEST
# ============================================================
func _unhandled_input(event):
	if event.is_action_pressed("test_damage"):
		take_damage(10)
	if event.is_action_pressed("test_blood"):
		current_blood = max(current_blood - 10, 0)
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.update_blood(current_blood, max_blood)
