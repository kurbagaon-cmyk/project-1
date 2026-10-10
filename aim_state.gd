extends State

# ============================================================
# MENZİLLİ SİLAH: NİŞAN, KALÇADAN ATEŞ, HIZLI ATIŞ
# 3 giriş modu:
#   0 NİŞAN : ateşli silah modunda sağ tık (ya da Q) basılı: omuz üstü kamera, isabetli
#   1 KALÇA : ateşli silah modunda sol tık (nişan almadan): hızlı ama daha dağınık
#   2 HIZLI : KILIÇ modundayken Q'ya kısa dokunuş: silahı çek, ateş et, kılıca dön (Witcher işareti gibi).
#             Q'yu basılı tutarsan tam nişan moduna geçer.
# Hem kılıç hem ateşli silah modunda kullanılabilir. Seçili duruş radyal menüden değişir.
# İsabet: nişan yardımı (kilitli düşmana kenetlenir), küçük yayılma, bölgeye göre hasar (baş/gövde/bacak).
# ============================================================

const MOD_NISAN: int = 0
const MOD_KALCA: int = 1
const MOD_HIZLI: int = 2

# --- DURUŞ TABLOSU (değerleri buradan değiştir) ---
# hasar: taban hasar | yayilma: derece (küçük = isabetli) | aralik: atışlar arası sn
# sarjor: şarjör kapasitesi | doldurma: doldurma süresi sn | yedek: cephane havuzu
# ses: duyulma yarıçapı (m) | tepme: atış başına yayılma artışı | kamera_tepme: kamera sekmesi (derece)
# sarsinti: ekran sarsıntısı | odak_suresi: nişanın toplanma süresi | otomatik: basılı tutunca ateş
# karanlik: atış başına karanlık artışı | nisan_orani: nişan yardımının hedef yüksekliği (0.6 gövde, 0.85 kafa)
var durus_tablosu: Array = [
	{
		"ad": "HIZLI", "renk": Color(1.0, 0.85, 0.2),
		"hasar": 7.0, "yayilma": 1.8, "aralik": 0.16, "sarjor": 10, "doldurma": 1.4,
		"yedek": "normal", "ses": 22.0, "tepme": 0.35, "kamera_tepme": 0.4, "sarsinti": 0.03,
		"odak_suresi": 0.2, "menzil": 60.0, "otomatik": true, "karanlik": 0.0, "nisan_orani": 0.6,
	},
	{
		"ad": "AĞIR", "renk": Color(1.0, 1.0, 1.0),
		"hasar": 45.0, "yayilma": 0.12, "aralik": 0.9, "sarjor": 1, "doldurma": 1.8,
		"yedek": "normal", "ses": 30.0, "tepme": 0.1, "kamera_tepme": 1.6, "sarsinti": 0.16,
		"odak_suresi": 0.5, "menzil": 90.0, "otomatik": false, "karanlik": 0.0, "nisan_orani": 0.85,
	},
	{
		"ad": "KARANLIK", "renk": Color(0.7, 0.25, 1.0),
		"hasar": 30.0, "yayilma": 0.7, "aralik": 0.28, "sarjor": 5, "doldurma": 1.6,
		"yedek": "karanlik", "ses": 28.0, "tepme": 0.3, "kamera_tepme": 1.0, "sarsinti": 0.09,
		"odak_suresi": 0.3, "menzil": 70.0, "otomatik": false, "karanlik": 4.0, "nisan_orani": 0.65,
	},
]

# Başlangıç cephanesi
@export var baslangic_normal_mermi: int = 40
@export var baslangic_karanlik_barut: int = 12

@export var yuruyus_hizi: float = 3.0
@export var donus_hizi: float = 20.0
# Nişan alırken kamera: yakınlaşma çarpanı, FOV azalması, omuz kaydırma, geçiş hızı
@export var kamera_yaklasma: float = 0.75
@export var fov_azalt: float = 8.0
@export var omuz_kaydirma: float = 0.45
@export var kamera_hizi: float = 14.0
# Karakter modeli +Z yönüne mi bakıyor? (diğer state'lerdeki ayarla aynı olmalı)
@export var model_ileri_z: bool = true
@export var kilici_gizle: bool = true             # kılıç modunda silah çekilince kılıç gizlenir

