extends State

# ============================================================
# BÜYÜ SİSTEMİ (CastState)
#
# NASIL ÇALIŞIR:
#   1) Büyüler aşağıdaki BÜYÜ TABLOSUNDA tanımlıdır (ad, kan maliyeti, bekleme süresi...).
#   2) Radyal menünün "Büyü" dilimi sıradaki büyüyü seçer (buyu_dongu).
#   3) `cast` tuşuna basınca PlayerNew `dene()` fonksiyonunu çağırır: kan yeterli mi, bekleme bitti mi,
#      gerekiyorsa hedef var mı kontrol eder. Uygunsa bu state'e geçilir.
#   4) State'te önce kısa bir HAZIRLIK (animasyon), sonra büyünün ETKİSİ uygulanır, sonra kısa bir
#      TOPARLANMA vardır. Sonra Run/Idle'a dönülür.
#   5) Büyünün etkisi `_buyu_uygula()` içinde büyünün "id"sine göre ilgili fonksiyona yönlendirilir.
#
# YENİ BÜYÜ EKLEMEK İÇİN:
#   a) buyu_tablosu'na yeni bir satır ekle (id'si benzersiz olsun)
#   b) _buyu_uygula() içindeki match'e o id için bir satır ekle
#   c) O büyünün etkisini yapan bir fonksiyon yaz (örn. _yeni_buyu(b))
#
# Büyü efektleri (parlama, halka, şimşek) kodla oluşturulur, sahneye bir şey eklemek gerekmez.
# ============================================================

enum Evre { HAZIRLIK, TOPARLANMA }

# --- BÜYÜ TABLOSU (değerleri buradan değiştir) ---
# maliyet: kan | bekleme: tekrar kullanmak için sn | hazirlik/toparlanma: animasyon süreleri
# tur: "kan", "karanlik" ya da "elektrik" | karanlik: kullanınca artan karanlık puanı
var buyu_tablosu: Array = [
	{
		"id": "golge_adimi", "ad": "Gölge Adımı", "tur": "kan", "renk": Color(0.6, 0.35, 0.95),
		"maliyet": 15.0, "bekleme": 2.0, "hazirlik": 0.05, "toparlanma": 0.3, "karanlik": 0.0,
		"mesafe": 7.0,   # en fazla ne kadar ileri kayar (m)
	},
	{
		"id": "kan_kalkani", "ad": "Kan Kalkanı", "tur": "kan", "renk": Color(0.85, 0.1, 0.2),
		"maliyet": 25.0, "bekleme": 8.0, "hazirlik": 0.2, "toparlanma": 0.2, "karanlik": 0.0,
		"kalkan": 40.0,  # emebileceği hasar
		"sure": 10.0,    # kalkanın süresi (sn)
	},
	{
		"id": "karanlik_patlamasi", "ad": "Karanlık Patlama", "tur": "karanlik", "renk": Color(0.45, 0.1, 0.7),
		"maliyet": 20.0, "bekleme": 5.0, "hazirlik": 0.3, "toparlanma": 0.3, "karanlik": 6.0,
		"hasar": 18.0, "yaricap": 6.5, "aci": 130.0,   # önündeki 130 derecelik alanda 6.5 m içindekilere
	},
	{
		"id": "elektrik_zinciri", "ad": "Elektrik Zinciri", "tur": "elektrik", "renk": Color(0.4, 0.8, 1.0),
		"maliyet": 30.0, "bekleme": 4.0, "hazirlik": 0.25, "toparlanma": 0.25, "karanlik": 0.0,
		"hasar": 22.0, "menzil": 18.0, "atlama": 3, "atlama_mesafe": 6.5,
		"hedef_gerekli": true,   # hedef yoksa büyü kullanılamaz (kan harcanmaz)
	},
]

@export var debug: bool = true
# Karanlık büyülerin gücü karanlık seviyesiyle artar (seviye başına +%10)
@export var karanlik_guc_carpani: float = 0.1
@export var model_ileri_z: bool = true
@export var anim_hazirlik: String = "Spell_Simple_Enter"
@export var anim_atis: String = "Spell_Simple_Shoot"
@export var anim_cikis: String = "Spell_Simple_Exit"
@export var azami_kan: float = 100.0
var kan: float = 100.0

var kalkan: float = 0.0
var dokunulmaz: bool = false
var parry_durumda: bool = false

