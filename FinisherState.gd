extends State

# ============================================================
# FİNİSHER SAHNESİ (tam zamanında parry sonrası)
# 1) Zaman yavaşlar, kamera yaklaşır, ekranda küçülen halka + tuş çıkar
# 2) Halka kapanmadan tuşa basılırsa -> ölümcül darbe, düşman ölür
# 3) Basılmazsa -> düşman ölmez, oyuncu vuruşun hasarını alır
# Süreler "gerçek saniye"dir (yavaşlatmadan etkilenmez).
# ============================================================

@export var qte_suresi: float = 0.8              # tuşa basma süresi (halka bu sürede kapanır)
@export var yavaslatma: float = 0.15             # QTE sırasında oyun hızı (1.0 = normal)
@export var kamera_zoom: float = 10.0            # QTE sırasında FOV'un ne kadar azalacağı (derece)
@export var finisher_suresi: float = 1.0         # finisher animasyonunun süresi
@export var vurus_noktasi: float = 0.45          # animasyon başladıktan kaç sn sonra düşman ölür
@export var kacirma_hasar_carpani: float = 1.0   # kaçırınca alınan hasar çarpanı (1.0 = tam hasar)
@export var varsayilan_hasar: int = 10           # düşmanın hasar bilgisi gelmezse kullanılır
@export var finisher_kan: float = 30.0           # başarılı finisher'ın kazandırdığı kan
@export var finisher_can: float = 20.0           # başarılı finisher'ın yenilediği can
@export var finisher_yedek_animasyon: String = "Sword_Attack"
@export var hasar_animasyonu: String = "Hit_Chest"
# Karakter modeli +Z yönüne mi bakıyor? (DodgeState'teki ayarla aynı olmalı)
@export var model_ileri_z: bool = true

var aktif: bool = false
var basildi: bool = false
var yavaslatma_bizde: bool = false
var dondurulmus: bool = false
var oyuncu = null
var dusman = null
var hasar: int = 0
var anim: AnimationPlayer
var kamera: Camera3D = null
var fov_orijinal: float = 75.0
var katman: CanvasLayer = null
var halka: Panel = null

# Oyuncu scripti geçişten ÖNCE çağırır
func hedef_ayarla(d, h: int) -> void:
	dusman = d
	hasar = h

func enter() -> void:
	# owner, düğüm başka bir sahnede eklenmişse oyuncu olmayabilir; StateMachine'in ebeveyni her zaman oyuncudur
	oyuncu = state_machine.get_parent()
	anim = oyuncu.anim
	
	if not is_instance_valid(dusman):
		state_machine.transition_to($"../IdleState")
		return
	
	aktif = true
	basildi = false
	
	# Sahne boyunca: yerinde dur, hasar alma, dodge/parry/saldırı kapalı
	oyuncu.velocity.x = 0.0
	oyuncu.velocity.z = 0.0
	oyuncu.dokunulmaz = true
	oyuncu.dodge_aktif = true
	oyuncu.parry_durumda = true
	oyuncu.set_meta("attack_pressed", false)
	if oyuncu.hitbox:
		oyuncu.hitbox.monitoring = false
	
	# Düşmanı dondur, ona dön
	if dusman.has_method("dondur"):
		dusman.dondur()
		dondurulmus = true
	_dusmana_don()
	
	_sekans()

func exit() -> void:
	aktif = false
	_prompt_gizle()
	if yavaslatma_bizde:
		Engine.time_scale = 1.0
		yavaslatma_bizde = false
	if dondurulmus and is_instance_valid(dusman) and dusman.has_method("coz"):
		dusman.coz()
	dondurulmus = false
	if kamera and is_instance_valid(kamera):
		kamera.fov = fov_orijinal
	if oyuncu:
		oyuncu.dokunulmaz = false
		oyuncu.dodge_aktif = false
		oyuncu.parry_durumda = false
		oyuncu.set_meta("attack_pressed", false)

func physics_update(delta: float) -> void:
	if oyuncu == null:
		return
	oyuncu.velocity.x = move_toward(oyuncu.velocity.x, 0.0, 30.0 * delta)
	oyuncu.velocity.z = move_toward(oyuncu.velocity.z, 0.0, 30.0 * delta)
	oyuncu.move_and_slide()