# Kalçadan ateş
@export var kalca_yayilma_carpani: float = 1.7
@export var kalca_sure: float = 0.5               # son atıştan sonra silahın indirilme süresi
# Hızlı atış (kılıç modunda Q dokunuşu)
@export var tap_esigi: float = 0.2                # bundan kısa basış = hızlı atış, uzun basış = nişan
@export var cekme_suresi: float = 0.12            # silahı çekip ateş etme süresi
@export var hizli_cikis_suresi: float = 0.3       # atıştan sonra kılıca dönme süresi
@export var hizli_yayilma_carpani: float = 1.3
# Nişan yardımı: koni (derece) ve güç (0..1). Kilitliyken hedefe kenetlenir.
@export var yardim_koni_nisan: float = 6.0
@export var yardim_guc_nisan: float = 0.75
@export var yardim_koni_kalca: float = 9.0
@export var yardim_guc_kalca: float = 0.5
@export var yardim_koni_hizli: float = 25.0
@export var yardim_guc_hizli: float = 1.0
@export var yardim_koni_kilitli: float = 35.0
# Bölgeye göre hasar çarpanı ve bölge sınırları (hedef boyunun oranı)
@export var bas_carpani: float = 2.0
@export var govde_carpani: float = 1.0
@export var bacak_carpani: float = 0.7
@export var bas_orani: float = 0.8
@export var bacak_orani: float = 0.45

var aktif_durus: int = 0
var sarjor: Array = []
var yedek: Dictionary = {}
var ates_bekleme: float = 0.0
var doldurma_sirada: int = -1       # hangi duruşun şarjörü doluyor (-1 = doldurma yok)
var doldurma_bitis_ms: int = 0
var nisan_suresi: float = 0.0
var tepme: float = 0.0
var atis_anim_kalan: float = 0.0
var isabet_flash: float = 0.0
var isabet_renk: Color = Color(1.0, 0.2, 0.2)
var onceki_tik: bool = false
var bakis_yonu: Vector3 = Vector3.FORWARD

# PlayerNew geçişten ÖNCE ayarlar: MOD_NISAN / MOD_KALCA / MOD_HIZLI
var giris_modu: int = 0
var mod: int = 0
var aktif: bool = false
var nisan_tutuluyor: bool = false
var kalca_sayac: float = 0.0
var q_suresi: float = 0.0
var hizli_basladi: bool = false
var hizli_atildi: bool = false
var hizli_zaman: float = 0.0
var hizli_cikis: float = 0.0
var kilic_gizlendi: bool = false
var bildirim_katmani: CanvasLayer = null

var oyuncu = null
var anim: AnimationPlayer
var kamera: Camera3D = null
var kamera_kolu: SpringArm3D = null
var spring_orijinal: float = 0.0
var fov_orijinal: float = 75.0
var h_orijinal: float = 0.0
var katman: CanvasLayer = null
var cizgiler: Array = []
var bilgi: Label = null

func _ready() -> void:
	for d in durus_tablosu:
		sarjor.append(d["sarjor"])
	yedek = {"normal": baslangic_normal_mermi, "karanlik": baslangic_karanlik_barut}