# Düşme ve yön hesabı için
var havada_idi: bool = false
var dusus_baslangic_y: float = 0.0

@onready var anim: AnimationPlayer = $AnimationPlayer # Kendi AnimationPlayer yoluna göre düzenle
@onready var camera_pivot: Node3D = $CameraPivot     # Kamera pivotunun adı
@onready var hitbox: Area3D = $Hitbox                # Saldırı alanı (varsa)
var aktif_buyu: int = 0
var bekleme_bitis: Array = []     # her büyünün bekleme süresinin biteceği zaman (ms)
var evre: Evre = Evre.HAZIRLIK
var sayac: float = 0.0
var etki_yapildi: bool = false
var bakis_yonu: Vector3 = Vector3.FORWARD
var oyuncu = null
var hud_katman: CanvasLayer = null
var hud_etiket: Label = null
var bildirim_katmani: CanvasLayer = null

func _ready() -> void:
	for i in buyu_tablosu.size():
		bekleme_bitis.append(0)
	# Ekran etiketi sahne tamamen yüklendikten sonra oluşturulur
	call_deferred("_hud_olustur")

# Her karede ekrandaki büyü etiketini günceller (state aktif olmasa da çalışır)
func _process(_delta: float) -> void:
	_hud_guncelle()

# ============================================================
# 1) DIŞARIDAN ÇAĞRILAN FONKSİYONLAR
# ============================================================

# `cast` tuşuna basılınca PlayerNew çağırır. true dönerse state'e geçilir.
func dene() -> bool:
	oyuncu = state_machine.get_parent()
	var b: Dictionary = buyu_tablosu[aktif_buyu]
	# Bekleme süresi bitti mi? (sessiz çık: kalan süre ekranda zaten görünüyor)
	if Time.get_ticks_msec() < bekleme_bitis[aktif_buyu]:
		return false
	# Yeterli kan var mı?
	if oyuncu.kan < b["maliyet"]:
		bildirim("KAN YETERSİZ", Color(1.0, 0.3, 0.3))
		return false
	# Hedef gereken büyüde hedef var mı?
	if b.get("hedef_gerekli", false) and _ilk_hedef(b["menzil"]) == null:
		bildirim("HEDEF YOK", Color(0.8, 0.8, 0.8))
		return false
	return true

# Radyal menünün Büyü dilimi: sıradaki büyüye geç
func buyu_dongu() -> void:
	aktif_buyu = (aktif_buyu + 1) % buyu_tablosu.size()
	var b: Dictionary = buyu_tablosu[aktif_buyu]
	bildirim("BÜYÜ: " + b["ad"] + "  (" + str(int(b["maliyet"])) + " kan)", b["renk"])
	if debug:
		print("🔮 Seçilen büyü: ", b["ad"])

# ============================================================
# 2) STATE: GİRİŞ, HER KARE, ÇIKIŞ
# ============================================================
func enter() -> void:
	oyuncu = state_machine.get_parent()
	anim = oyuncu.anim
	var b: Dictionary = buyu_tablosu[aktif_buyu]
	
	# Bedelini öde ve bekleme süresini başlat
	oyuncu.kan_harca(b["maliyet"])
	bekleme_bitis[aktif_buyu] = Time.get_ticks_msec() + int(b["bekleme"] * 1000.0)
	
	evre = Evre.HAZIRLIK
	sayac = 0.0
	etki_yapildi = false
	
	# parry_durumda bayrağı saldırı, parry, nişan, şarj, ısırma gibi diğer eylemleri kapatır.
	# (dodge açık kalır: büyü sırasında kaçınarak iptal edebilirsin)
	oyuncu.parry_durumda = true
	oyuncu.set_meta("attack_pressed", false)
	if oyuncu.hitbox:
		oyuncu.hitbox.monitoring = false
	
	bakis_yonu = _bakis_hesapla()
	ParkurYardimci.mesh_don(oyuncu, bakis_yonu, model_ileri_z)
	_anim_oynat(anim_hazirlik, b["hazirlik"])
	if debug:
		print("🔮 Büyü başladı: ", b["ad"], " | kalan kan: ", oyuncu.kan)

func exit() -> void:
	if oyuncu:
		oyuncu.parry_durumda = false
		oyuncu.dokunulmaz = false

