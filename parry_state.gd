extends State

# ============================================================
# OYUNCU PARRY / GUARD (basılı tutma)
# Sağ tık (parry) basılınca guard kaldırılır, basılı tutulduğu sürece duruşta kalır.
#   - İlk kısa pencerede gelen vuruş  -> parry (düşman sersemler)
#   - Pencerenin en başında gelen     -> MÜKEMMEL parry (finisher sahnesi)
#   - Pencereden sonra gelen vuruş    -> blok (hasar azalır, düşman sersemlemez)
# Sadece önden (guard yönünden) gelen vuruşlar parry/blok edilir.
# Guard'ı tutarken yavaş yürünebilir. Tuşu bırakınca guard iner.
# ============================================================

enum Evre { KALDIRMA, TUTMA, BIRAKMA }

@export var kalkma_suresi: float = 0.25          # guard kaldırma süresi (animasyonun ilk kısmı)
@export var pencere_baslangic: float = 0.0       # parry penceresi başlangıcı (sn)
@export var pencere_bitis: float = 0.25          # parry penceresi bitişi (sn)
# Tuşa bastıktan sonraki bu kadar sürede gelen vuruş "tam zamanında" sayılır ve finisher başlatır.
# pencere_bitis ile aynı yaparsan her başarılı parry finisher olur.
@export var mukemmel_pencere: float = 0.22
# Animasyonun yüzde kaçında donacağı (0.4 = %40'ında guard pozunda durur)
@export_range(0.05, 0.95) var tutma_orani: float = 0.4
@export var birakma_suresi: float = 0.35         # tuşu bırakınca guard'ın inme süresi
@export var basarili_birakma_suresi: float = 0.1 # başarılı parry sonrası inme süresi (hızlı karşı saldırı için)
@export var bekleme_suresi: float = 0.3          # bittikten sonra tekrar basma bekleme süresi
@export var yuruyus_hizi: float = 2.0            # guard'ı tutarken yürüme hızı
@export var donus_hizi: float = 12.0             # guard yönüne dönme hızı
# Karakter modeli +Z yönüne mi bakıyor? (DodgeState'teki ayarla aynı olmalı)
@export var model_ileri_z: bool = true
# Parry/blok animasyonu yoksa bunu oynatır (Mixamo animasyonu eklenene kadar test için)
@export var yedek_animasyon: String = "Sword_Idle"

var evre: Evre = Evre.KALDIRMA
var sayac: float = 0.0
var birakma_baslangic: float = 0.0
var oyuncu = null
var anim: AnimationPlayer

func enter() -> void:
	# owner, düğüm başka bir sahnede eklenmişse oyuncu olmayabilir; StateMachine'in ebeveyni her zaman oyuncudur
	oyuncu = state_machine.get_parent()
	anim = oyuncu.anim
	sayac = 0.0
	birakma_baslangic = 0.0
	evre = Evre.KALDIRMA
	
	# Parry saldırıyı iptal eder
	oyuncu.set_meta("attack_pressed", false)
	if oyuncu.hitbox:
		oyuncu.hitbox.monitoring = false
	
	oyuncu.parry_durumda = true
	oyuncu.parry_basarili_oldu = false
	oyuncu.blok_aktif = false
	oyuncu.parry_aktif = pencere_baslangic <= 0.0
	oyuncu.parry_mukemmel = true
	_anim_oynat()

func exit() -> void:
	if oyuncu:
		oyuncu.parry_aktif = false
		oyuncu.parry_mukemmel = false
		oyuncu.blok_aktif = false
		oyuncu.parry_durumda = false
		oyuncu.parry_bekleme = bekleme_suresi
		oyuncu.set_meta("attack_pressed", false)
	# Donmuş (pause) animasyon başka state'in animasyonunu engellemesin
	if anim and not anim.is_playing():
		anim.stop()