func enter() -> void:
	oyuncu = state_machine.get_parent()
	anim = oyuncu.anim
	aktif = true
	mod = giris_modu
	giris_modu = MOD_NISAN
	nisan_suresi = 0.0
	tepme = 0.0
	atis_anim_kalan = 0.0
	isabet_flash = 0.0
	q_suresi = 0.0
	hizli_basladi = false
	hizli_atildi = false
	hizli_zaman = 0.0
	hizli_cikis = 0.0
	kalca_sayac = kalca_sure
	nisan_tutuluyor = (mod == MOD_NISAN)
	# Kalçadan girdiysek ilk tık ateş eder; diğerlerinde basılı tık hemen ateş etmesin
	onceki_tik = false if mod == MOD_KALCA else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	
	# Diğer işlemler kapalı (dodge hâlâ açık, silahı iptal eder)
	oyuncu.set_meta("attack_pressed", false)
	if oyuncu.hitbox:
		oyuncu.hitbox.monitoring = false
	oyuncu.parry_durumda = true
	
	# Kılıç modunda silah çekilince kılıcı gizle
	kilic_gizlendi = false
	if kilici_gizle and oyuncu.get("silah_modu") == 0:
		oyuncu.kilic_goster(false)
		kilic_gizlendi = true
	
	kamera = get_viewport().get_camera_3d()
	kamera_kolu = oyuncu.find_child("SpringArm3D", true, false)
	if kamera_kolu:
		spring_orijinal = kamera_kolu.spring_length
	if kamera:
		fov_orijinal = kamera.fov
		h_orijinal = kamera.h_offset
	
	_hud_olustur()

func exit() -> void:
	aktif = false
	if oyuncu:
		oyuncu.parry_durumda = false
		oyuncu.set_meta("attack_pressed", false)
		if kilic_gizlendi and oyuncu.get("silah_modu") == 0:
			oyuncu.kilic_goster(true)
	kilic_gizlendi = false
	if kamera_kolu and is_instance_valid(kamera_kolu):
		kamera_kolu.spring_length = spring_orijinal
	if kamera and is_instance_valid(kamera):
		kamera.fov = fov_orijinal
		kamera.h_offset = h_orijinal
	_hud_kaldir()

func physics_update(delta: float) -> void:
	_doldur_kontrol()
	var s: Dictionary = durus_tablosu[aktif_durus]
	var aim_tus: bool = _aim_tusu()
	var basili: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	
	# --- Mod geçişleri ve çıkış koşulları ---
	match mod:
		MOD_NISAN:
			if not aim_tus:
				_cik()
				return
		MOD_KALCA:
			if aim_tus:
				mod = MOD_NISAN
			else:
				if basili:
					kalca_sayac = kalca_sure
				else:
					kalca_sayac -= delta
				if kalca_sayac <= 0.0:
					_cik()
					return
		MOD_HIZLI:
			if not hizli_basladi:
				if aim_tus:
					q_suresi += delta
					if q_suresi >= tap_esigi:
						mod = MOD_NISAN      # uzun basış: tam nişan
				else:
					hizli_basladi = true     # kısa dokunuş: hızlı atış
					hizli_zaman = maxf(cekme_suresi - q_suresi, 0.0)
	nisan_tutuluyor = (mod == MOD_NISAN)
	
	oyuncu.set_meta("attack_pressed", false)
	ates_bekleme = maxf(ates_bekleme - delta, 0.0)
	tepme = maxf(tepme - 6.0 * delta, 0.0)
	nisan_suresi += delta
	atis_anim_kalan = maxf(atis_anim_kalan - delta, 0.0)
	isabet_flash = maxf(isabet_flash - delta, 0.0)
	
	# Kameranın baktığı yön, karakter oraya döner
	var cam: Basis = oyuncu.camera_pivot.global_transform.basis
	var cam_ileri: Vector3 = Vector3(-cam.z.x, 0.0, -cam.z.z).normalized()
	var cam_sag: Vector3 = Vector3(cam.x.x, 0.0, cam.x.z).normalized()
	bakis_yonu = cam_ileri
	_yuzu_don(cam_ileri, delta)
	
	# Yürüme (kameraya göre)
	var hedef_hiz: Vector3 = Vector3.ZERO
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() > 0.1:
		var yon: Vector3 = (cam_sag * input_dir.x + cam_ileri * (-input_dir.y)).normalized()
		hedef_hiz = yon * yuruyus_hizi * minf(input_dir.length(), 1.0)
	oyuncu.velocity.x = move_toward(oyuncu.velocity.x, hedef_hiz.x, 35.0 * delta)
	oyuncu.velocity.z = move_toward(oyuncu.velocity.z, hedef_hiz.z, 35.0 * delta)
	oyuncu.move_and_slide()
	
	_kamera_guncelle(delta)
	
	# --- Ateş ---
	if mod == MOD_HIZLI:
		_hizli_isle(delta, s)
	else:
		var yeni_tik: bool = basili and not onceki_tik
		onceki_tik = basili
		if (yeni_tik or (basili and s["otomatik"])) and ates_bekleme <= 0.0 and doldurma_sirada < 0:
			if sarjor[aktif_durus] <= 0:
				_doldur_baslat()
			else:
				_ates_et(s, mod)
	
	_animasyon_guncelle()
	_hud_guncelle(s)