func physics_update(delta: float) -> void:
	sayac += delta
	var b: Dictionary = buyu_tablosu[aktif_buyu]
	
	# Büyü sırasında karakter yavaşça durur
	oyuncu.velocity.x = move_toward(oyuncu.velocity.x, 0.0, 30.0 * delta)
	oyuncu.velocity.z = move_toward(oyuncu.velocity.z, 0.0, 30.0 * delta)
	oyuncu.move_and_slide()
	
	match evre:
		Evre.HAZIRLIK:
			# Hazırlanırken hedefe / baktığın yöne dönük kal
			bakis_yonu = _bakis_hesapla()
			ParkurYardimci.mesh_don(oyuncu, bakis_yonu, model_ileri_z)
			if sayac >= b["hazirlik"]:
				_buyu_uygula(b)
				etki_yapildi = true
				evre = Evre.TOPARLANMA
				sayac = 0.0
				_anim_oynat(anim_atis, b["toparlanma"])
		Evre.TOPARLANMA:
			if sayac >= b["toparlanma"]:
				_cik()

# Büyünün etkisini id'sine göre ilgili fonksiyona yönlendirir
func _buyu_uygula(b: Dictionary) -> void:
	var basarili: bool = true
	match b["id"]:
		"golge_adimi":
			basarili = _golge_adimi(b)
		"kan_kalkani":
			_kan_kalkani(b)
		"karanlik_patlamasi":
			_karanlik_patlamasi(b)
		"elektrik_zinciri":
			basarili = _elektrik_zinciri(b)
	
	if not basarili:
		# Büyü gerçekleşemedi (örn. yol kapalı): kanı iade et, beklemeyi sıfırla
		oyuncu.kan_kazan(b["maliyet"])
		bekleme_bitis[aktif_buyu] = 0
		return
	
	# Karanlık büyüler karanlığı artırır (oyunun sonunu belirleyecek değer)
	if b["karanlik"] > 0.0:
		OyunDurumu.karanlik_kazan(b["karanlik"], oyuncu)

# ============================================================
# 3) BÜYÜLER
# ============================================================

# --- GÖLGE ADIMI: baktığın/gittiğin yöne anında kayar, kısa süre dokunulmazsın ---
# Önce tam mesafeyi dener, duvara çarpıyorsa ya da altında zemin yoksa mesafeyi kısaltır.
func _golge_adimi(b: Dictionary) -> bool:
	var yon: Vector3 = ParkurYardimci.girdi_yonu(oyuncu)
	if yon == Vector3.ZERO:
		yon = bakis_yonu
	var ayak: Vector3 = oyuncu.global_position
	var gogus: Vector3 = ayak + Vector3.UP * 1.0
	
	var hedef_ayak: Vector3 = ayak
	var bulundu: bool = false
	for oran in [1.0, 0.75, 0.5, 0.3]:
		var uzaklik: float = b["mesafe"] * oran
		var hedef: Vector3 = gogus + yon * uzaklik
		# Aradaki duvara çarparsak duvarın 0.6 m önünde dur
		var duvar: Dictionary = ParkurYardimci.isin(oyuncu, gogus, hedef)
		if not duvar.is_empty():
			var iceri: float = gogus.distance_to(duvar["position"]) - 0.6
			if iceri < 0.8:
				continue
			hedef = gogus + yon * iceri
		# Hedefin altında zemin var mı? (boşluğa kaymayalım)
		var zemin: Dictionary = ParkurYardimci.isin(oyuncu, hedef + Vector3.UP * 0.5, hedef + Vector3.DOWN * 4.0)
		if zemin.is_empty():
			continue
		hedef_ayak = zemin["position"]
		bulundu = true
		break
	
	if not bulundu:
		bildirim("YOL KAPALI", Color(0.8, 0.8, 0.8))
		return false
	
	_parcacik(ayak + Vector3.UP * 1.0, b["renk"])
	oyuncu.global_position = hedef_ayak + Vector3.UP * 0.05
	oyuncu.velocity = yon * 4.0
	oyuncu.dokunulmaz = true
	# Düşme takibini sıfırla: yüksek/alçak yere kayınca "düştü" sanılmasın
	oyuncu.havada_idi = false
	oyuncu.dusus_baslangic_y = oyuncu.global_position.y
	_parcacik(hedef_ayak + Vector3.UP * 1.0, b["renk"])
	SavasYoneticisi.ses_cikar(oyuncu, 3.0, 0.3)
	return true

