extends AIState

# ============================================================
# DÜŞMAN SALDIRI STATE'İ
# Hazırlık (uyarı) -> Vuruş (öne atılma + hasar anı) -> Toparlanma (açıkta kalır)
# ============================================================

enum Evre { HAZIRLIK, VURUS, TOPARLANMA }

# Saldırı çeşitleri, her saldırıda biri rastgele seçilir. Süreler saniye.
# anim       : animasyon adı (AnimationPlayer'daki isim)
# hazirlik   : uyarı süresi, oyuncunun kaçması için zaman
# vurus      : hasarın verilebildiği kısa pencere
# toparlanma : vuruştan sonra düşmanın açıkta kaldığı süre
# hasar      : oyuncuya verilen hasar
# atilma     : vuruş sırasında öne doğru hız (0 = yerinde vurur)
var saldirilar: Array = [
	{"anim": "Sword_Attack", "hazirlik": 0.45, "vurus": 0.15, "toparlanma": 0.45, "hasar": 15, "atilma": 5.0},
	{"anim": "Punch_Jab", "hazirlik": 0.25, "vurus": 0.12, "toparlanma": 0.35, "hasar": 8, "atilma": 3.0},
]

# Vuruş anında oyuncu bu mesafenin içindeyse ve önündeyse hasar alır.
@export var vurus_menzili: float = 2.0
# Düşmanın önündeki vuruş açısı (derece, toplam genişlik)
@export var vurus_acisi: float = 100.0
# Hazırlığın ilk bu kadarlık kısmında düşman seni takip eder, sonra yönü kilitlenir.
# Kilitlendikten sonra yana kaçarsan vuruştan kurtulursun.
@export_range(0.1, 1.0) var yon_kilit_orani: float = 0.6
# Atılırken oyuncuya bu mesafeden fazla yaklaşmaz (iç içe geçmesin)
@export var min_yaklasma: float = 1.0
# Saldırı bittikten sonra bir sonraki saldırıya kadar rastgele bekleme (saniye)
@export var bekleme_min: float = 1.0
@export var bekleme_max: float = 2.2
# Açıkken Output paneline saldırının hangi aşamada ne yaptığını yazar
@export var debug: bool = true
# Kombo: toparlanmadan sonra oyuncu hâlâ yakındaysa ikinci bir hızlı saldırı gelebilir
@export var kombo_sansi: float = 0.35
@export var max_kombo: int = 1
@export var kombo_menzili: float = 2.6

var evre: Evre = Evre.HAZIRLIK
var sayac: float = 0.0
var secili: Dictionary = {}
var yon: Vector3 = Vector3.FORWARD
var vurdu: bool = false
var anim: AnimationPlayer
var kombo_hakki: int = 0

func enter() -> void:
	kombo_hakki = max_kombo
	_saldiri_baslat(false)

func _saldiri_baslat(kombo: bool) -> void:
	secili = saldirilar.pick_random().duplicate()
	if kombo:
		# Kombo vuruşu daha hızlı gelir
		secili["hazirlik"] = secili["hazirlik"] * 0.7
	evre = Evre.HAZIRLIK
	sayac = 0.0
	vurdu = false
	enemy.velocity = Vector3.ZERO
	
	yon = _oyuncuya_yon()
	if yon == Vector3.ZERO:
		yon = -enemy.global_transform.basis.z
	_yuzunu_don()
	_anim_baslat()
	
	# Uyarı parlaması + sesi
	if debug:
		print("[SALDIRI] başladı: ", secili["anim"], " | player=", player)
	if enemy.has_method("telegraph_baslat"):
		enemy.telegraph_baslat(secili["hazirlik"])

func exit() -> void:
	enemy.velocity = Vector3.ZERO
	# Saldırı bitse de bölünse de (sersemleme) bir sonraki saldırı için bekleme başlar
	enemy.saldiri_bekleme = randf_range(bekleme_min, bekleme_max)
	# Saldırı hakkını geri ver, sıradaki düşman saldırabilsin
	SavasYoneticisi.slot_birak(enemy)

