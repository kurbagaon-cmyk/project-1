extends State

# ============================================================
# OYUNCU DODGE (GÖLGE ADIMI)
# - Kilitliyken: düşmana dönük kalır, girişe göre 4 yönlü kayar
# - Serbest kamerada: giriş yönüne döner ve ileri kayar, giriş yoksa geri adım atar
# - Başında kısa dokunulmazlık (i-frame) penceresi vardır
# ============================================================

@export var dodge_suresi: float = 0.55          # toplam süre, animasyon buna sığdırılır
@export var dokunulmaz_baslangic: float = 0.05  # i-frame başlangıcı (sn)
@export var dokunulmaz_bitis: float = 0.4       # i-frame bitişi (sn)
@export var dodge_hizi: float = 8.0             # başlangıç hızı, sona doğru yavaşlar
@export var bekleme_suresi: float = 0.35        # dodge bittikten sonra tekrar basma bekleme süresi
# Karakter modeli +Z yönüne mi bakıyor? Dodge yanlış yöne dönüyorsa bunu değiştir.
@export var model_ileri_z: bool = true
# Dodge animasyonu bulunamazsa bunun yerine oynatılır (Mixamo animasyonları eklenene kadar test için)
@export var yedek_animasyon: String = "Roll"

var sayac: float = 0.0
var yon: Vector3 = Vector3.ZERO
var oyuncu = null
var anim: AnimationPlayer

func enter() -> void:
	oyuncu = owner
	anim = oyuncu.anim
	sayac = 0.0
	
	# Dodge saldırıyı iptal eder: bekleyen saldırı tuşunu ve hitbox'ı temizle
	oyuncu.set_meta("attack_pressed", false)
	if oyuncu.hitbox:
		oyuncu.hitbox.monitoring = false
	oyuncu.dodge_aktif = true
	oyuncu.dokunulmaz = false
	
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var anahtar: String = "backward"
	
	# Kameraya göre yatay yönler
	var cam: Basis = oyuncu.camera_pivot.global_transform.basis
	var cam_ileri: Vector3 = Vector3(-cam.z.x, 0.0, -cam.z.z).normalized()
	var cam_sag: Vector3 = Vector3(cam.x.x, 0.0, cam.x.z).normalized()
	var giris_yonu: Vector3 = cam_sag * input_dir.x + cam_ileri * (-input_dir.y)
	
	var kilitli = oyuncu.get_locked_enemy()
	if kilitli:
		# KİLİTLİ: düşmana dönük kal, girişe göre 4 yönlü kay
		var hedefe: Vector3 = kilitli.global_position - oyuncu.global_position
		hedefe.y = 0.0
		var bakis: Vector3 = hedefe.normalized() if hedefe.length() > 0.01 else cam_ileri
		var sag: Vector3 = bakis.cross(Vector3.UP)
		if input_dir.length() > 0.1:
			yon = giris_yonu.normalized()
			var ileri_d: float = yon.dot(bakis)
			var sag_d: float = yon.dot(sag)
			if abs(ileri_d) >= abs(sag_d):
				anahtar = "forward" if ileri_d > 0.0 else "backward"
			else:
				anahtar = "right" if sag_d > 0.0 else "left"
		else:
			yon = -bakis
			anahtar = "backward"
		_yuzu_don(bakis)
	else:
		# SERBEST: giriş varsa o yöne dön ve ileri kay, yoksa geri adım at
		if input_dir.length() > 0.1:
			yon = giris_yonu.normalized()
			anahtar = "forward"
			_yuzu_don(yon)
		else:
			yon = -_mesh_ileri()
			anahtar = "backward"
	
	_anim_oynat(anahtar)

func exit() -> void:
	if oyuncu:
		oyuncu.dokunulmaz = false
		oyuncu.dodge_aktif = false
		oyuncu.dodge_bekleme = bekleme_suresi

func physics_update(delta: float) -> void:
	sayac += delta
	
	# Dokunulmazlık penceresi
	oyuncu.dokunulmaz = sayac >= dokunulmaz_baslangic and sayac <= dokunulmaz_bitis
	
	# Hız: baştan hızlı, sona doğru yavaşlar
	var t: float = clampf(sayac / dodge_suresi, 0.0, 1.0)
	var hiz: float = dodge_hizi * (1.0 - t * t)
	oyuncu.velocity.x = yon.x * hiz
	oyuncu.velocity.z = yon.z * hiz
	oyuncu.move_and_slide()
	
	if sayac >= dodge_suresi:
		var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if input_dir.length() > 0.1:
			state_machine.transition_to($"../RunState")
		else:
			state_machine.transition_to($"../IdleState")

# ------------------------------------------------------------
# YARDIMCILAR
# ------------------------------------------------------------
func _mesh_ileri() -> Vector3:
	var b: Basis = oyuncu.mesh.global_transform.basis
	var f: Vector3 = b.z if model_ileri_z else -b.z
	f.y = 0.0
	return f.normalized()

func _yuzu_don(f: Vector3) -> void:
	if f.length() < 0.01:
		return
	var aci: float = atan2(f.x, f.z)
	if not model_ileri_z:
		aci += PI
	oyuncu.mesh.global_rotation.y = aci

# AnimationPlayer'daki isimlerden "dodge" + yön geçeni bulur
# (Standing Dodge Forward / Backward / Left / Right gibi)
func _anim_bul(anahtar: String) -> String:
	if anim == null:
		return ""
	for adi in anim.get_animation_list():
		var kucuk: String = String(adi).to_lower()
		if kucuk.contains("dodge") and kucuk.contains(anahtar):
			return String(adi)
	push_warning("DodgeState: '" + anahtar + "' yönü için dodge animasyonu bulunamadı, yedek animasyon deneniyor")
	if anim.has_animation(yedek_animasyon):
		return yedek_animasyon
	return ""

func _anim_oynat(anahtar: String) -> void:
	var adi: String = _anim_bul(anahtar)
	if adi == "":
		return
	# Animasyonu dodge süresine sığdır
	var uzunluk: float = anim.get_animation(adi).length
	anim.play(adi, 0.05, uzunluk / dodge_suresi)
