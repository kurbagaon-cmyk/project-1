extends State

# ============================================================
# PARKUR STATE'İ
#
# Bu state üç hareket yapar:
#   1) VAULT  : Alçak bir engelin (sandık, çit, duvar) üstünden atlayıp karşı tarafa inmek
#   2) MANTLE : Yüksek bir kenara tutunup kendini yukarı çekmek (tırmanma)
#   3) TAKLA  : Yüksekten düşünce yere inerken yuvarlanmak (hasarı azaltır)
#
# NASIL ÇALIŞIR (kısaca):
#   a) Oyuncu zıplama tuşuna basınca PlayerNew, bu state'in `engel_tara()` fonksiyonunu çağırır.
#   b) `engel_tara()` önümüzdeki engeli "ışınlarla" (raycast) ölçer: nerede, ne kadar yüksek, ne kadar kalın,
#      üstünde ya da karşısında durulacak boş yer var mı. Sonuç olarak bir "plan" (Dictionary) döndürür.
#   c) Plan boş değilse PlayerNew `hazirla(plan)` çağırıp bu state'e geçer.
#   d) `enter()` planı bir "yol"a (üç-dört nokta) çevirir. `physics_update()` her karede karakteri
#      bu yol üzerinde birazcık ilerletir. Yol bitince state biter.
#
# Karakteri normal fizikle (move_and_slide) değil, doğrudan konumunu değiştirerek (global_position)
# taşıyoruz. Çünkü fizik motoru karakteri duvara çarpıp durdurur, bizse duvarın üstünden geçmek istiyoruz.
# ============================================================

# ------------------------------------------------------------
# AYARLAR (Inspector'dan da değiştirebilirsin)
# ------------------------------------------------------------
@export var debug: bool = true                    # Output'a parkur bilgisi yazar

# --- Algılama ---
@export var algilama_mesafesi: float = 1.1        # Önündeki engeli bu kadar uzaktan arar (metre)
@export var on_ray_yuksekligi: float = 0.55       # Yerdeyken engel arama ışınının yüksekliği (diz üstü)
@export var min_yukseklik: float = 0.45           # Bundan alçak engellerde parkur yapmaz (zaten yürüyerek aşılır)
@export var vault_max_yukseklik: float = 1.25     # Bu yüksekliğe kadar üstünden atlar
@export var mantle_max_yukseklik: float = 2.5     # Bu yüksekliğe kadar tırmanır (daha yüksekse hiçbir şey yapmaz)
@export var havada_min_yukseklik: float = 1.0     # Havadayken kenara tutunmak için kenar en az bu kadar yüksekte olmalı
@export var vault_max_kalinlik: float = 1.4       # Engel bundan inceyse karşı tarafa atlar, kalınsa üstüne çıkar
@export var bos_yukseklik: float = 1.9            # Durulacak yerin üstünde bu kadar boşluk olmalı (kafa mesafesi)
@export var mantle_ic_mesafe: float = 0.55        # Tırmanınca kenardan ne kadar içeri basılacağı

# --- Hareket süreleri (saniye) ---
@export var vault_sureleri: Array[float] = [0.2, 0.15, 0.2]
@export var mantle_yuksek_sureleri: Array[float] = [0.3, 0.5, 0.3]   # yüksek duvar: tutun, çekil, öne geç
@export var mantle_alcak_sureleri: Array[float] = [0.4, 0.3]         # alçak duvar: yüksel, öne geç
@export var hang_giris_suresi: float = 0.25
@export var vault_zirve: float = 0.3              # Atlarken engelin ne kadar üstünden geçileceği
@export var el_yuksekligi: float = 1.7            # Tutunurken ayaklar, kenarın bu kadar altında olur
@export var duvar_aralik: float = 0.4             # Tutunurken duvardan bu kadar uzakta durulur

# --- Çıkış ---
@export var cikis_hizi_vault: float = 5.0         # Vault bitince koşmaya devam hızı
@export var cikis_hizi_mantle: float = 2.0
@export var bekleme_suresi: float = 0.25          # Parkurdan sonra tekrar parkur için bekleme

# --- Takla (yüksekten inişte yuvarlanma) ---
@export var takla_suresi: float = 0.55
@export var takla_hizi: float = 6.0
@export var takla_dokunulmaz: float = 0.4         # Taklanın ilk bu kadar saniyesinde hasar almaz

# --- Animasyonlar ---
# Önce AnimationPlayer'da adında bu kelimeler geçen animasyon aranır (Mixamo'dan ekleyince otomatik bulunur).
# Bulunamazsa yedek animasyon oynar.
@export var yedek_vault: String = "Jump"
@export var yedek_mantle: String = "Jump"
@export var yedek_takla: String = "Roll"

