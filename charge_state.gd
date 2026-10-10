extends State

# ============================================================
# ŞARJLI (AĞIR) SALDIRI
# Sol tık basılı tutulunca başlar. Tuttukça güç birikir, bırakınca ağır vuruş gelir.
# Animasyon: Sword_Attack'in ilk kısmı oynayıp hazırlık pozunda donar, bırakınca vuruş devam eder.
# Tam şarjda vuruş düşmanı sersemletir (ısırılabilir hale getirir).
# ============================================================

enum Evre { SARJ, VURUS, TOPARLANMA }

@export var taban_hasar: float = 15.0            # normal saldırıyla aynı taban hasar
@export var maks_sarj_suresi: float = 1.0        # tam şarj için gereken süre (sn)
@export var min_hasar_carpani: float = 1.5       # hemen bırakılan şarjlı vuruşun çarpanı
@export var maks_hasar_carpani: float = 3.0      # tam şarjın çarpanı
@export var tam_sarj_esigi: float = 0.95         # şarj seviyesi bunu geçerse "tam şarj" sayılır
@export var sarj_yuruyus_hizi: float = 1.5       # şarj ederken yürüme hızı
@export var vurus_suresi: float = 0.25           # hasar penceresi (sn)
@export var toparlanma_suresi: float = 0.5       # vuruştan sonra açıkta kalma süresi
@export var atilma_hizi: float = 5.0             # vuruşta öne atılma hızı (şarj seviyesiyle ölçeklenir)
@export var sarj_animasyonu: String = "Sword_Attack"
@export_range(0.05, 0.95) var sarj_orani: float = 0.3   # animasyonun yüzde kaçında hazırlık pozunda donar
@export var hazirlik_hizi: float = 2.0           # animasyonun hazırlık kısmının oynama hızı
# Karakter modeli +Z yönüne mi bakıyor? (DodgeState'teki ayarla aynı olmalı)
@export var model_ileri_z: bool = true

var evre: Evre = Evre.SARJ
var sayac: float = 0.0
var sarj_suresi: float = 0.0
var seviye: float = 0.0
var hazirlik_suresi: float = 0.15
var donduruldu: bool = false
var tam_sarj_bildirildi: bool = false
var vurulanlar: Array = []
var oyuncu = null
var anim: AnimationPlayer

func enter() -> void:
	oyuncu = state_machine.get_parent()
	anim = oyuncu.anim
	evre = Evre.SARJ
	sayac = 0.0
	sarj_suresi = 0.0
	seviye = 0.0
	donduruldu = false
	tam_sarj_bildirildi = false
	vurulanlar.clear()
	
	oyuncu.set_meta("attack_pressed", false)
	if oyuncu.hitbox:
		oyuncu.hitbox.monitoring = false
	
	# Animasyonun hazırlık kısmını hızlıca oynat, sonra pozda dondur
	if anim and anim.has_animation(sarj_animasyonu):
		var uzunluk: float = anim.get_animation(sarj_animasyonu).length
		hazirlik_suresi = (uzunluk * sarj_orani) / hazirlik_hizi
		anim.play(sarj_animasyonu, 0.1, hazirlik_hizi)
	else:
		hazirlik_suresi = 0.15

func exit() -> void:
	if oyuncu:
		if oyuncu.hitbox:
			oyuncu.hitbox.monitoring = false
		oyuncu.set_meta("attack_pressed", false)
	# Donmuş (pause) animasyon başka state'in animasyonunu engellemesin
	if anim and not anim.is_playing():
		anim.stop()

func physics_update(delta: float) -> void:
	sayac += delta
	match evre:
		Evre.SARJ:
			_sarj(delta)
		Evre.VURUS:
			_vurus(delta)
		Evre.TOPARLANMA:
			_toparlanma(delta)

# ------------------------------------------------------------
# 1) ŞARJ: tuş basılı tutuldukça güç birikir
# ------------------------------------------------------------
func _sarj(delta: float) -> void:
	sarj_suresi += delta
	seviye = clampf(sarj_suresi / maks_sarj_suresi, 0.0, 1.0)
	
	# Hazırlık pozuna gelince animasyonu dondur
	if not donduruldu and sayac >= hazirlik_suresi:
		donduruldu = true
		if anim and anim.has_animation(sarj_animasyonu):
			anim.pause()
	
	# Tam şarj bildirimi (küçük titreşim)
	if seviye >= tam_sarj_esigi and not tam_sarj_bildirildi:
		tam_sarj_bildirildi = true
		print("⚡ TAM ŞARJ")
		oyuncu.ekran_salla(0.05)
	
	# Şarj ederken kilitli düşmana dön, yavaş yürü
	_hareket_et(delta, sarj_yuruyus_hizi)
	
	# Tuş bırakıldı: ağır vuruş
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		evre = Evre.VURUS
		sayac = 0.0
		vurulanlar.clear()
		print("🗡️ AĞIR VURUŞ | seviye=", snappedf(seviye, 0.01))
		if oyuncu.hitbox:
			oyuncu.hitbox.monitoring = true
		# Donmuş animasyonu kaldığı yerden devam ettir (vuruş)
		if anim and not anim.is_playing() and anim.current_animation != "":
			anim.play()