func physics_update(delta: float) -> void:
	sayac += delta
	
	# Parry pencereleri (tuşa bastıktan itibaren geçen süreye göre)
	oyuncu.parry_aktif = sayac >= pencere_baslangic and sayac <= pencere_bitis
	oyuncu.parry_mukemmel = sayac <= mukemmel_pencere
	
	var basili: bool = InputMap.has_action("parry") and Input.is_action_pressed("parry")
	
	# Kameraya göre yatay yönler
	var cam: Basis = oyuncu.camera_pivot.global_transform.basis
	var cam_ileri: Vector3 = Vector3(-cam.z.x, 0.0, -cam.z.z).normalized()
	var cam_sag: Vector3 = Vector3(cam.x.x, 0.0, cam.x.z).normalized()
	
	# Guard yönü: kilitliyse düşmana, değilse kameranın baktığı yöne
	var bakis: Vector3 = cam_ileri
	var kilitli = oyuncu.get_locked_enemy()
	if kilitli:
		var h: Vector3 = kilitli.global_position - oyuncu.global_position
		h.y = 0.0
		if h.length() > 0.01:
			bakis = h.normalized()
	oyuncu.blok_yonu = bakis
	_yuzu_don(bakis, delta)
	
	# Hareket: sadece guard'ı tutarken yavaş yürü
	var hedef_hiz: Vector3 = Vector3.ZERO
	if evre == Evre.TUTMA:
		var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if input_dir.length() > 0.1:
			var yon: Vector3 = (cam_sag * input_dir.x + cam_ileri * (-input_dir.y)).normalized()
			hedef_hiz = yon * yuruyus_hizi * minf(input_dir.length(), 1.0)
	oyuncu.velocity.x = move_toward(oyuncu.velocity.x, hedef_hiz.x, 30.0 * delta)
	oyuncu.velocity.z = move_toward(oyuncu.velocity.z, hedef_hiz.z, 30.0 * delta)
	oyuncu.move_and_slide()
	
	match evre:
		Evre.KALDIRMA:
			oyuncu.blok_aktif = sayac > pencere_bitis
			if sayac >= kalkma_suresi:
				if basili:
					# Guard pozunda dur: animasyonu dondur, basılı tuttukça orada kal
					evre = Evre.TUTMA
					if anim:
						anim.pause()
				else:
					_birakmaya_gec()
		Evre.TUTMA:
			oyuncu.blok_aktif = sayac > pencere_bitis
			if not basili:
				_birakmaya_gec()
		Evre.BIRAKMA:
			oyuncu.blok_aktif = false
			var bitis: float = basarili_birakma_suresi if oyuncu.parry_basarili_oldu else birakma_suresi
			if sayac - birakma_baslangic >= bitis:
				_cik()

func _birakmaya_gec() -> void:
	evre = Evre.BIRAKMA
	birakma_baslangic = sayac
	oyuncu.blok_aktif = false
	# Donmuş animasyonu kaldığı yerden devam ettir (guard iner)
	if anim and not anim.is_playing() and anim.current_animation != "":
		anim.play()

func _cik() -> void:
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() > 0.1:
		state_machine.transition_to($"../RunState")
	else:
		state_machine.transition_to($"../IdleState")

# Modeli guard yönüne yumuşakça döndürür
func _yuzu_don(f: Vector3, delta: float) -> void:
	if f.length() < 0.01:
		return
	var hedef_aci: float = atan2(f.x, f.z)
	if not model_ileri_z:
		hedef_aci += PI
	var mesh: Node3D = oyuncu.mesh
	mesh.global_rotation.y = lerp_angle(mesh.global_rotation.y, hedef_aci, clampf(donus_hizi * delta, 0.0, 1.0))

# ------------------------------------------------------------
# "parry" ya da "block" geçen animasyonu bulur
# ------------------------------------------------------------
func _anim_bul() -> String:
	if anim == null:
		return ""
	for adi in anim.get_animation_list():
		var kucuk: String = String(adi).to_lower()
		if kucuk.contains("parry") or kucuk.contains("block"):
			return String(adi)
	push_warning("ParryState: parry/block animasyonu bulunamadı, yedek animasyon deneniyor")
	if anim.has_animation(yedek_animasyon):
		return yedek_animasyon
	return ""

func _anim_oynat() -> void:
	var adi: String = _anim_bul()
	if adi == "":
		return
	# Animasyonun ilk kısmı (tutma_orani) kalkma_suresi içinde oynar, sonra donar
	var uzunluk: float = anim.get_animation(adi).length
	var hiz: float = (uzunluk * tutma_orani) / kalkma_suresi
	anim.play(adi, 0.05, hiz)