# Karakter modeli +Z yönüne mi bakıyor? (diğer state'lerdeki ayarla aynı olmalı)
@export var model_ileri_z: bool = true

# ------------------------------------------------------------
# DEĞİŞKENLER (kodun kendi kullandığı, Inspector'da görünmez)
# ------------------------------------------------------------
var oyuncu = null                  # PlayerNew
var anim: AnimationPlayer
var veri: Dictionary = {}          # hazirla() ile gelen plan
var tip: String = ""               # "vault", "mantle" veya "takla"
var yol: Array = []                # karakterin izleyeceği noktalar (Vector3)
var sureler: Array = []            # her yol parçasının süresi
var toplam_sure: float = 0.0
var sayac: float = 0.0             # state'e girdiğimizden beri geçen süre
var yon: Vector3 = Vector3.FORWARD # hareket yönü (yatay)
var cikis_hizi: float = 0.0

# ============================================================
# 1) ENGEL TARAMA (PlayerNew çağırır)
# yon_istek: oyuncunun gitmek istediği yön, yerde: karakter yerde mi
# Döndürdüğü plan boşsa ({}) parkur yapılamaz demektir.
# ============================================================
func engel_tara(yon_istek: Vector3, yerde: bool) -> Dictionary:
	oyuncu = state_machine.get_parent()
	var ayak: Vector3 = oyuncu.global_position              # karakterin ayak konumu
	var yon_h: Vector3 = Vector3(yon_istek.x, 0.0, yon_istek.z).normalized()
	if yon_h == Vector3.ZERO:
		return {}
	
	# ---- ADIM 1: Önde bir duvar/engel var mı? ----
	# Yerdeyken diz üstünden, havadayken el hizasından birkaç yükseklikten ileriye ışın atarız.
	var yukseklikler: Array = [on_ray_yuksekligi]
	if not yerde:
		yukseklikler = [0.9, 1.4, 1.9]
	var duvar: Dictionary = {}
	for h in yukseklikler:
		var bas: Vector3 = ayak + Vector3.UP * h
		duvar = _isin(bas, bas + yon_h * algilama_mesafesi)
		if not duvar.is_empty():
			break
	if duvar.is_empty():
		return {}
	
	# Duvar yüzeyinin dikey olduğundan emin ol (rampa/zemin değil)
	var n: Vector3 = duvar["normal"]
	if absf(n.y) > 0.3:
		return {}
	# "ic_yon": duvarın içine doğru yön (duvar yüzeyine dik). Parkur bu yönde yapılır.
	var ic_yon: Vector3 = Vector3(-n.x, 0.0, -n.z).normalized()
	# Oyuncu duvara yeterince dik gidiyor mu? (duvara sürtünerek yürürken parkur başlamasın)
	if yon_h.dot(ic_yon) < 0.5:
		return {}
	
	# ---- ADIM 2: Duvar çok yüksek mi? ----
	# En yüksek tırmanabileceğimiz noktanın biraz üstünden ışın at: hâlâ duvar varsa bu duvar aşılamaz.
	var yuksek_bas: Vector3 = ayak + Vector3.UP * (mantle_max_yukseklik + 0.3)
	if not _isin(yuksek_bas, yuksek_bas + yon_h * (algilama_mesafesi + 0.4)).is_empty():
		return {}
	
	# ---- ADIM 3: Engelin üst yüzeyi nerede? ----
	# Duvar yüzeyinin biraz içinden, yukarıdan aşağıya ışın at. İlk çarptığı yer üst yüzeydir.
	var ust_x: Vector3 = duvar["position"] + ic_yon * 0.3
	var asagi: Dictionary = _isin(
		Vector3(ust_x.x, ayak.y + mantle_max_yukseklik + 0.2, ust_x.z),
		Vector3(ust_x.x, ayak.y - 0.2, ust_x.z))
	if asagi.is_empty():
		return {}
	var ust_n: Vector3 = asagi["normal"]
	if ust_n.y < 0.7:
		return {}   # üstü düz değil (eğik yüzey ya da tavan)
	var y_ust: float = asagi["position"].y
	var yukseklik: float = y_ust - ayak.y
	if yukseklik < min_yukseklik or yukseklik > mantle_max_yukseklik:
		return {}
	if not yerde and yukseklik < havada_min_yukseklik:
		return {}
	
	# ---- ADIM 4: Üstünde durulacak boşluk var mı? (tavan/kafa mesafesi) ----
	var ust_nokta: Vector3 = Vector3(ust_x.x, y_ust, ust_x.z)
	if not _isin(ust_nokta + Vector3.UP * 0.05, ust_nokta + Vector3.UP * bos_yukseklik).is_empty():
		return {}
	
	# ---- ADIM 5: VAULT mu, MANTLE mı? ----
	var tip_sonuc: String = "hang" if (not yerde or yukseklik > el_yuksekligi) else "mantle"
	var inis: Vector3 = Vector3.ZERO
	var kalinlik: float = 99.0
	
	if yerde and tip_sonuc == "mantle" and yukseklik <= vault_max_yukseklik:
		# Engelin karşı tarafına doğru 20 cm aralıklarla aşağı ışın atıp engelin nerede bittiğini buluruz.
		var d: float = 0.4
		var zemin_ilk: Dictionary = {}
		while d <= vault_max_kalinlik + 0.8:
			var nokta: Vector3 = duvar["position"] + ic_yon * d
			var zemin: Dictionary = _isin(
				Vector3(nokta.x, y_ust + 0.3, nokta.z),
				Vector3(nokta.x, ayak.y - 1.5, nokta.z))
			if zemin.is_empty():
				break   # altı boş (çukur): vault yapma
			if zemin["position"].y < y_ust - 0.35:
				kalinlik = d          # engel burada bitti
				zemin_ilk = zemin
				break
			d += 0.2
		
		if not zemin_ilk.is_empty() and kalinlik <= vault_max_kalinlik:
			# İniş noktasını engelin 0.45 m ilerisine al (kenara tam inmesin)
			inis = zemin_ilk["position"]
			var nokta2: Vector3 = duvar["position"] + ic_yon * (kalinlik + 0.45)
			var zemin2: Dictionary = _isin(
				Vector3(nokta2.x, y_ust + 0.3, nokta2.z),
				Vector3(nokta2.x, ayak.y - 1.5, nokta2.z))
			if not zemin2.is_empty() and absf(zemin2["position"].y - inis.y) < 0.3:
				inis = zemin2["position"]
			# İniş yerinde kafa mesafesi var mı?
			if _isin(inis + Vector3.UP * 0.1, inis + Vector3.UP * bos_yukseklik).is_empty():
				tip_sonuc = "vault"
	
	# ---- ADIM 6: MANTLE için üst yüzeyde basılacak yer var mı? ----
	var ust_poz: Vector3 = Vector3(
		duvar["position"].x + ic_yon.x * mantle_ic_mesafe,
		y_ust,
		duvar["position"].z + ic_yon.z * mantle_ic_mesafe)
	if tip_sonuc == "mantle":
		# Basılacak noktanın altında zemin (yüzey) devam ediyor mu?
		var yuzey: Dictionary = _isin(ust_poz + Vector3.UP * 0.3, ust_poz - Vector3.UP * 0.3)
		if yuzey.is_empty():
			return {}   # çok ince bir duvar: üstüne çıkılamaz
		if not _isin(ust_poz + Vector3.UP * 0.1, ust_poz + Vector3.UP * bos_yukseklik).is_empty():
			return {}   # üstünde tavan var
	
	if debug:
		print("[PARKUR] ", tip_sonuc.to_upper(), " bulundu | yükseklik=", snappedf(yukseklik, 0.01), " | kalınlık=", snappedf(kalinlik, 0.01), " | yerde=", yerde)
	
	return {
		"tip": tip_sonuc,
		"yon": ic_yon,
		"duvar": duvar["position"],
		"y_ust": y_ust,
		"yukseklik": yukseklik,
		"ust_poz": ust_poz,
		"inis": inis,
		"kalinlik": kalinlik,
	}

