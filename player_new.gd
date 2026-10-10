extends CharacterBody3D

# EXPORT
@export var walk_speed: float = 5.0
@export var run_speed: float = 9.0
@export var jump_strength: float = 5.0
@export var mouse_sensitivity: float = 0.08
@export var turn_speed: float = 10.0
@export var lock_on_menzil: float = 15.0
@export var lock_on_kamera_hizi: float = 8.0
@export var lock_on_mesafe: float = 6.5
@export var normal_mesafe: float = 4.0
@export var kritik_sansi: float = 0.15    # normal vuruşta kritik olasılığı (0.15 = %15)
@export var kritik_carpani: float = 2.0   # kritik vuruşun hasar çarpanı
@export var sarj_esigi: float = 0.25      # sol tık bu kadar saniye basılı tutulursa şarj başlar
@export var parkur_takla_min_dusus_mesafesi: float = 2.5
@export var dusme_hasar_esigi: float = 7.0
@export var dusme_hasar_carpani: float = 8.0
@export var havada_otomatik_tutunma: bool = true
@onready var radial_menu: CanvasLayer = $RadialMenu
# REFERANSLAR
@onready var mesh: Node3D = $Mesh
@onready var anim: AnimationPlayer = $Mesh/AnimationPlayer
@onready var camera_pivot: Node3D = $CameraPivot
@onready var state_machine: StateMachine = $StateMachine
@onready var hitbox: Area3D = $Hitbox
@onready var raycast_gogus = $RayCast_Gogus
@onready var raycast_bas = $RayCast_Bas
@export var blok_hasar_carpani: float = 0.3
@export var max_kan: float = 100.0
@export var blok_acisi: float = 140.0   # guard'ın önden kapsadığı toplam açı (derece)
@export var model_ileri_z: bool = true
@export var lock_on_gorus_acisi: float = 110.0     # kameranın önünde bu geniş açıdaki düşmanlar kilitlenebilir
@export var lock_on_kopma_mesafesi: float = 22.0   # kilitli düşman bu kadar uzaklaşırsa kilit kopar
@export var lock_on_donus_hizi: float = 14.0       # kilitliyken karakterin düşmana dönme hızı
@export var azami_kan: float = 100.0
var kan: float = 100.0
var kalkan: float = 0.0
var dokunulmaz: bool = false
var parry_durumda: bool = false

# Düşme ve yön hesabı için
var havada_idi: bool = false
var dusus_baslangic_y: float = 0.0

# STATE
var locked_enemy: Node3D = null
var lock_on_offset_yaw: float = 0.0
var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var shake_siddet: float = 0.0
var orijinal_kamera_pozisyonu: Vector3
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_health: float = 100.0
var max_health: float = 100.0
var combo_sayisi: int = 0
var combo_zamanlayici: float = 0.0
var dodge_aktif: bool = false
var dodge_bekleme: float = 0.0
var parry_aktif: bool = false
var parry_basarili_oldu: bool = false
var parry_bekleme: float = 0.0
var saldiri_kilidi: float = 0.0
var parry_mukemmel: bool = false
var blok_aktif: bool = false
var blok_yonu: Vector3 = Vector3.ZERO
var attack_basili: bool = false
var attack_basma_zamani: float = 0.0
var sarj_baslatildi: bool = false
var egiliyor: bool = false
var lock_on_isareti: MeshInstance3D = null
var silah_modu: int = 0   # 0 = kılıç (ana silah), 1 = ateşli silah (ana silah)
var radial_acik: bool = false
var parkur_state: State
var ledge_state: State
var wallrun_state: State
var parkur_bekleme: float = 0.0
# Nişan giriş modları (AimState ile aynı)
const NISAN_NISAN: int = 0
const NISAN_KALCA: int = 1
const NISAN_HIZLI: int = 2
# Tırmanma hızın
var climb_speed = 3.0 
var is_climbing = false
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	orijinal_kamera_pozisyonu = camera_pivot.position
	hitbox.monitoring = false
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_health"):
		hud.update_health(current_health, max_health)
	anim.playback_default_blend_time = 0.15
	process_priority = 100
	_parkur_statelerini_hazirla()
	dusus_baslangic_y = global_position.y
	
	# Başlangıçta menüyü ve içindeki çizimi tamamen gizliyoruz
	if radial_menu:
		radial_menu.visible = false
		if radial_menu.has_node("RadialMenu"):
			radial_menu.get_node("RadialMenu").visible = false