# ------------------------------------------------------------
# 2) VURUŞ: öne atıl, hasar penceresi açık
# ------------------------------------------------------------
func _vurus(delta: float) -> void:
	var ileri: Vector3 = _mesh_ileri()
	var hiz: float = atilma_hizi * seviye
	oyuncu.velocity.x = ileri.x * hiz
	oyuncu.velocity.z = ileri.z * hiz
	oyuncu.move_and_slide()
	
	_hasar_ver()
	
	if sayac >= vurus_suresi:
		if oyuncu.hitbox:
			oyuncu.hitbox.monitoring = false
		evre = Evre.TOPARLANMA
		sayac = 0.0

# ------------------------------------------------------------
# 3) TOPARLANMA: açıkta kalır
# ------------------------------------------------------------
func _toparlanma(delta: float) -> void:
	oyuncu.velocity.x = move_toward(oyuncu.velocity.x, 0.0, 30.0 * delta)
	oyuncu.velocity.z = move_toward(oyuncu.velocity.z, 0.0, 30.0 * delta)
	oyuncu.move_and_slide()
	if sayac >= toparlanma_suresi:
		var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if input_dir.length() > 0.1:
			state_machine.transition_to($"../RunState")
		else:
			state_machine.transition_to($"../IdleState")

# ------------------------------------------------------------
# HASAR (oyuncunun normal saldırı state'iyle aynı mantık)
# ------------------------------------------------------------
func _hasar_ver() -> void:
	if not oyuncu.hitbox:
		return
	var carpan: float = lerpf(min_hasar_carpani, maks_hasar_carpani, seviye)
	var tam_sarj: bool = seviye >= tam_sarj_esigi
	
	for body in oyuncu.hitbox.get_overlapping_bodies():
		if body == oyuncu or body in vurulanlar:
			continue
		if body.has_method("take_damage"):
			_vur(body, carpan, tam_sarj)
	
	for area in oyuncu.hitbox.get_overlapping_areas():
		var sahip = area.get_parent()
		if sahip == oyuncu or sahip in vurulanlar:
			continue
		if sahip and sahip.has_method("take_damage"):
			_vur(sahip, carpan, tam_sarj)

func _vur(hedef, carpan: float, tam_sarj: bool) -> void:
	vurulanlar.append(hedef)
	if oyuncu.has_method("hedefe_vur"):
		oyuncu.hedefe_vur(hedef, taban_hasar, carpan, true, tam_sarj)
	else:
		hedef.take_damage(int(taban_hasar * carpan))
	oyuncu.hit_pause()
	oyuncu.ekran_salla(0.25)

# ------------------------------------------------------------
# YARDIMCILAR
# ------------------------------------------------------------
func _mesh_ileri() -> Vector3:
	var b: Basis = oyuncu.mesh.global_transform.basis
	var f: Vector3 = b.z if model_ileri_z else -b.z
	f.y = 0.0
	return f.normalized()

func _hareket_et(delta: float, max_hiz: float) -> void:
	var cam: Basis = oyuncu.camera_pivot.global_transform.basis
	var cam_ileri: Vector3 = Vector3(-cam.z.x, 0.0, -cam.z.z).normalized()
	var cam_sag: Vector3 = Vector3(cam.x.x, 0.0, cam.x.z).normalized()
	
	# Kilitliyken düşmana dön
	var kilitli = oyuncu.get_locked_enemy()
	if kilitli:
		var h: Vector3 = kilitli.global_position - oyuncu.global_position
		h.y = 0.0
		if h.length() > 0.01:
			var f: Vector3 = h.normalized()
			var aci: float = atan2(f.x, f.z)
			if not model_ileri_z:
				aci += PI
			var mesh: Node3D = oyuncu.mesh
			mesh.global_rotation.y = lerp_angle(mesh.global_rotation.y, aci, clampf(12.0 * delta, 0.0, 1.0))
	
	var hedef_hiz: Vector3 = Vector3.ZERO
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() > 0.1:
		var yon: Vector3 = (cam_sag * input_dir.x + cam_ileri * (-input_dir.y)).normalized()
		hedef_hiz = yon * max_hiz * minf(input_dir.length(), 1.0)
	oyuncu.velocity.x = move_toward(oyuncu.velocity.x, hedef_hiz.x, 30.0 * delta)
	oyuncu.velocity.z = move_toward(oyuncu.velocity.z, hedef_hiz.z, 30.0 * delta)
	oyuncu.move_and_slide()