# Tuş girişi (olay tabanlı, yavaşlatmadan etkilenmez)
func _input(event: InputEvent) -> void:
	if aktif and not basildi and InputMap.has_action("finisher") and event.is_action_pressed("finisher"):
		basildi = true

# ------------------------------------------------------------
# SAHNE AKIŞI
# ------------------------------------------------------------
func _sekans() -> void:
	kamera = get_viewport().get_camera_3d()
	fov_orijinal = kamera.fov if kamera else 75.0
	Engine.time_scale = yavaslatma
	yavaslatma_bizde = true
	_prompt_goster()
	
	var baslangic: int = Time.get_ticks_msec()
	var sure_ms: float = qte_suresi * 1000.0
	while aktif and not basildi:
		var gecen: float = float(Time.get_ticks_msec() - baslangic)
		if gecen >= sure_ms:
			break
		var t: float = gecen / sure_ms
		_halka_guncelle(t)
		if kamera and is_instance_valid(kamera):
			kamera.fov = fov_orijinal - kamera_zoom * t
		await get_tree().process_frame
	
	_prompt_gizle()
	if yavaslatma_bizde:
		Engine.time_scale = 1.0
		yavaslatma_bizde = false
	if not aktif:
		return
	
	if basildi:
		await _finisher()
	else:
		await _kacirildi()

func _finisher() -> void:
	print("🗡️ FINISHER!")
	_anim_oynat(_finisher_anim_bul(), finisher_suresi)
	await _bekle(vurus_noktasi)
	if not aktif:
		return
	
	# Ölümcül darbe: ölüm animasyonunu ve slow-motion'ı düşmanın ol() fonksiyonu yönetir
	if is_instance_valid(dusman):
		dondurulmus = false
		# Büyük kan patlaması
	var kan_sahnesi = load("res://kan_efekti.tscn")
	if kan_sahnesi:
		for i in range(3):
			var kan = kan_sahnesi.instantiate()
			get_tree().current_scene.add_child(kan)
			kan.global_position = dusman.global_position + Vector3(
				randf_range(-0.3, 0.3), 1.2, randf_range(-0.3, 0.3)
			)
		dusman.take_damage(99999)
		# Kan emme: finisher can yeniler ve kan barını doldurur
		if oyuncu.has_method("kan_kazan"):
			oyuncu.kan_kazan(finisher_kan)
		if oyuncu.has_method("iyiles"):
			oyuncu.iyiles(finisher_can)
	oyuncu.ekran_salla(0.25)
	
	# Animasyonun bitmesini bekle (ölüm slow-motion'ında yavaşlayabilir)
	var bas: int = Time.get_ticks_msec()
	while aktif and anim and anim.is_playing() and Time.get_ticks_msec() - bas < 3000:
		await get_tree().process_frame
	if not aktif:
		return
	_bitir()

func _kacirildi() -> void:
	print("💢 FINISHER KAÇIRILDI")
	if is_instance_valid(dusman) and dusman.has_method("coz"):
		dondurulmus = false
		dusman.coz()
	
	# Düşman ölmez, oyuncu vuruşu yer
	oyuncu.dokunulmaz = false
	_anim_oynat(hasar_animasyonu)
	var vurus: int = varsayilan_hasar if hasar <= 0 else hasar
	oyuncu.take_damage(int(vurus * kacirma_hasar_carpani))
	oyuncu.ekran_salla(0.2)
	if oyuncu.current_health <= 0:
		return
	
	await _bekle(0.45)
	if not aktif:
		return
	_bitir()

func _bitir() -> void:
	await _fov_geri()
	if not aktif:
		return
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() > 0.1:
		state_machine.transition_to($"../RunState")
	else:
		state_machine.transition_to($"../IdleState")

# ------------------------------------------------------------
# YARDIMCILAR
# ------------------------------------------------------------
func _bekle(sn: float) -> void:
	await get_tree().create_timer(sn, true, false, true).timeout