# --- KAN KALKANI: bir süre gelen hasarın bir kısmını emer ---
func _kan_kalkani(b: Dictionary) -> void:
	oyuncu.kalkan_ver(b["kalkan"], b["sure"])
	_halka_efekti(oyuncu.global_position, b["renk"], 1.8)
	SavasYoneticisi.ses_cikar(oyuncu, 6.0, 0.3)

# --- KARANLIK PATLAMA: önündeki alanda düşmanları sersemletip geri iter ---
# Sersemleyen düşman kırmızı parlar ve ısırılabilir (kan emme için fırsat).
func _karanlik_patlamasi(b: Dictionary) -> void:
	var merkez: Vector3 = oyuncu.global_position
	var carpan: float = 1.0 + karanlik_guc_carpani * OyunDurumu.karanlik_seviyesi()
	var vurulan: int = 0
	for d in get_tree().get_nodes_in_group("enemy"):
		if not _canli(d):
			continue
		var fark: Vector3 = d.global_position - merkez
		fark.y = 0.0
		var mesafe: float = fark.length()
		if mesafe > b["yaricap"]:
			continue
		# Önümüzdeki koni içinde mi? (çok yakındakiler her açıdan etkilenir)
		if mesafe > 1.5 and rad_to_deg(bakis_yonu.angle_to(fark.normalized())) > b["aci"] * 0.5:
			continue
		# agir=true: geri savurur, sersemlet=true: düşmanı sersemletir
		oyuncu.hedefe_vur(d, b["hasar"], carpan, true, true, "", false)
		vurulan += 1
	_halka_efekti(merkez, b["renk"], b["yaricap"])
	oyuncu.ekran_salla(0.25)
	SavasYoneticisi.ses_cikar(oyuncu, 18.0, 0.8)
	if debug:
		print("🔮 Karanlık Patlama: ", vurulan, " düşman etkilendi | güç çarpanı: ", snappedf(carpan, 0.01))

# --- ELEKTRİK ZİNCİRİ: hedefe çarpar, sonra yakındaki düşmanlara atlar ---
func _elektrik_zinciri(b: Dictionary) -> bool:
	var ilk = _ilk_hedef(b["menzil"])
	if ilk == null:
		return false
	
	# Zinciri kur: ilk hedeften başlayıp her seferinde en yakın başka düşmana atla
	var zincir: Array = [ilk]
	var son = ilk
	for i in b["atlama"]:
		var sonraki = null
		var en_yakin: float = b["atlama_mesafe"]
		for d in get_tree().get_nodes_in_group("enemy"):
			if d in zincir or not _canli(d):
				continue
			var m: float = son.global_position.distance_to(d.global_position)
			if m < en_yakin:
				en_yakin = m
				sonraki = d
		if sonraki == null:
			break
		zincir.append(sonraki)
		son = sonraki
	
	_zincir_vur(zincir, b)
	SavasYoneticisi.ses_cikar(oyuncu, 20.0, 0.8)
	return true

# Zincirdeki düşmanlara sırayla vurur (her atlama arasında kısa bekleme, görsel olarak "atlasın" diye)
func _zincir_vur(zincir: Array, b: Dictionary) -> void:
	var onceki: Vector3 = oyuncu.global_position + Vector3.UP * 1.3 + bakis_yonu * 0.4
	var hasar: float = b["hasar"]
	for d in zincir:
		if not is_instance_valid(d):
			break
		var hedef_nokta: Vector3 = d.global_position + Vector3.UP * 1.1
		_simsek_ciz(onceki, hedef_nokta, b["renk"])
		# "govde" bölgesi: düşman Hit_Chest tepkisi verir
		oyuncu.hedefe_vur(d, hasar, 1.0, false, false, "govde", false)
		onceki = hedef_nokta
		hasar *= 0.7   # her atlamada hasar azalır
		await get_tree().create_timer(0.09, true, false, true).timeout

# ============================================================
# 4) YARDIMCI FONKSİYONLAR
# ============================================================

# Büyünün yönü: kilitli düşman varsa ona, yoksa kameranın baktığı yöne
func _bakis_hesapla() -> Vector3:
	var kilitli = oyuncu.get_locked_enemy()
	if kilitli:
		var f: Vector3 = kilitli.global_position - oyuncu.global_position
		f.y = 0.0
		if f.length() > 0.01:
			return f.normalized()
	var cam: Basis = oyuncu.camera_pivot.global_transform.basis
	return Vector3(-cam.z.x, 0.0, -cam.z.z).normalized()