func physics_update(delta: float) -> void:
	sayac += delta
	match evre:
		Evre.HAZIRLIK:
			_hazirlik()
		Evre.VURUS:
			_vurus()
		Evre.TOPARLANMA:
			_toparlanma()

# ------------------------------------------------------------
# 1) HAZIRLIK: uyarı, oyuncuyu kısa süre takip et, sonra yönü kilitle
# ------------------------------------------------------------
func _hazirlik() -> void:
	if sayac < secili["hazirlik"] * yon_kilit_orani:
		var yeni_yon: Vector3 = _oyuncuya_yon()
		if yeni_yon != Vector3.ZERO:
			yon = yeni_yon
		_yuzunu_don()
	
	if sayac >= secili["hazirlik"]:
		evre = Evre.VURUS
		sayac = 0.0

# ------------------------------------------------------------
# 2) VURUŞ: kilitli yönde öne atıl, hasar penceresi açık
# ------------------------------------------------------------
func _vurus() -> void:
	var atilma: float = secili["atilma"]
	# Oyuncuya çok yaklaştıysa atılmayı durdur
	if _oyuncu_mesafesi() <= min_yaklasma:
		atilma = 0.0
	
	enemy.velocity = yon * atilma
	enemy.move_and_slide()
	
	if not vurdu:
		_vurus_kontrol()
	
	if sayac >= secili["vurus"]:
		enemy.velocity = Vector3.ZERO
		evre = Evre.TOPARLANMA
		sayac = 0.0

# ------------------------------------------------------------
# 3) TOPARLANMA: düşman açıkta, oyuncu karşı saldırı yapabilir
# ------------------------------------------------------------
func _toparlanma() -> void:
	enemy.velocity = Vector3.ZERO
	if sayac >= secili["toparlanma"]:
		# Kombo: oyuncu hâlâ yakındaysa arka arkaya ikinci bir hızlı saldırı
		if kombo_hakki > 0 and randf() < kombo_sansi and _oyuncu_mesafesi() <= kombo_menzili:
			kombo_hakki -= 1
			if debug:
				print("[SALDIRI] KOMBO!")
			_saldiri_baslat(true)
			return
		# Saldırıdan sonra oyuncunun etrafında dolaşmaya geç (yoksa kovalamaya)
		var sonraki = state_machine.get_node_or_null("CircleState")
		if sonraki == null:
			sonraki = state_machine.get_node_or_null("ChaseState")
		if sonraki == null:
			sonraki = state_machine.get_node_or_null("IdleState")
		state_machine.transition_to(sonraki)