# PlayerNew, geçişten önce planı verir
func hazirla(plan: Dictionary) -> void:
	veri = plan

# ============================================================
# 2) STATE'E GİRİŞ: planı bir YOL'a çevir
# ============================================================
func enter() -> void:
	oyuncu = state_machine.get_parent()
	anim = oyuncu.anim
	tip = veri.get("tip", "")
	if tip == "":
		_bitir()
		return
	
	sayac = 0.0
	yon = veri["yon"]
	yol.clear()
	sureler.clear()
	
	# Parkur sırasında diğer eylemler kapalı: dodge_aktif bayrağı dodge, parry, nişan, şarj, ısırma,
	# radyal menü ve kilitlenme dönüşünü engeller.
	oyuncu.dodge_aktif = true
	oyuncu.set_meta("attack_pressed", false)
	if oyuncu.hitbox:
		oyuncu.hitbox.monitoring = false
	oyuncu.velocity = Vector3.ZERO
	_yuzu_don(yon)
	
	match tip:
		"vault":
			_vault_yolu()
		"mantle":
			_mantle_yolu()
		"hang":
			_mantle_yolu()
		"takla":
			_takla_baslat()
	
	toplam_sure = 0.0
	for s in sureler:
		toplam_sure += s
	if tip == "takla":
		toplam_sure = takla_suresi
	_anim_oynat()