func _input(event):
	# ==== RADIAL MENÜ ====
	# Tab'a basınca açılır (oyun yavaşlar). İmleci dilime götürüp Tab'ı bırak ya da sol tıkla.
	if event.is_action_pressed("weapon_switch"):
		_radial_menuyu_ac()
		return
	if radial_acik:
		var birakildi: bool = event.is_action_released("weapon_switch")
		var tiklandi: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
		if birakildi or tiklandi:
			_radial_menu_secimini_isle(_radial_aktif_dilim())
			_radial_menuyu_kapat()
		return   # menü açıkken diğer girişler (kamera, saldırı) çalışmaz

	if _parkur_ziplama_girdisi(event) and _parkur_dene():
		get_viewport().set_input_as_handled()
		return
	
	# ==== KAMERA ====
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
		print("LOCK-ON TUŞU BASILDI")
		toggle_lock_on()

	# ==== SOL TIK ====
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if silah_modu == 1:
			# Ateşli silah modu: sol tık kalçadan ateş (nişan alıyorsan AimState zaten ateş eder)
			if event.pressed:
				_nisan_dene(NISAN_KALCA)
			return
		if event.pressed:
			attack_basili = true
			attack_basma_zamani = Time.get_ticks_msec() / 1000.0
			sarj_baslatildi = false
		else:
			attack_basili = false
			if not sarj_baslatildi:
				set_meta("attack_pressed", true)

	if InputMap.has_action("crouch") and event.is_action_pressed("crouch"):
		_egilme_dene()

	if InputMap.has_action("dodge") and event.is_action_pressed("dodge"):
		_dodge_dene()
	
	# ==== SAĞ TIK: kılıç modunda parry/blok, ateşli silah modunda nişan ====
	if event.is_action_pressed("parry") or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
		if silah_modu == 1:
			_nisan_dene(NISAN_NISAN)
		else:
			_parry_dene()
			
	if InputMap.has_action("bite") and event.is_action_pressed("bite"):
		_isirma_dene()

	# ==== Q (aim): her iki modda da çalışır ====
	# Kılıç modunda kısa dokunuş = hızlı atış, basılı tutma = nişan. Ateşli modda = nişan.
	if InputMap.has_action("aim") and event.is_action_pressed("aim"):
		_nisan_dene(NISAN_HIZLI if silah_modu == 0 else NISAN_NISAN)

	# ==== DOLDUR ====
	if InputMap.has_action("reload") and event.is_action_pressed("reload"):
		_doldur_dene()