# Kılıç modunda Q dokunuşu: silahı çek, ateş et, geri dön
func _hizli_isle(delta: float, s: Dictionary) -> void:
	if not hizli_basladi:
		return
	if not hizli_atildi:
		hizli_zaman -= delta
		if hizli_zaman <= 0.0:
			hizli_atildi = true
			hizli_cikis = hizli_cikis_suresi
			if doldurma_sirada >= 0:
				pass
			elif sarjor[aktif_durus] <= 0:
				_doldur_baslat()   # boşsa arka planda doldurmaya başla
			else:
				_ates_et(s, MOD_HIZLI)
	else:
		hizli_cikis -= delta
		if hizli_cikis <= 0.0:
			_cik()

func _aim_tusu() -> bool:
	if InputMap.has_action("aim") and Input.is_action_pressed("aim"):
		return true
	# Ateşli silah modunda sağ tık (parry action'ı) nişan alır
	if oyuncu.get("silah_modu") == 1 and InputMap.has_action("parry") and Input.is_action_pressed("parry"):
		return true
	return false

# ------------------------------------------------------------
# DURUŞ DEĞİŞTİRME (PlayerNew çağırır, nişan almıyorken de çalışır)
# ------------------------------------------------------------
func durus_sec(i: int) -> void:
	aktif_durus = clampi(i, 0, durus_tablosu.size() - 1)
	doldurma_sirada = -1
	nisan_suresi = 0.0
	print("🔫 Silah duruşu: ", durus_tablosu[aktif_durus]["ad"])

# Hızlı -> Ağır -> Karanlık -> Hızlı (karanlık barut bittiyse karanlık atlanır)
func durus_dongu() -> void:
	var sonraki: int = (aktif_durus + 1) % durus_tablosu.size()
	for i in durus_tablosu.size():
		var d: Dictionary = durus_tablosu[sonraki]
		if d["yedek"] == "karanlik" and yedek["karanlik"] <= 0 and sarjor[sonraki] <= 0:
			sonraki = (sonraki + 1) % durus_tablosu.size()
		else:
			break
	durus_sec(sonraki)

# Eski kod uyumluluğu: son duruştan sonra false döner
func sonraki_durus() -> bool:
	var sonraki: int = aktif_durus + 1
	if sonraki >= durus_tablosu.size():
		return false
	durus_sec(sonraki)
	return true

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
	e.offset_top = -160.0
	e.offset_bottom = -100.0
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.add_theme_font_size_override("font_size", 30)
	e.add_theme_color_override("font_color", renk)
	e.add_theme_color_override("font_outline_color", Color.BLACK)
	e.add_theme_constant_override("outline_size", 8)
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	k.add_child(e)
	await get_tree().create_timer(1.2, true, false, true).timeout
	if is_instance_valid(k):
		k.queue_free()