# VAULT yolu: bulunduğun yer -> engelin ön kenarının üstü -> engelin ortasının üstü -> iniş noktası
func _vault_yolu() -> void:
	var ayak: Vector3 = oyuncu.global_position
	var duvar: Vector3 = veri["duvar"]
	var y_ust: float = veri["y_ust"]
	var ic: Vector3 = veri["yon"]
	var kalinlik: float = veri["kalinlik"]
	var inis: Vector3 = veri["inis"]
	
	var on_kenar: Vector3 = Vector3(duvar.x - ic.x * 0.15, y_ust + vault_zirve, duvar.z - ic.z * 0.15)
	var orta: Vector3 = Vector3(duvar.x + ic.x * kalinlik * 0.5, y_ust + vault_zirve, duvar.z + ic.z * kalinlik * 0.5)
	yol = [ayak, on_kenar, orta, inis]
	sureler = vault_sureleri.duplicate()
	cikis_hizi = cikis_hizi_vault

# MANTLE yolu: yüksek duvarda önce kenara asıl, sonra yukarı çekil, sonra öne geç
func _mantle_yolu() -> void:
	var ayak: Vector3 = oyuncu.global_position
	var duvar: Vector3 = veri["duvar"]
	var y_ust: float = veri["y_ust"]
	var ic: Vector3 = veri["yon"]
	var yukseklik: float = veri["yukseklik"]
	var ust_poz: Vector3 = veri["ust_poz"]
	
	# Duvarın hemen önü (duvardan duvar_aralik kadar geride)
	var xz: Vector3 = Vector3(duvar.x - ic.x * duvar_aralik, 0.0, duvar.z - ic.z * duvar_aralik)

	if tip == "hang":
		var asili: Vector3 = Vector3(
			xz.x,
			maxf(y_ust - el_yuksekligi, ayak.y),
			xz.z
		)
		yol = [ayak, asili]
		sureler = [hang_giris_suresi]
		cikis_hizi = 0.0
		return
	
	if yukseklik > el_yuksekligi:
		# Yüksek duvar: önce eller kenara yetişecek şekilde duvara yapış (asılma),
		# sonra yukarı çekil, sonra kenarın üstüne geç.
		var asili: Vector3 = Vector3(xz.x, maxf(y_ust - el_yuksekligi, ayak.y), xz.z)
		var kenar: Vector3 = Vector3(xz.x, y_ust, xz.z)
		yol = [ayak, asili, kenar, ust_poz]
		sureler = mantle_yuksek_sureleri.duplicate()
	else:
		# Alçak duvar: dikey yüksel, sonra öne geç
		var kenar2: Vector3 = Vector3(xz.x, y_ust, xz.z)
		yol = [ayak, kenar2, ust_poz]
		sureler = mantle_alcak_sureleri.duplicate()
	cikis_hizi = cikis_hizi_mantle

func _takla_baslat() -> void:
	cikis_hizi = takla_hizi * 0.4
	oyuncu.dokunulmaz = true   # takla başında hasar almaz

# ============================================================
# 3) HER KARE: karakteri yol üzerinde ilerlet
# ============================================================
func physics_update(delta: float) -> void:
	sayac += delta
	
	if tip == "takla":
		# Takla normal fizikle çalışır: öne doğru yavaşlayarak kayar
		var t: float = clampf(sayac / takla_suresi, 0.0, 1.0)
		var hiz: float = takla_hizi * (1.0 - t * t)
		oyuncu.velocity.x = yon.x * hiz
		oyuncu.velocity.z = yon.z * hiz
		oyuncu.move_and_slide()
		oyuncu.dokunulmaz = sayac <= takla_dokunulmaz
	else:
		# Vault ve mantle: konumu doğrudan yol üzerine koy
		oyuncu.velocity = Vector3.ZERO
		if yol.size() >= 2:
			oyuncu.global_position = _yoldaki_konum(sayac)
	
	if sayac >= toplam_sure:
		_bitir()