# Büyü değiştirme tuşu (Örn: 'change_spell' eylemi veya radyal menü)
	if event.is_action_pressed("change_spell"):
		$StateMachine/CastState.buyu_dongu()

	# Büyü yapma tuşu (Örn: 'cast' eylemi)
	if event.is_action_pressed("cast"):
		if $StateMachine/CastState.dene():
			state_machine.transition_to($StateMachine/CastState)
	if event is InputEventMouseButton and event.pressed and get_locked_enemy():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			lock_on_hedef_degistir(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			lock_on_hedef_degistir(1)

func _parkur_ziplama_girdisi(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_accept") or (
		InputMap.has_action("jump") and event.is_action_pressed("jump")
	)

func _zipla_basildi() -> bool:
	return (
		(InputMap.has_action("ui_accept") and Input.is_action_just_pressed("ui_accept"))
		or (InputMap.has_action("jump") and Input.is_action_just_pressed("jump"))
	)

func _physics_process(delta):
	if is_climbing:
		# Karakteri yukarı doğru hareket ettir
		velocity.y = climb_speed
	# Kenar Algılama (Ledge Detection) Kontrolü
		if raycast_gogus.is_colliding() and not raycast_bas.is_colliding():
			kenara_tutun_ve_cik()
	# Yerçekimi yalnız bir kez uygulanır; JumpState yatay hareketi ve move_and_slide'ı yönetir.
	if not is_on_floor():
		velocity.y -= gravity * delta
	if attack_basili and not sarj_baslatildi:
		if Time.get_ticks_msec() / 1000.0 - attack_basma_zamani >= sarj_esigi:
			_sarj_dene()
	if parry_bekleme > 0.0:
		parry_bekleme -= delta
	if dodge_bekleme > 0.0:
		dodge_bekleme -= delta
	# Combo zamanlayıcısı işleme
	if combo_zamanlayici > 0.0:
		combo_zamanlayici -= delta
		if combo_zamanlayici <= 0.0:
			combo_sayisi = 0
			var hud = get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("combo_gizle"):
				hud.combo_gizle()

	var locked = get_locked_enemy()
	if locked:
		var to_enemy = locked.global_position - global_position
		to_enemy.y = 0
		var lock_angle = atan2(to_enemy.x, to_enemy.z)
		var hedef_yaw = lock_angle + lock_on_offset_yaw
		camera_yaw = lerp_angle(camera_yaw, hedef_yaw, lock_on_kamera_hizi * delta)
		camera_pitch = lerp(camera_pitch, deg_to_rad(-15), lock_on_kamera_hizi * delta)
		camera_pivot.rotation = Vector3(camera_pitch, camera_yaw, 0)

	if parkur_bekleme > 0.0:
		parkur_bekleme = maxf(parkur_bekleme - delta, 0.0)
	_parkur_dususu_takip_et()
	_parkur_havada_otomatik()

func _parkur_statelerini_hazirla() -> void:
	parkur_state = _parkur_statei_bul_veya_olustur(
		"ParkourState", "res://parkour_state.gd"
	)
	ledge_state = _parkur_statei_bul_veya_olustur(
		"LedgeState", "res://ledge_state.gd"
	)
	wallrun_state = _parkur_statei_bul_veya_olustur(
		"WallRunState", "res://wallrun_state.gd"
	)

func _parkur_statei_bul_veya_olustur(ad: String, yol: String) -> State:
	var mevcut: Node = state_machine.get_node_or_null(ad)
	if mevcut is State:
		var bulunan: State = mevcut as State
		bulunan.state_machine = state_machine
		print("✅ %s bağlandı (sahnede bulundu)" % ad)
		return bulunan

	var script: Script = load(yol) as Script
	if script == null:
		push_warning("%s dosyası bulunamadı: %s" % [ad, yol])
		return null

	var yeni: State = script.new() as State
	if yeni == null:
		push_error("%s, State sınıfından türemiyor: %s" % [ad, yol])
		return null
	yeni.name = ad
	yeni.state_machine = state_machine
	state_machine.add_child(yeni)
	return yeni

func _parkur_dene() -> bool:
	if parkur_bekleme > 0.0:
		return false
	if parkur_state == null or wallrun_state == null:
		_parkur_statelerini_hazirla()
	if dodge_aktif or parry_durumda or radial_acik:
		return false

	var aktif_state: State = state_machine.current_state
	if aktif_state == null:
		return false
	if aktif_state.name not in ["IdleState", "RunState", "JumpState"]:
		return false

	var yon: Vector3 = _parkur_hareket_yonu()
	if parkur_state:
		var plan: Dictionary = parkur_state.call("engel_tara", yon, is_on_floor())
		if not plan.is_empty():
			parkur_state.call("hazirla", plan)
			state_machine.transition_to(parkur_state)
			return true
	if wallrun_state and wallrun_state.has_method("duvar_tara"):
		var duvar_plani: Dictionary = wallrun_state.call(
			"duvar_tara", yon, is_on_floor()
		)
		if not duvar_plani.is_empty():
			wallrun_state.call("hazirla", duvar_plani)
			state_machine.transition_to(wallrun_state)
			return true
	return false

func _parkur_hareket_yonu() -> Vector3:
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var yon: Vector3 = Vector3.ZERO
	if input_dir.length() > 0.1:
		yon = camera_pivot.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	else:
		yon = mesh.global_transform.basis.z
		if not model_ileri_z:
			yon = -yon

	yon.y = 0.0
	if yon.length() > 0.01:
		return yon.normalized()
	return Vector3.FORWARD

func _parkur_dususu_takip_et() -> void:
	if parkur_state == null:
		return
	if dodge_aktif or state_machine.current_state == parkur_state:
		havada_idi = false
		dusus_baslangic_y = global_position.y
		return

	if not is_on_floor():
		if not havada_idi:
			havada_idi = true
			dusus_baslangic_y = global_position.y
		return

	if not havada_idi:
		dusus_baslangic_y = global_position.y
		return

	var dusus_mesafesi: float = dusus_baslangic_y - global_position.y
	havada_idi = false
	if state_machine.current_state == null:
		return
	var uygun_state: bool = state_machine.current_state.name in [
		"IdleState", "RunState", "JumpState"
	]
	var takla_uygun: bool = (
		dusus_mesafesi >= parkur_takla_min_dusus_mesafesi
		and parkur_bekleme <= 0.0
		and uygun_state
	)
	if dusus_mesafesi >= dusme_hasar_esigi:
		var hasar: int = roundi(dusus_mesafesi * dusme_hasar_carpani)
		if takla_uygun:
			hasar = roundi(hasar * 0.5)
		if hasar > 0:
			take_damage(hasar)
			if current_health <= 0.0:
				return
	if not takla_uygun:
		return

	parkur_state.call("hazirla", {
		"tip": "takla",
		"yon": _parkur_hareket_yonu()
	})
	state_machine.transition_to(parkur_state)

func _parkur_havada_otomatik() -> void:
	if not havada_otomatik_tutunma or is_on_floor():
		return
	if dodge_aktif or parry_durumda or radial_acik or parkur_bekleme > 0.0:
		return
	if state_machine.current_state == null:
		return
	if state_machine.current_state.name not in ["IdleState", "RunState", "JumpState"]:
		return
	if parkur_state == null or wallrun_state == null:
		return

	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() < 0.1:
		return
	var yon: Vector3 = _parkur_hareket_yonu()
	var plan: Dictionary = parkur_state.call("engel_tara", yon, false)
	if not plan.is_empty():
		parkur_state.call("hazirla", plan)
		state_machine.transition_to(parkur_state)
		return

	var duvar_plani: Dictionary = wallrun_state.call("duvar_tara", yon, false)
	if not duvar_plani.is_empty():
		wallrun_state.call("hazirla", duvar_plani)
		state_machine.transition_to(wallrun_state)

func _process(delta):
	_lock_on_yuz_don(delta)
	if shake_siddet > 0.0:
		camera_pivot.position = orijinal_kamera_pozisyonu + Vector3(
			randf_range(-shake_siddet, shake_siddet),
			randf_range(-shake_siddet, shake_siddet),
			randf_range(-shake_siddet, shake_siddet)
		)
		shake_siddet = move_toward(shake_siddet, 0.0, 0.15 * delta)
	else:
		camera_pivot.position = orijinal_kamera_pozisyonu

# ============================================================
# RADIAL MENÜ
# Dilimler (saat yönünde, sağdan başlayarak): 0 Silah, 1 Ateşli Silah Modu, 2 Vampir Özellikleri, 3 Büyü
# ============================================================
func _radial_menuyu_ac() -> void:
	if radial_menu == null or radial_acik or dodge_aktif:
		return
	radial_acik = true
	Engine.time_scale = 0.1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	radial_menu.visible = true
	if radial_menu.has_node("RadialMenu"):
		radial_menu.get_node("RadialMenu").visible = true

func _radial_menuyu_kapat() -> void:
	radial_acik = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if radial_menu:
		radial_menu.visible = false
		if radial_menu.has_node("RadialMenu"):
			radial_menu.get_node("RadialMenu").visible = false

func _radial_aktif_dilim() -> int:
	if radial_menu == null:
		return -1
	var ic_menu = radial_menu.get_node_or_null("RadialMenu")
	if ic_menu == null:
		return -1
	var dilim = ic_menu.get("active_slice")
	return int(dilim) if dilim != null else -1

func _radial_menu_secimini_isle(dilim: int) -> void:
	print("Seçilen dilim: ", dilim)
	match dilim:
		0:
			silah_modu_degistir()
		1:
			durus_degistir()
		2:
			_yakinda_bildir("VAMPİR ÖZELLİKLERİ: yakında")
		3:
			buyu_degistir()
func buyu_degistir() -> void:
	var cast_state = get_node_or_null("StateMachine/CastState")
	if cast_state:
		cast_state.buyu_dongu()
func _yakinda_bildir(metin: String) -> void:
	var nisan_state = state_machine.get_node_or_null("AimState")
	if nisan_state:
		nisan_state.bildirim(metin, Color(0.75, 0.75, 0.75))

# Ana silahı değiştirir: kılıç <-> ateşli silah
func silah_modu_degistir() -> void:
	var nisan_state = state_machine.get_node_or_null("AimState")
	if nisan_state == null:
		print("⚠️ AimState bulunamadı")
		return
	if dodge_aktif:
		return
	if silah_modu == 0:
		silah_modu = 1
		kilic_goster(false)
		var d = nisan_state.durus_tablosu[nisan_state.aktif_durus]
		nisan_state.bildirim("ANA SİLAH: ATEŞLİ (" + d["ad"] + ")", d["renk"])
	else:
		silah_modu = 0
		kilic_goster(true)
		nisan_state.bildirim("ANA SİLAH: KILIÇ", Color(1, 1, 1))

# Ateşli silahın duruşunu değiştirir (Hızlı -> Ağır -> Karanlık). İki modda da çalışır.
func durus_degistir() -> void:
	var nisan_state = state_machine.get_node_or_null("AimState")
	if nisan_state == null:
		print("⚠️ AimState bulunamadı")
		return
	nisan_state.durus_dongu()
	var d = nisan_state.durus_tablosu[nisan_state.aktif_durus]
	nisan_state.bildirim("DURUŞ: " + d["ad"], d["renk"])

# ============================================================
# LOCK-ON
# ============================================================
func toggle_lock_on():
	if locked_enemy and is_instance_valid(locked_enemy):
		print("Lock-on KAPALI")
		_lock_on_birak()
	else:
		var hedef = find_nearest_enemy(lock_on_menzil)
		if hedef:
			print("Lock-on AÇIK: ", hedef.name)
			_lock_on_kilitle(hedef)
		else:
			print("Lock-on: görüş alanında düşman yok")

func find_nearest_enemy(max_range: float) -> Node3D:
	var kamera: Camera3D = get_viewport().get_camera_3d()
	var en_iyi: Node3D = null
	var en_iyi_skor: float = INF
	for d in get_tree().get_nodes_in_group("enemy"):
		if not _hedef_gecerli(d, max_range, true):
			continue
		var m: float = global_position.distance_to(d.global_position)
		var aci: float = 0.0
		if kamera:
			var yon: Vector3 = (d.global_position - kamera.global_position).normalized()
			aci = rad_to_deg((-kamera.global_transform.basis.z).angle_to(yon))
		var skor: float = m * (1.0 + aci / 60.0)
		if skor < en_iyi_skor:
			en_iyi_skor = skor
			en_iyi = d
	return en_iyi

func get_locked_enemy() -> Node3D:
	if locked_enemy == null or not is_instance_valid(locked_enemy):
		if locked_enemy != null:
			_lock_on_birak()
		return null
	if _hedef_gecerli(locked_enemy, lock_on_kopma_mesafesi, false):
		return locked_enemy
	var yeni = find_nearest_enemy(lock_on_menzil)
	if yeni and yeni != locked_enemy:
		_lock_on_kilitle(yeni)
		return yeni
	_lock_on_birak()
	return null

func _hedef_gecerli(d, menzil: float, gorus_sart: bool) -> bool:
	if d == null or not is_instance_valid(d) or not (d is Node3D):
		return false
	var saglik = d.get("health")
	if saglik and saglik.get("can") != null and saglik.get("can") <= 0:
		return false
	if global_position.distance_to(d.global_position) > menzil:
		return false
	if not gorus_sart:
		return true
	var kamera: Camera3D = get_viewport().get_camera_3d()
	if kamera:
		var kam_ileri: Vector3 = -kamera.global_transform.basis.z
		var yon: Vector3 = d.global_position - kamera.global_position
		if yon.length() > 0.01 and rad_to_deg(kam_ileri.angle_to(yon.normalized())) > lock_on_gorus_acisi * 0.5:
			return false
	var haric: Array[RID] = [get_rid()]
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is CollisionObject3D:
			haric.append(e.get_rid())
	var space_state = get_world_3d().direct_space_state
	if space_state == null:
		return false
	var sorgu: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.2, 0), d.global_position + Vector3(0, 1.2, 0))
	sorgu.exclude = haric
	return space_state.intersect_ray(sorgu).is_empty()