# ------------------------------------------------------------
# ATEŞ
# ------------------------------------------------------------
func _ates_et(s: Dictionary, atis_modu: int) -> void:
	sarjor[aktif_durus] -= 1
	ates_bekleme = s["aralik"]
	var aci: float = _etkin_yayilma(s, atis_modu)
	tepme = minf(tepme + s["tepme"], 4.0)
	nisan_suresi *= 0.5
	kalca_sayac = kalca_sure
	
	if kamera == null or not is_instance_valid(kamera):
		kamera = get_viewport().get_camera_3d()
	# Ekranın ortasından çıkan ışın: önce nişan yardımı, sonra yayılma
	var merkez: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var bas: Vector3 = kamera.project_ray_origin(merkez)
	var yon: Vector3 = kamera.project_ray_normal(merkez)
	yon = _nisan_yardimi(bas, yon, s, atis_modu)
	yon = _sapma(yon, aci)
	var son: Vector3 = bas + yon * s["menzil"]
	var sorgu: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(bas, son)
	sorgu.exclude = [oyuncu.get_rid()]
	var sonuc: Dictionary = oyuncu.get_world_3d().direct_space_state.intersect_ray(sorgu)
	
	var vurus_noktasi: Vector3 = son
	var vurulan = null
	if not sonuc.is_empty():
		vurus_noktasi = sonuc["position"]
		vurulan = sonuc["collider"]
	
	# Hasar: vurulan bölgeye göre (baş / gövde / bacak)
	var bolge: String = ""
	if vurulan != null and is_instance_valid(vurulan) and vurulan.has_method("take_damage"):
		bolge = _bolge_bul(vurulan, vurus_noktasi)
		var carpan: float = _bolge_carpani(bolge)
		if oyuncu.has_method("hedefe_vur"):
			oyuncu.hedefe_vur(vurulan, s["hasar"], carpan, false, false, bolge, false)
		else:
			vurulan.take_damage(int(s["hasar"] * carpan))
		isabet_flash = 0.15
		match bolge:
			"bas":
				isabet_renk = Color(1.0, 0.9, 0.2)
			"bacak":
				isabet_renk = Color(1.0, 0.55, 0.1)
			_:
				isabet_renk = Color(1.0, 0.2, 0.2)
	
	# Gürültü: yakındaki düşmanlar sese gelir
	SavasYoneticisi.ses_cikar(oyuncu, s["ses"], 0.9)
	
	# Karanlık barut seni karanlığa sürükler
	if s["karanlik"] > 0.0:
		OyunDurumu.karanlik_kazan(s["karanlik"], oyuncu)
	
	# Hissiyat: sarsıntı, kamera sekmesi, namlu ışığı, mermi izi, animasyon
	oyuncu.ekran_salla(s["sarsinti"])
	if s["kamera_tepme"] > 0.0:
		oyuncu.camera_pitch = clampf(oyuncu.camera_pitch + deg_to_rad(s["kamera_tepme"]), deg_to_rad(-60), deg_to_rad(60))
		oyuncu.camera_pivot.rotation.x = oyuncu.camera_pitch
	var namlu: Vector3 = oyuncu.global_position + Vector3(0, 1.4, 0) + bakis_yonu * 0.5
	_namlu_isigi(namlu, s["renk"])
	_iz_ciz(namlu, vurus_noktasi, s["renk"])
	if anim and anim.has_animation("Pistol_Shoot"):
		anim.play("Pistol_Shoot", 0.02)
		atis_anim_kalan = 0.15
	
	print("🔫 ", s["ad"], " | kalan: ", sarjor[aktif_durus], " | yayılma: ", snappedf(aci, 0.1), "° | bölge: ", bolge if bolge != "" else "ıskaladı")

# Yayılma (derece): hareket dağıtır, nişanı tutmak toplar, kalçadan ateş dağıtır
func _etkin_yayilma(s: Dictionary, atis_modu: int) -> float:
	var a: float = s["yayilma"]
	var hiz: float = Vector2(oyuncu.velocity.x, oyuncu.velocity.z).length()
	if hiz > 0.5:
		a *= 1.4
	var odak: float = clampf(nisan_suresi / s["odak_suresi"], 0.0, 1.0)
	a *= lerpf(1.3, 1.0, odak)
	if atis_modu == MOD_KALCA:
		a *= kalca_yayilma_carpani
	elif atis_modu == MOD_HIZLI:
		a *= hizli_yayilma_carpani
	return minf(a + tepme, 8.0)