# ------------------------------------------------------------
# HASAR KONTROLÜ (menzil + açı)
# ------------------------------------------------------------
func _vurus_kontrol() -> void:
	if player == null or not is_instance_valid(player):
		if debug:
			print("[SALDIRI] vuruş anında player yok (null)")
		return
	
	var fark: Vector3 = player.global_position - enemy.global_position
	fark.y = 0.0
	var mesafe: float = fark.length()
	if mesafe > vurus_menzili:
		if debug:
			print("[SALDIRI] menzil dışı: mesafe=", snappedf(mesafe, 0.01), " > ", vurus_menzili)
		return
	
	# Oyuncu düşmanın önündeki açının içinde mi?
	if mesafe > 0.01:
		var aci: float = rad_to_deg(yon.angle_to(fark / mesafe))
		if aci > vurus_acisi * 0.5:
			if debug:
				print("[SALDIRI] açı dışı: aci=", snappedf(aci, 0.1), " > ", vurus_acisi * 0.5)
			return
	
	vurdu = true
	
	# Vuruş önden mi geliyor? (parry ve blok sadece önden çalışır)
	var onden: bool = (not player.has_method("onden_mi")) or player.onden_mi(enemy)
	if debug:
		print("[SALDIRI] vuruş geldi | parry_aktif=", player.get("parry_aktif"), " blok_aktif=", player.get("blok_aktif"), " dokunulmaz=", player.get("dokunulmaz"), " onden=", onden)
	
	# Oyuncu parry penceresindeyse: hasar yok, düşman sersemler
	if player.get("parry_aktif") == true and onden:
		if debug:
			print("[SALDIRI] PARRY EDİLDİ!")
		# Tam zamanında parry ise oyuncu finisher sahnesini başlatır (true döner)
		var finisher: bool = false
		if player.has_method("parry_basarili"):
			finisher = player.parry_basarili(enemy, secili["hasar"]) == true
		if enemy.has_method("parry_edildi"):
			enemy.parry_edildi(not finisher)   # finisher'da geri itme yok, düşman yakında kalır
		return
	
	# Dodge: dokunulmazlık penceresinde hasar yok
	if player.get("dokunulmaz") == true:
		print("[SALDIRI] KAÇINILDI (dokunulmazlık)")
		return
	
	# Blok: önden gelen vuruşun hasarı azalır
	var hasar: int = secili["hasar"]
	var blokta: bool = player.get("blok_aktif") == true and onden
	if blokta:
		var carpan = player.get("blok_hasar_carpani")
		if carpan == null:
			carpan = 0.3
		hasar = int(hasar * float(carpan))
		print("[SALDIRI] 🛡️ BLOKLANDI: ", secili["hasar"], " -> ", hasar)
		if player.has_method("ekran_salla"):
			player.ekran_salla(0.08)
		if hasar <= 0:
			return
	
	var hedef: Node = _hasar_hedefi()
	if hedef:
		if debug:
			print("[SALDIRI] HASAR VERİLİYOR: ", hasar, " -> ", hedef.get_path())
		# Oyuncunun take_damage'indeki blok kodu hasarı ikinci kez azaltmasın
		if blokta:
			player.set("blok_aktif", false)
		hedef.take_damage(hasar)
		if blokta and is_instance_valid(player):
			player.set("blok_aktif", true)
	else:
		var isimler: Array = []
		for cocuk in player.find_children("*", "", true, false):
			isimler.append(cocuk.name)
		print("[SALDIRI] HATA: take_damage'i olan düğüm bulunamadı. Oyuncunun alt düğümleri: ", isimler)

# ------------------------------------------------------------
# YARDIMCILAR
# ------------------------------------------------------------
# take_damage fonksiyonu oyuncunun kendisinde ya da altındaki Hurtbox düğümünde olabilir
func _hasar_hedefi() -> Node:
	if player.has_method("take_damage"):
		return player
	var altlar: Array = player.find_children("*", "", true, false)
	for cocuk in altlar:
		if cocuk.name.to_lower() == "hurtbox" and cocuk.has_method("take_damage"):
			return cocuk
	# Adı farklıysa take_damage'i olan herhangi bir alt düğümü kullan
	for cocuk in altlar:
		if cocuk.has_method("take_damage"):
			return cocuk
	return null

func _oyuncuya_yon() -> Vector3:
	if player == null or not is_instance_valid(player):
		return Vector3.ZERO
	var fark: Vector3 = player.global_position - enemy.global_position
	fark.y = 0.0
	if fark.length() < 0.01:
		return Vector3.ZERO
	return fark.normalized()

func _oyuncu_mesafesi() -> float:
	if player == null or not is_instance_valid(player):
		return INF
	var fark: Vector3 = player.global_position - enemy.global_position
	fark.y = 0.0
	return fark.length()

func _yuzunu_don() -> void:
	if yon != Vector3.ZERO:
		enemy.look_at(enemy.global_position + yon, Vector3.UP)

func _anim_baslat() -> void:
	if anim == null:
		anim = enemy.find_child("AnimationPlayer", true, false)
	if anim == null or not anim.has_animation(secili["anim"]):
		return
	# Animasyonu saldırının toplam süresine sığdır (vuruş anı ile animasyon uyuşsun)
	var toplam: float = secili["hazirlik"] + secili["vurus"] + secili["toparlanma"]
	var uzunluk: float = anim.get_animation(secili["anim"]).length
	anim.stop()
	anim.play(secili["anim"], -1.0, uzunluk / toplam)