func _lock_on_kilitle(hedef: Node3D) -> void:
	locked_enemy = hedef
	lock_on_offset_yaw = 0.0
	var spring_arm = $CameraPivot/SpringArm3D if has_node("CameraPivot/SpringArm3D") else null
	if spring_arm:
		spring_arm.spring_length = lock_on_mesafe
	_isaret_koy(hedef)

func _lock_on_birak() -> void:
	locked_enemy = null
	lock_on_offset_yaw = 0.0
	var spring_arm = $CameraPivot/SpringArm3D if has_node("CameraPivot/SpringArm3D") else null
	if spring_arm:
		spring_arm.spring_length = normal_mesafe
	_isaret_kaldir()

func _isaret_koy(hedef: Node3D) -> void:
	_isaret_kaldir()
	if hedef == null or not is_instance_valid(hedef):
		return
	var m: MeshInstance3D = MeshInstance3D.new()
	var kure: SphereMesh = SphereMesh.new()
	kure.radius = 0.1
	kure.height = 0.2
	m.mesh = kure
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.1, 0.15)
	mat.no_depth_test = true
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hedef.add_child(m)
	m.position = Vector3(0, 2.4, 0)
	lock_on_isareti = m

func _isaret_kaldir() -> void:
	if lock_on_isareti != null and is_instance_valid(lock_on_isareti):
		lock_on_isareti.queue_free()
	lock_on_isareti = null