# Nişan yardımı: ışını yakındaki canlı düşmanın gövdesine/kafasına doğru çeker.
# Kilitliyken sadece kilitli hedefe kenetlenir.
func _nisan_yardimi(bas: Vector3, yon: Vector3, s: Dictionary, atis_modu: int) -> Vector3:
	var koni: float = yardim_koni_nisan
	var guc: float = yardim_guc_nisan
	if atis_modu == MOD_KALCA:
		koni = yardim_koni_kalca
		guc = yardim_guc_kalca
	elif atis_modu == MOD_HIZLI:
		koni = yardim_koni_hizli
		guc = yardim_guc_hizli
	
	var kilitli = oyuncu.get_locked_enemy()
	if kilitli:
		koni = maxf(koni, yardim_koni_kilitli)
		guc = maxf(guc, 0.9)
	
	var en_iyi_yon: Vector3 = yon
	var en_iyi_aci: float = koni
	var bulundu: bool = false
	for d in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(d) or not (d is Node3D):
			continue
		if kilitli and d != kilitli:
			continue
		var saglik = d.get("health")
		if saglik and saglik.get("can") != null and saglik.get("can") <= 0:
			continue
		var nokta: Vector3 = d.global_position + Vector3(0, _hedef_boyu(d) * s["nisan_orani"], 0)
		var hedef_yon: Vector3 = (nokta - bas).normalized()
		var aci: float = rad_to_deg(yon.angle_to(hedef_yon))
		if aci < en_iyi_aci and _gorus_acik(bas, nokta, d):
			en_iyi_aci = aci
			en_iyi_yon = hedef_yon
			bulundu = true
	if not bulundu:
		return yon
	return yon.slerp(en_iyi_yon, guc).normalized()

func _gorus_acik(bas: Vector3, nokta: Vector3, d) -> bool:
	var sorgu: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(bas, nokta)
	var haric: Array[RID] = [oyuncu.get_rid()]
	if d is CollisionObject3D:
		haric.append(d.get_rid())
	sorgu.exclude = haric
	return oyuncu.get_world_3d().direct_space_state.intersect_ray(sorgu).is_empty()

# ------------------------------------------------------------
# BÖLGE (baş / gövde / bacak)
# ------------------------------------------------------------
# Düşmanın boyu: çarpışma kapsülünden okunur (bulunamazsa 1.8)
func _hedef_boyu(hedef: Node3D) -> float:
	var kapsul = hedef.find_child("CollisionShape3D", false, false)
	if kapsul != null and kapsul.shape is CapsuleShape3D:
		var olcek: float = hedef.global_transform.basis.get_scale().y
		return maxf(kapsul.position.y + kapsul.shape.height * 0.5, 0.5) * olcek
	return 1.8

func _bolge_bul(hedef: Node3D, nokta: Vector3) -> String:
	var boy: float = _hedef_boyu(hedef)
	var oran: float = (nokta.y - hedef.global_position.y) / boy
	if oran >= bas_orani:
		return "bas"
	if oran < bacak_orani:
		return "bacak"
	return "govde"

func _bolge_carpani(bolge: String) -> float:
	match bolge:
		"bas":
			return bas_carpani
		"bacak":
			return bacak_carpani
	return govde_carpani