func _fov_geri() -> void:
	if kamera == null or not is_instance_valid(kamera):
		return
	var bas: int = Time.get_ticks_msec()
	var baslangic_fov: float = kamera.fov
	while aktif and is_instance_valid(kamera):
		var t: float = clampf(float(Time.get_ticks_msec() - bas) / 250.0, 0.0, 1.0)
		kamera.fov = lerpf(baslangic_fov, fov_orijinal, t)
		if t >= 1.0:
			break
		await get_tree().process_frame

func _dusmana_don() -> void:
	if not is_instance_valid(dusman):
		return
	var f: Vector3 = dusman.global_position - oyuncu.global_position
	f.y = 0.0
	if f.length() < 0.01:
		return
	f = f.normalized()
	var aci: float = atan2(f.x, f.z)
	if not model_ileri_z:
		aci += PI
	oyuncu.mesh.global_rotation.y = aci

# "finisher" ya da "execution" geçen animasyonu bulur, yoksa yedeği kullanır
func _finisher_anim_bul() -> String:
	if anim == null:
		return ""
	for adi in anim.get_animation_list():
		var kucuk: String = String(adi).to_lower()
		if kucuk.contains("finisher") or kucuk.contains("execution"):
			return String(adi)
	if anim.has_animation(finisher_yedek_animasyon):
		return finisher_yedek_animasyon
	return ""

func _anim_oynat(adi: String, sure: float = 0.0) -> void:
	if adi == "" or anim == null or not anim.has_animation(adi):
		return
	var hiz: float = 1.0
	if sure > 0.0:
		hiz = anim.get_animation(adi).length / sure
	anim.play(adi, 0.05, hiz)

# ------------------------------------------------------------
# EKRAN ÜSTÜ TUŞ İSTEMİ (kodla oluşturulur, sahne düzenlemek gerekmez)
# Kırmızı halka küçülüp beyaz halkaya oturur, süre biter.
# ------------------------------------------------------------
func _prompt_goster() -> void:
	katman = CanvasLayer.new()
	katman.layer = 100
	katman.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(katman)
	
	var merkez: Control = Control.new()
	merkez.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	merkez.mouse_filter = Control.MOUSE_FILTER_IGNORE
	katman.add_child(merkez)
	
	var hedef_halka: Panel = _daire_olustur(Color(1, 1, 1, 0.9), 3, 150.0)
	merkez.add_child(hedef_halka)
	halka = _daire_olustur(Color(1.0, 0.15, 0.15, 1.0), 6, 150.0)
	merkez.add_child(halka)
	
	var etiket: Label = Label.new()
	etiket.text = _tus_adi()
	etiket.size = Vector2(150, 150)
	etiket.position = Vector2(-75, -75)
	etiket.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiket.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	etiket.add_theme_font_size_override("font_size", 56 if etiket.text.length() <= 3 else 22)
	etiket.add_theme_color_override("font_outline_color", Color.BLACK)
	etiket.add_theme_constant_override("outline_size", 8)
	etiket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	merkez.add_child(etiket)
	_halka_guncelle(0.0)

func _prompt_gizle() -> void:
	if katman and is_instance_valid(katman):
		katman.queue_free()
	katman = null
	halka = null

func _halka_guncelle(t: float) -> void:
	if halka and is_instance_valid(halka):
		halka.scale = Vector2.ONE * lerpf(2.6, 1.0, t)

func _daire_olustur(renk: Color, kalinlik: int, boyut: float) -> Panel:
	var p: Panel = Panel.new()
	p.size = Vector2(boyut, boyut)
	p.position = Vector2(-boyut * 0.5, -boyut * 0.5)
	p.pivot_offset = Vector2(boyut * 0.5, boyut * 0.5)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stil: StyleBoxFlat = StyleBoxFlat.new()
	stil.bg_color = Color(0, 0, 0, 0)
	stil.border_color = renk
	stil.set_border_width_all(kalinlik)
	stil.set_corner_radius_all(int(boyut))
	p.add_theme_stylebox_override("panel", stil)
	return p

func _tus_adi() -> String:
	var olaylar: Array[InputEvent] = InputMap.action_get_events("finisher")
	if olaylar.size() > 0:
		return olaylar[0].as_text().replace(" (Physical)", "")
	return "?"