func _lock_on_yuz_don(delta: float) -> void:
	var hedef = get_locked_enemy()
	if hedef == null or dodge_aktif or parry_durumda:
		return
	var f: Vector3 = hedef.global_position - global_position
	f.y = 0.0
	if f.length() < 0.05:
		return
	f = f.normalized()
	var aci: float = atan2(f.x, f.z)
	if not model_ileri_z:
		aci += PI
	mesh.global_rotation.y = lerp_angle(mesh.global_rotation.y, aci, clampf(lock_on_donus_hizi * delta, 0.0, 1.0))

func lock_on_hedef_degistir(yon: int) -> void:
	var kilitli = get_locked_enemy()
	var kamera: Camera3D = get_viewport().get_camera_3d()
	if kilitli == null or kamera == null:
		return
	var kam_sag: Vector3 = kamera.global_transform.basis.x
	var adaylar: Array = []
	for d in get_tree().get_nodes_in_group("enemy"):
		if not _hedef_gecerli(d, lock_on_menzil, true):
			continue
		var v: Vector3 = d.global_position - kamera.global_position
		v.y = 0.0
		adaylar.append({"d": d, "x": v.normalized().dot(kam_sag)})
	adaylar.sort_custom(func(a, b): return a["x"] < b["x"])
	var idx: int = -1
	for i in adaylar.size():
		if adaylar[i]["d"] == kilitli:
			idx = i
	var yeni_idx: int = idx + yon
	if idx == -1 or yeni_idx < 0 or yeni_idx >= adaylar.size():
		return
	_lock_on_kilitle(adaylar[yeni_idx]["d"])

