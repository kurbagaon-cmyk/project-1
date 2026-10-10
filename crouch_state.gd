extends State

# ============================================================
# EĞİLME (GİZLİLİK DURUŞU)
# - Yavaş yürür, kamera biraz alçalır
# - Düşmanlar eğilen oyuncuyu daha geç görür ve neredeyse hiç duymaz
# - Saldırı tuşuna basılırsa ayağa kalkar ve saldırıyı normal state devralır
# Eğilme açma/kapama tuşu PlayerNew scriptinde (_egilme_dene) yönetilir.
# ============================================================

@export var egilme_hizi: float = 2.5
@export var donus_hizi: float = 10.0
@export var kamera_inisi: float = 0.2            # eğilirken kameranın ne kadar alçalacağı (fazla alçalırsa kamera karakterin içine girebilir)
@export var kamera_hizi: float = 8.0
# true yaparsan çarpışma kapsülü de küçülür (alçak geçitler için). Kapalı kalması daha güvenli.
@export var kapsul_kucult: bool = false
@export_range(0.4, 0.9) var kapsul_orani: float = 0.65
@export var bekleme_animasyonu: String = "Crouch_Idle"
@export var yurume_animasyonu: String = "Crouch_Fwd"
# Karakter modeli +Z yönüne mi bakıyor? (DodgeState'teki ayarla aynı olmalı)
@export var model_ileri_z: bool = true

var oyuncu = null
var anim: AnimationPlayer
var normal_kamera_y: float = 0.0
var kapsul: CollisionShape3D = null
var kapsul_normal_h: float = 0.0
var kapsul_normal_y: float = 0.0

func enter() -> void:
	oyuncu = state_machine.get_parent()
	anim = oyuncu.anim
	oyuncu.egiliyor = true
	normal_kamera_y = oyuncu.orijinal_kamera_pozisyonu.y
	# Kamera kolu karakterin kendi çarpışma kapsülüne çarpıp karakterin içine girmesin
	var kamera_kolu = oyuncu.find_child("SpringArm3D", true, false)
	if kamera_kolu:
		kamera_kolu.add_excluded_object(oyuncu.get_rid())
	if kapsul_kucult:
		_kapsul_kucult()

func exit() -> void:
	if oyuncu:
		oyuncu.egiliyor = false
		var p: Vector3 = oyuncu.orijinal_kamera_pozisyonu
		p.y = normal_kamera_y
		oyuncu.orijinal_kamera_pozisyonu = p
	_kapsul_geri()

func physics_update(delta: float) -> void:
	# Saldırı tuşuna basıldıysa ayağa kalk, saldırıyı normal state devralır
	if oyuncu.has_meta("attack_pressed") and oyuncu.get_meta("attack_pressed"):
		state_machine.transition_to($"../IdleState")
		return
	
	# Kamera yumuşakça alçalır
	var p: Vector3 = oyuncu.orijinal_kamera_pozisyonu
	p.y = lerpf(p.y, normal_kamera_y - kamera_inisi, clampf(kamera_hizi * delta, 0.0, 1.0))
	oyuncu.orijinal_kamera_pozisyonu = p
	
	# Kameraya göre yön
	var cam: Basis = oyuncu.camera_pivot.global_transform.basis
	var cam_ileri: Vector3 = Vector3(-cam.z.x, 0.0, -cam.z.z).normalized()
	var cam_sag: Vector3 = Vector3(cam.x.x, 0.0, cam.x.z).normalized()
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	var yon: Vector3 = Vector3.ZERO
	var hedef_hiz: Vector3 = Vector3.ZERO
	if input_dir.length() > 0.1:
		yon = (cam_sag * input_dir.x + cam_ileri * (-input_dir.y)).normalized()
		hedef_hiz = yon * egilme_hizi * minf(input_dir.length(), 1.0)
	
	# Bakış yönü: kilitliyse düşmana, değilse gittiği yöne
	var bakis: Vector3 = Vector3.ZERO
	var kilitli = oyuncu.get_locked_enemy()
	if kilitli:
		var h: Vector3 = kilitli.global_position - oyuncu.global_position
		h.y = 0.0
		if h.length() > 0.01:
			bakis = h.normalized()
	elif yon != Vector3.ZERO:
		bakis = yon
	if bakis != Vector3.ZERO:
		_yuzu_don(bakis, delta)
	
	oyuncu.velocity.x = move_toward(oyuncu.velocity.x, hedef_hiz.x, 25.0 * delta)
	oyuncu.velocity.z = move_toward(oyuncu.velocity.z, hedef_hiz.z, 25.0 * delta)
	oyuncu.move_and_slide()
	
	# Animasyon
	if hedef_hiz.length() > 0.1:
		_anim_oynat(yurume_animasyonu)
	else:
		_anim_oynat(bekleme_animasyonu)

func _yuzu_don(f: Vector3, delta: float) -> void:
	var hedef_aci: float = atan2(f.x, f.z)
	if not model_ileri_z:
		hedef_aci += PI
	var mesh: Node3D = oyuncu.mesh
	mesh.global_rotation.y = lerp_angle(mesh.global_rotation.y, hedef_aci, clampf(donus_hizi * delta, 0.0, 1.0))

func _anim_oynat(isim: String) -> void:
	if anim == null or not anim.has_animation(isim):
		return
	if anim.current_animation != isim or not anim.is_playing():
		anim.play(isim, 0.15)

# ------------------------------------------------------------
# İSTEĞE BAĞLI: ÇARPIŞMA KAPSÜLÜNÜ KÜÇÜLTME
# ------------------------------------------------------------
func _kapsul_kucult() -> void:
	# Sadece oyuncunun doğrudan altındaki CollisionShape3D (Hitbox'ınki değil)
	kapsul = oyuncu.find_child("CollisionShape3D", false, false)
	if kapsul == null or not (kapsul.shape is CapsuleShape3D):
		kapsul = null
		return
	var sekil: CapsuleShape3D = kapsul.shape
	kapsul_normal_h = sekil.height
	kapsul_normal_y = kapsul.position.y
	var yeni_h: float = maxf(kapsul_normal_h * kapsul_orani, sekil.radius * 2.0 + 0.01)
	sekil.height = yeni_h
	# Ayaklar yerde kalsın diye merkezi aşağı kaydır
	kapsul.position.y = kapsul_normal_y - (kapsul_normal_h - yeni_h) * 0.5

func _kapsul_geri() -> void:
	if kapsul and is_instance_valid(kapsul) and kapsul.shape is CapsuleShape3D:
		(kapsul.shape as CapsuleShape3D).height = kapsul_normal_h
		kapsul.position.y = kapsul_normal_y
	kapsul = null