# ------------------------------------------------------------
# EFEKTLER
# ------------------------------------------------------------
# Yönü, verilen açı kadar koni içinde rastgele saptırır
func _sapma(yon: Vector3, aci_derece: float) -> Vector3:
	if aci_derece <= 0.01:
		return yon
	var r: float = sqrt(randf()) * deg_to_rad(aci_derece)
	var teta: float = randf() * TAU
	var yardimci: Vector3 = Vector3.UP if absf(yon.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var sag: Vector3 = yon.cross(yardimci).normalized()
	var yukari: Vector3 = sag.cross(yon).normalized()
	return (yon + (sag * cos(teta) + yukari * sin(teta)) * tan(r)).normalized()

# Kısa süre görünen mermi izi
func _iz_ciz(bas: Vector3, son: Vector3, renk: Color) -> void:
	var uzunluk: float = bas.distance_to(son)
	if uzunluk < 0.1:
		return
	var m: MeshInstance3D = MeshInstance3D.new()
	var kutu: BoxMesh = BoxMesh.new()
	kutu.size = Vector3(0.02, 0.02, uzunluk)
	m.mesh = kutu
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = renk
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(m)
	m.global_position = (bas + son) * 0.5
	var yukari: Vector3 = Vector3.UP if absf((son - bas).normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	m.look_at(son, yukari)
	await get_tree().create_timer(0.06, true, false, true).timeout
	if is_instance_valid(m):
		m.queue_free()

# Namlu ışığı: çok kısa süren parlama
func _namlu_isigi(poz: Vector3, renk: Color) -> void:
	var isik: OmniLight3D = OmniLight3D.new()
	isik.light_color = renk
	isik.light_energy = 4.0
	isik.omni_range = 6.0
	get_tree().current_scene.add_child(isik)
	isik.global_position = poz
	await get_tree().create_timer(0.05, true, false, true).timeout
	if is_instance_valid(isik):
		isik.queue_free()

# ------------------------------------------------------------
# DOLDURMA (arka planda da çalışır: kılıç modunda silahı çekmeden doldurabilirsin)
# ------------------------------------------------------------
# PlayerNew'dan `reload` tuşuyla çağrılır
func doldur_istegi() -> void:
	_doldur_baslat()

func _doldur_baslat() -> void:
	var s: Dictionary = durus_tablosu[aktif_durus]
	if doldurma_sirada >= 0:
		return
	if sarjor[aktif_durus] >= s["sarjor"]:
		return
	if yedek[s["yedek"]] <= 0:
		bildirim("CEPHANE YOK", s["renk"])
		return
	doldurma_sirada = aktif_durus
	doldurma_bitis_ms = Time.get_ticks_msec() + int(s["doldurma"] * 1000.0)
	if aktif and anim and anim.has_animation("Pistol_Reload"):
		var uzunluk: float = anim.get_animation("Pistol_Reload").length
		anim.play("Pistol_Reload", 0.05, uzunluk / s["doldurma"])
	if not (aktif and mod == MOD_NISAN):
		bildirim("DOLDURULUYOR...", s["renk"])
	await get_tree().create_timer(s["doldurma"], true, false, true).timeout
	_doldur_kontrol()

func _doldur_kontrol() -> void:
	if doldurma_sirada < 0 or Time.get_ticks_msec() < doldurma_bitis_ms:
		return
	var i: int = doldurma_sirada
	doldurma_sirada = -1
	var d: Dictionary = durus_tablosu[i]
	var eksik: int = d["sarjor"] - sarjor[i]
	var al: int = mini(eksik, yedek[d["yedek"]])
	sarjor[i] += al
	yedek[d["yedek"]] -= al

# ------------------------------------------------------------
# KAMERA, ANİMASYON, YÖN
# ------------------------------------------------------------
func _kamera_guncelle(delta: float) -> void:
	var k: float = clampf(kamera_hizi * delta, 0.0, 1.0)
	# Kamera sadece tam nişan alırken yakınlaşır
	var yaklasma: float = kamera_yaklasma if nisan_tutuluyor else 1.0
	var fov_hedef: float = fov_orijinal - (fov_azalt if nisan_tutuluyor else 0.0)
	var h_hedef: float = h_orijinal + (omuz_kaydirma if nisan_tutuluyor else 0.0)
	if kamera_kolu and is_instance_valid(kamera_kolu):
		kamera_kolu.spring_length = lerpf(kamera_kolu.spring_length, spring_orijinal * yaklasma, k)
	if kamera and is_instance_valid(kamera):
		kamera.fov = lerpf(kamera.fov, fov_hedef, k)
		kamera.h_offset = lerpf(kamera.h_offset, h_hedef, k)

func _animasyon_guncelle() -> void:
	if anim == null or atis_anim_kalan > 0.0 or doldurma_sirada >= 0:
		return
	var pitch: float = rad_to_deg(oyuncu.camera_pitch)
	var ad: String = "Pistol_Aim_Neutral"
	if pitch > 12.0:
		ad = "Pistol_Aim_Up"
	elif pitch < -12.0:
		ad = "Pistol_Aim_Down"
	if anim.has_animation(ad) and (anim.current_animation != ad or not anim.is_playing()):
		anim.play(ad, 0.06)

func _yuzu_don(f: Vector3, delta: float) -> void:
	if f.length() < 0.01:
		return
	var hedef_aci: float = atan2(f.x, f.z)
	if not model_ileri_z:
		hedef_aci += PI
	var mesh: Node3D = oyuncu.mesh
	mesh.global_rotation.y = lerp_angle(mesh.global_rotation.y, hedef_aci, clampf(donus_hizi * delta, 0.0, 1.0))

func _cik() -> void:
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() > 0.1:
		state_machine.transition_to($"../RunState")
	else:
		state_machine.transition_to($"../IdleState")

# ------------------------------------------------------------
# EKRAN ÜSTÜ: NİŞANGÂH VE CEPHANE (kodla oluşturulur)
# ------------------------------------------------------------
func _hud_olustur() -> void:
	katman = CanvasLayer.new()
	katman.layer = 90
	get_tree().current_scene.add_child(katman)
	
	var merkez: Control = Control.new()
	merkez.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	merkez.mouse_filter = Control.MOUSE_FILTER_IGNORE
	katman.add_child(merkez)
	cizgiler.clear()
	for i in 4:
		var c: ColorRect = ColorRect.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		merkez.add_child(c)
		cizgiler.append(c)
	
	bilgi = Label.new()
	bilgi.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bilgi.offset_left = -330.0
	bilgi.offset_top = -120.0
	bilgi.offset_right = -24.0
	bilgi.offset_bottom = -24.0
	bilgi.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bilgi.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	bilgi.add_theme_font_size_override("font_size", 24)
	bilgi.add_theme_color_override("font_outline_color", Color.BLACK)
	bilgi.add_theme_constant_override("outline_size", 6)
	bilgi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	katman.add_child(bilgi)

func _hud_kaldir() -> void:
	if katman and is_instance_valid(katman):
		katman.queue_free()
	katman = null
	bilgi = null
	cizgiler.clear()

func _hud_guncelle(s: Dictionary) -> void:
	if katman == null or cizgiler.size() < 4 or bilgi == null:
		return
	var renk: Color = isabet_renk if isabet_flash > 0.0 else s["renk"]
	# Nişangâh boşluğu yayılmayla büyür/küçülür
	var bosluk: float = 5.0 + _etkin_yayilma(s, mod) * 6.0
	cizgiler[0].position = Vector2(-1, -bosluk - 10); cizgiler[0].size = Vector2(2, 10)
	cizgiler[1].position = Vector2(-1, bosluk);       cizgiler[1].size = Vector2(2, 10)
	cizgiler[2].position = Vector2(-bosluk - 10, -1); cizgiler[2].size = Vector2(10, 2)
	cizgiler[3].position = Vector2(bosluk, -1);       cizgiler[3].size = Vector2(10, 2)
	for c in cizgiler:
		c.color = renk
	
	var metin: String = "%s   %d / %d" % [s["ad"], sarjor[aktif_durus], yedek[s["yedek"]]]
	if doldurma_sirada >= 0:
		metin += "\nDOLDURULUYOR..."
	metin += "\nKaranlık: %d" % int(OyunDurumu.karanlik)
	bilgi.text = metin
	bilgi.add_theme_color_override("font_color", s["renk"])