# ============================================================
# FEEDBACK
# ============================================================
func hit_pause() -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(0.08, true, false, true).timeout
	Engine.time_scale = 1.0

func ekran_salla(siddet: float = 0.15) -> void:
	shake_siddet = maxf(shake_siddet, siddet)

func kilic_goster(goster: bool) -> void:
	var Sword = find_child("Sword", true, false)
	if Sword:
		Sword.visible = goster

# ============================================================
# EYLEMLER (state'lere geçiş)
# ============================================================
func _dodge_dene() -> void:
	if dodge_aktif or dodge_bekleme > 0.0 or not is_on_floor():
		return
	var dodge_state = state_machine.get_node_or_null("DodgeState")
	if dodge_state:
		state_machine.transition_to(dodge_state)
		SavasYoneticisi.ses_cikar(self, 4.0, 0.4)
	else:
		print("⚠️ DodgeState bulunamadı")

# giris: 0 nişan (basılı tut), 1 kalçadan ateş, 2 hızlı atış (kılıç modunda Q dokunuşu)
func _nisan_dene(giris: int = 0) -> void:
	if dodge_aktif or parry_durumda or not is_on_floor():
		return
	# Sağ tık ve kalçadan ateş sadece ateşli silah modunda. Hızlı atış (Q) her iki modda çalışır.
	if giris != NISAN_HIZLI and silah_modu != 1:
		return
	var nisan_state = state_machine.get_node_or_null("AimState")
	if nisan_state:
		nisan_state.giris_modu = giris
		state_machine.transition_to(nisan_state)
	else:
		print("⚠️ AimState bulunamadı")

# `reload` tuşu: şarjörü doldurur (silahı çekmeden, arka planda da çalışır)
func _doldur_dene() -> void:
	var nisan_state = state_machine.get_node_or_null("AimState")
	if nisan_state:
		nisan_state.doldur_istegi()

func take_damage(miktar: int, kaynak: Node3D = null) -> void:
	if dokunulmaz:
		print("🌫️ KAÇINILDI")
		return
	
	if blok_aktif and onden_mi(kaynak):
		miktar = int(miktar * blok_hasar_carpani)
		ekran_salla(0.08)
		print("🛡️ BLOKLANDI, kalan hasar: ", miktar)
		if miktar <= 0:
			return
	
	print("💥 OYUNCU HASAR ALDI: ", miktar)
	current_health = max(current_health - miktar, 0)
	print("❤️ Kalan can: ", current_health)
	
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_health"):
		hud.update_health(current_health, max_health)
	
	SavasYoneticisi.ses_cikar(self, 12.0, 0.7)
	
	if current_health <= 0:
		ol()