func _canli(d) -> bool:
	if d == null or not is_instance_valid(d) or not (d is Node3D):
		return false
	var saglik = d.get("health")
	if saglik and saglik.get("can") != null and saglik.get("can") <= 0:
		return false
	return true

# Zincir gibi hedef isteyen büyüler için ilk hedef:
# kilitli düşman varsa o, yoksa baktığın yönde en yakın açıdaki (45 derece içinde) görünür düşman
func _ilk_hedef(menzil: float):
	oyuncu = state_machine.get_parent()
	var kilitli = oyuncu.get_locked_enemy()
	if kilitli and _canli(kilitli) and oyuncu.global_position.distance_to(kilitli.global_position) <= menzil:
		return kilitli
	
	var yon: Vector3 = _bakis_hesapla()
	var en_iyi = null
	var en_iyi_aci: float = 45.0
	var gogus: Vector3 = oyuncu.global_position + Vector3.UP * 1.2
	for d in get_tree().get_nodes_in_group("enemy"):
		if not _canli(d):
			continue
		var fark: Vector3 = d.global_position - oyuncu.global_position
		fark.y = 0.0
		if fark.length() > menzil or fark.length() < 0.1:
			continue
		var aci: float = rad_to_deg(yon.angle_to(fark.normalized()))
		if aci >= en_iyi_aci:
			continue
		# Araya duvar girmemiş olmalı
		if not ParkurYardimci.isin(oyuncu, gogus, d.global_position + Vector3.UP * 1.1).is_empty():
			continue
		en_iyi_aci = aci
		en_iyi = d
	return en_iyi

func _cik() -> void:
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() > 0.1:
		state_machine.transition_to($"../RunState")
	else:
		state_machine.transition_to($"../IdleState")

# Animasyonu verilen süreye sığdırarak oynatır (çok hızlanmasın diye hız 1-6 arasında sınırlanır)
func _anim_oynat(ad: String, sure: float) -> void:
	if anim == null or not anim.has_animation(ad):
		return
	var hiz: float = 1.0
	if sure > 0.0:
		hiz = clampf(anim.get_animation(ad).length / sure, 1.0, 6.0)
	anim.play(ad, 0.05, hiz)

# ============================================================
# 5) GÖRSEL EFEKTLER (kodla oluşturulur)
# ============================================================

# Genişleyen yarı saydam küre (patlama ve kalkan için)
func _halka_efekti(poz: Vector3, renk: Color, yaricap: float) -> void:
	var m: MeshInstance3D = MeshInstance3D.new()
	var kure: SphereMesh = SphereMesh.new()
	kure.radius = 1.0
	kure.height = 2.0
	m.mesh = kure
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(renk.r, renk.g, renk.b, 0.4)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(m)
	m.global_position = poz + Vector3.UP * 0.8
	m.scale = Vector3.ONE * 0.3
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * yaricap, 0.35)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(m.queue_free)

# Kısa süreli parçacık patlaması (gölge adımı için)
func _parcacik(poz: Vector3, renk: Color) -> void:
	var p: CPUParticles3D = CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 28
	p.lifetime = 0.55
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -1.5, 0)
	var kure: SphereMesh = SphereMesh.new()
	kure.radius = 0.07
	kure.height = 0.14
	p.mesh = kure
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = renk
	p.material_override = mat
	get_tree().current_scene.add_child(p)
	p.global_position = poz
	p.emitting = true
	await get_tree().create_timer(1.0, true, false, true).timeout
	if is_instance_valid(p):
		p.queue_free()

# A noktasından B noktasına kıvrımlı bir şimşek çizer (6 parçalı, her parçaya rastgele sapma)
func _simsek_ciz(a: Vector3, b: Vector3, renk: Color) -> void:
	var yon: Vector3 = b - a
	var uzun: float = yon.length()
	if uzun < 0.2:
		return
	var d: Vector3 = yon / uzun
	var yan: Vector3 = d.cross(Vector3.UP)
	if yan.length() < 0.1:
		yan = d.cross(Vector3.RIGHT)
	yan = yan.normalized()
	var yukari: Vector3 = yan.cross(d).normalized()
	
	var noktalar: Array = [a]
	var parca: int = 6
	for i in range(1, parca):
		var p: Vector3 = a + d * (uzun * float(i) / float(parca))
		p += yan * randf_range(-0.3, 0.3) + yukari * randf_range(-0.3, 0.3)
		noktalar.append(p)
	noktalar.append(b)
	for i in range(noktalar.size() - 1):
		_cizgi(noktalar[i], noktalar[i + 1], 0.05, renk, 0.18)