# Yol üzerinde, geçen süreye karşılık gelen konumu bulur.
# Yol birkaç parçadan oluşur; hangi parçada olduğumuzu süreleri toplayarak buluruz.
func _yoldaki_konum(t: float) -> Vector3:
	var kalan: float = t
	var son_parca: int = sureler.size() - 1
	for i in sureler.size():
		var sure: float = sureler[i]
		if kalan <= sure or i == son_parca:
			var k: float = clampf(kalan / sure, 0.0, 1.0)
			# Yumuşak başlangıç ve bitiş
			if sureler.size() == 1:
				k = smoothstep(0.0, 1.0, k)
			elif i == 0:
				k = 1.0 - cos(k * PI * 0.5)
			elif i == son_parca:
				k = sin(k * PI * 0.5)
			return yol[i].lerp(yol[i + 1], k)
		kalan -= sure
	return yol[yol.size() - 1]

# ============================================================
# 4) BİTİŞ VE ÇIKIŞ
# ============================================================
func _bitir() -> void:
	if tip == "hang":
		var ledge: State = state_machine.get_node_or_null("LedgeState") as State
		if ledge:
			ledge.call("hazirla", veri)
			state_machine.transition_to(ledge)
			return
		push_warning("LedgeState yok; kenara asılma tamamlanamadı.")
	if tip != "takla" and tip != "hang" and yol.size() > 0:
		# Son noktaya oturt ve koşmaya devam hızı ver
		oyuncu.global_position = yol[yol.size() - 1]
		var yatay: Vector3 = Vector3(yon.x, 0.0, yon.z)
		oyuncu.velocity = yatay * cikis_hizi + Vector3.DOWN * 1.0
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() > 0.1:
		state_machine.transition_to($"../RunState")
	else:
		state_machine.transition_to($"../IdleState")

func exit() -> void:
	if oyuncu:
		oyuncu.dodge_aktif = false
		oyuncu.dokunulmaz = false
		oyuncu.parkur_bekleme = bekleme_suresi
		# Düşme takibini sıfırla: parkur bitince "yüksekten düştü" sanılmasın
		oyuncu.havada_idi = false
		oyuncu.dusus_baslangic_y = oyuncu.global_position.y
	veri = {}
	tip = ""
	# Donmuş (pause) animasyon başka state'in animasyonunu engellemesin
	if anim and not anim.is_playing():
		anim.stop()

# ============================================================
# YARDIMCI FONKSİYONLAR
# ============================================================

# Işın (raycast) atar: ilk çarptığı şeyi döndürür.
func _isin(bas: Vector3, son: Vector3) -> Dictionary:
	var sorgu: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(bas, son)
	# Oyuncunun kendisini ve düşmanları ışın görmesin
	var haric: Array[RID] = [oyuncu.get_rid()]
	for d in get_tree().get_nodes_in_group("enemy"):
		if d is CollisionObject3D:
			haric.append(d.get_rid())
	sorgu.exclude = haric
	var sonuc: Dictionary = oyuncu.get_world_3d().direct_space_state.intersect_ray(sorgu)
	# Karakter gövdeleri (NPC vb.) engel sayılmaz
	if not sonuc.is_empty() and sonuc["collider"] is CharacterBody3D:
		return {}
	return sonuc

# Modeli (mesh) hareket yönüne çevirir
func _yuzu_don(f: Vector3) -> void:
	if f.length() < 0.01:
		return
	var aci: float = atan2(f.x, f.z)
	if not model_ileri_z:
		aci += PI
	oyuncu.mesh.global_rotation.y = aci

# AnimationPlayer'daki isimlerde anahtar kelimeyi arar, bulamazsa yedeği kullanır
func _anim_bul(anahtarlar: Array, yedek: String) -> String:
	if anim == null:
		return ""
	for adi in anim.get_animation_list():
		var kucuk: String = String(adi).to_lower()
		for k in anahtarlar:
			if kucuk.contains(k):
				return String(adi)
	if anim.has_animation(yedek):
		return yedek
	return ""

func _anim_oynat() -> void:
	var anahtarlar: Array = []
	var yedek: String = ""
	match tip:
		"vault":
			anahtarlar = ["vault"]
			yedek = yedek_vault
		"mantle":
			anahtarlar = ["mantle", "climb"]
			yedek = yedek_mantle
		"hang":
			anahtarlar = ["jump to hang", "reach"]
			yedek = yedek_mantle
		"takla":
			anahtarlar = ["landing roll", "land_roll"]
			yedek = yedek_takla
	var adi: String = _anim_bul(anahtarlar, yedek)
	if adi == "" or toplam_sure <= 0.0:
		return
	# Animasyonu, hareketin süresine sığacak hızda oynat
	var uzunluk: float = anim.get_animation(adi).length
	anim.play(adi, 0.08, uzunluk / toplam_sure)