func onden_mi(kaynak: Node3D) -> bool:
	if kaynak == null or blok_yonu == Vector3.ZERO:
		return true
	var yon: Vector3 = kaynak.global_position - global_position
	yon.y = 0.0
	if yon.length() < 0.01:
		return true
	return rad_to_deg(blok_yonu.angle_to(yon.normalized())) <= blok_acisi * 0.5

func iyiles(miktar: float) -> void:
	current_health = minf(current_health + miktar, max_health)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_health"):
		hud.update_health(current_health, max_health)

func kan_kazan(miktar: float) -> void:
	kan = clampf(kan + miktar, 0.0, max_kan)
	_kan_hud_guncelle()

func _kan_hud_guncelle() -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	for ad in ["update_blood", "update_kan", "kan_guncelle", "update_mana"]:
		if hud.has_method(ad):
			hud.call(ad, kan, max_kan)
			return
	print("⚠️ HUD'da kan barı fonksiyonu bulunamadı (kan: ", kan, "/", max_kan, ")")

func en_yakin_isirilabilir(menzil: float) -> Node3D:
	var en_iyi: Node3D = null
	var en_yakin: float = menzil
	for d in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(d) or not (d is Node3D):
			continue
		if d.get("isirilabilir") != true:
			continue
		var m: float = global_position.distance_to(d.global_position)
		if m < en_yakin:
			en_yakin = m
			en_iyi = d
	return en_iyi

func _isirma_dene() -> void:
	if dodge_aktif or parry_durumda or not is_on_floor():
		return
	var isirma_state = state_machine.get_node_or_null("BiteState")
	if isirma_state == null:
		print("⚠️ BiteState bulunamadı")
		return
	
	var gizli_hedef = en_yakin_gizli_hedef(2.0)
	if gizli_hedef:
		isirma_state.hedef_ayarla(gizli_hedef, true)
		state_machine.transition_to(isirma_state)
		return
	
	var hedef = en_yakin_isirilabilir(2.5)
	if hedef:
		isirma_state.hedef_ayarla(hedef, false)
		state_machine.transition_to(isirma_state)

func ol():
	get_tree().paused = true
	var death = get_tree().current_scene.get_node_or_null("DeathMenu")
	if death:
		death.visible = true
	print("💀 OYUNCU ÖLDÜ")
	
	velocity = Vector3.ZERO
	set_physics_process(false)
	set_process(false)
	set_process_input(false)
	
	var death_menu = get_tree().get_first_node_in_group("death_menu")
	if death_menu and death_menu.has_method("show_death_screen"):
		death_menu.show_death_screen()
	else:
		get_tree().reload_current_scene()

func _parry_dene() -> void:
	if silah_modu == 1:
		_nisan_dene(NISAN_NISAN)
		return
	if parry_durumda or dodge_aktif or parry_bekleme > 0.0 or not is_on_floor():
		return
	var parry_state = state_machine.get_node_or_null("ParryState")
	if parry_state:
		state_machine.transition_to(parry_state)
	else:
		print("⚠️ ParryState bulunamadı")

func parry_basarili(dusman, hasar: int = 0) -> bool:
	print("⚔️ PARRY!")
	parry_basarili_oldu = true
	ekran_salla(0.12)
	kan_kazan(10.0)
	SavasYoneticisi.ses_cikar(self, 10.0, 0.7)
	if parry_mukemmel and InputMap.has_action("finisher") and is_instance_valid(dusman):
		var sahne = state_machine.get_node_or_null("FinisherState")
		if sahne:
			sahne.hedef_ayarla(dusman, hasar)
			state_machine.transition_to(sahne)
			return true
	hit_pause()
	return false

func _sarj_dene() -> void:
	if dodge_aktif or parry_durumda or not is_on_floor():
		return
	var simdiki = state_machine.get("current_state")
	if simdiki and String(simdiki.name).to_lower().contains("attack"):
		return
	var sarj_state = state_machine.get_node_or_null("ChargeState")
	if sarj_state == null:
		print("⚠️ ChargeState bulunamadı")
		return
	sarj_baslatildi = true
	state_machine.transition_to(sarj_state)