# İki nokta arasında ince, parlayan bir çizgi (kısa süre görünür)
func _cizgi(a: Vector3, b: Vector3, kalinlik: float, renk: Color, omur: float) -> void:
	var uzunluk: float = a.distance_to(b)
	if uzunluk < 0.01:
		return
	var m: MeshInstance3D = MeshInstance3D.new()
	var kutu: BoxMesh = BoxMesh.new()
	kutu.size = Vector3(kalinlik, kalinlik, uzunluk)
	m.mesh = kutu
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = renk
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(m)
	m.global_position = (a + b) * 0.5
	var yukari: Vector3 = Vector3.UP if absf((b - a).normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	m.look_at(b, yukari)
	await get_tree().create_timer(omur, true, false, true).timeout
	if is_instance_valid(m):
		m.queue_free()

# ============================================================
# 6) EKRAN ÜSTÜ: seçili büyü etiketi ve bildirimler
# ============================================================
func _hud_olustur() -> void:
	hud_katman = CanvasLayer.new()
	hud_katman.layer = 80
	get_tree().current_scene.add_child(hud_katman)
	hud_etiket = Label.new()
	hud_etiket.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hud_etiket.offset_left = 24.0
	hud_etiket.offset_right = 520.0
	hud_etiket.offset_top = -90.0
	hud_etiket.offset_bottom = -24.0
	hud_etiket.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hud_etiket.add_theme_font_size_override("font_size", 22)
	hud_etiket.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_etiket.add_theme_constant_override("outline_size", 6)
	hud_etiket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_katman.add_child(hud_etiket)

func _hud_guncelle() -> void:
	if hud_etiket == null or not is_instance_valid(hud_etiket) or state_machine == null:
		return
	var b: Dictionary = buyu_tablosu[aktif_buyu]
	var kalan: float = maxf((bekleme_bitis[aktif_buyu] - Time.get_ticks_msec()) / 1000.0, 0.0)
	var o = state_machine.get_parent()
	var kan_yetersiz: bool = o != null and o.get("kan") != null and o.get("kan") < b["maliyet"]
	
	var metin: String = "BÜYÜ: %s   (%d kan)" % [b["ad"], int(b["maliyet"])]
	var renk: Color = b["renk"]
	if kalan > 0.0:
		metin += "   %.1f sn" % kalan
		renk = renk.darkened(0.5)
	elif kan_yetersiz:
		metin += "   KAN YETERSİZ"
		renk = renk.darkened(0.5)
	hud_etiket.text = metin
	hud_etiket.add_theme_color_override("font_color", renk)

# Ekranın altında kısa süre görünen bildirim
func bildirim(metin: String, renk: Color) -> void:
	if bildirim_katmani and is_instance_valid(bildirim_katmani):
		bildirim_katmani.queue_free()
	var k: CanvasLayer = CanvasLayer.new()
	k.layer = 95
	get_tree().current_scene.add_child(k)
	bildirim_katmani = k
	var e: Label = Label.new()
	e.text = metin
	e.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	e.offset_left = -300.0
	e.offset_right = 300.0
	e.offset_top = -200.0
	e.offset_bottom = -140.0
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.add_theme_font_size_override("font_size", 28)
	e.add_theme_color_override("font_color", renk)
	e.add_theme_color_override("font_outline_color", Color.BLACK)
	e.add_theme_constant_override("outline_size", 8)
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	k.add_child(e)
	await get_tree().create_timer(1.2, true, false, true).timeout
	if is_instance_valid(k):
		k.queue_free()
# Gelecekte alt menüden doğrudan büyü seçmek için:
func buyu_sec(indeks: int) -> void:
	if indeks >= 3 and indeks < buyu_tablosu.size():
		aktif_buyu = indeks
		var b: Dictionary = buyu_tablosu[aktif_buyu]
		bildirim("BÜYÜ: " + b["ad"] + " (" + str(int(b["maliyet"])) + " kan)", b["renk"])