# Tüm oyuncu vuruşları buradan geçer.
# bolge: "bas" / "govde" / "bacak" (düşmanın bolge_hasari fonksiyonu varsa tepki verir)
# ses_ver: false ise vuruş gürültü çıkarmaz (silahlar kendi sesini çıkarır)
func hedefe_vur(hedef: Node, taban_hasar: float, carpan: float = 1.0, agir: bool = false, sersemlet: bool = false, bolge: String = "", ses_ver: bool = true) -> bool:
	if hedef == null or not is_instance_valid(hedef) or not hedef.has_method("take_damage"):
		return false
	var hasar: float = taban_hasar * carpan
	
	var sans: float = kritik_sansi + (0.1 if agir else 0.0)
	if hedef.get("isirilabilir") == true or hedef.get("farkinda") == false:
		sans = 1.0
	var kritik: bool = randf() < sans
	if kritik:
		hasar *= kritik_carpani
	var hasar_int: int = int(round(hasar))
	
	if bolge != "" and hedef.has_method("bolge_hasari"):
		hedef.bolge_hasari(bolge, hasar_int)
	else:
		hedef.take_damage(hasar_int)

	if hedef.has_method("hasar_sayisi_goster"):
		hedef.hasar_sayisi_goster(hasar_int, kritik or bolge == "bas")
	
	if agir:
		var kb = hedef.get("knockback_velocity")
		if kb != null:
			hedef.set("knockback_velocity", kb * 1.6)
		if sersemlet and hedef.has_method("parry_edildi"):
			hedef.parry_edildi(true)
	
	if ses_ver:
		SavasYoneticisi.ses_cikar(self, 12.0, 0.7)
	if kritik:
		print("💥 KRİTİK VURUŞ: ", hasar_int)
		ekran_salla(0.3)
	if has_method("kan_kazan"):
		kan_kazan(14.0 if kritik else 8.0)
	return kritik

func en_yakin_gizli_hedef(menzil: float) -> Node3D:
	var en_iyi: Node3D = null
	var en_yakin: float = menzil
	for d in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(d) or not (d is Node3D):
			continue
		if d.get("farkinda") != false:
			continue
		var saglik = d.get("health")
		if saglik and saglik.get("can") != null and saglik.get("can") <= 0:
			continue
		var fark: Vector3 = global_position - d.global_position
		fark.y = 0.0
		var m: float = fark.length()
		if m >= en_yakin:
			continue
		var d_ileri: Vector3 = -d.global_transform.basis.z
		if m > 0.01 and d_ileri.dot(fark / m) > -0.3:
			continue
		en_yakin = m
		en_iyi = d
	return en_iyi

func _egilme_dene() -> void:
	if egiliyor:
		var ayakta = state_machine.get_node_or_null("IdleState")
		if ayakta:
			state_machine.transition_to(ayakta)
		return
	if dodge_aktif or parry_durumda or not is_on_floor():
		return
	var egil = state_machine.get_node_or_null("CrouchState")
	if egil:
		state_machine.transition_to(egil)
	else:
		print("⚠ CrouchState bulunamadı")
func kenara_tutun_ve_cik():
	# 1. Tırmanmayı ve yukarı çıkma hızını anında durdur
	is_climbing = false
	velocity = Vector3.ZERO
	# 2. Varsa tırmanma animasyonunu durdur ve "Yukarı Çekilme (Pull Up)" animasyonunu başlat
	# $AnimationPlayer.play("pull_up")
	# 3. Karakteri duvarın üstüne pürüzsüzce yerleştir (Tween Kullanımı)
	# Karakterin baktığı yönü alıyoruz
	var ileri_yon = -transform.basis.z.normalized() 
	# Duvarın üstündeki hedef pozisyonu hesapla (değerleri kendi karakterine göre ince ayarla)
	# Karakteri biraz yukarı (y) ve biraz ileri (ileri_yon) taşıyoruz.
	var hedef_pozisyon = global_position + Vector3(0, 1.2, 0) + (ileri_yon * 0.8)
	# Anında ışınlanmak yerine Tween ile yumuşak bir geçiş yapıyoruz
	var tween = create_tween()
	tween.tween_property(self, "global_position", hedef_pozisyon, 0.3)
	
	# Tween bittikten sonra karakterin tekrar yürüyebilmesi için state'i sıfırlayabilirsin.
func kan_harca(miktar: float) -> void:
	kan = maxf(kan - miktar, 0.0)
func kalkan_ver(miktar: float, sure: float) -> void:
	kalkan += miktar
	get_tree().create_timer(sure).timeout.connect(func(): kalkan = maxf(kalkan - miktar, 0.0))
