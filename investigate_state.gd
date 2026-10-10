extends AIState

# ============================================================
# ARAŞTIRMA / ARAMA
# Düşman son duyulan/görülen konuma yürür, orada etrafına bakar, bulamazsa eski işine döner.
# arama_modu = true: oyuncuyu savaşta kaybetti, daha hızlı gider ve daha uzun arar.
# Yolda oyuncuyu fark ederse (farkındalık 1.0) enemy.gd onu savaşa geçirir.
# ============================================================

enum Evre { GIT, BAK }

@export var yurume_hizi: float = 2.4
@export var arama_hizi: float = 4.0                # arama modunda (savaşı kaybedince) hızı
@export var varis_mesafesi: float = 1.3
@export var bakinma_suresi: float = 3.0            # vardığında etrafa bakma süresi
@export var arama_bakinma_suresi: float = 5.0      # arama modunda bakma süresi
@export var bakinma_acisi: float = 70.0            # sağa/sola bakma açısı (derece)
@export var donus_hizi: float = 6.0
# Bu kadar saniye ilerleyemezse (duvar vb.) varmış sayıp etrafa bakar
@export var takilma_suresi: float = 1.5
@export var yurume_animasyonu: String = "Walk"
@export var kosma_animasyonu: String = "Jog_Fwd"
@export var bekleme_animasyonu: String = "Sword_Idle"

# enemy.gd geçişten ÖNCE ayarlar
var arama_modu: bool = false

var evre: Evre = Evre.GIT
var sayac: float = 0.0
var hedef_poz: Vector3 = Vector3.ZERO
var taban_yaw: float = 0.0
var onceki_mesafe: float = INF
var takilma_olcum: float = 0.0
var takilma_toplam: float = 0.0
var anim: AnimationPlayer

func enter() -> void:
	evre = Evre.GIT
	sayac = 0.0
	hedef_poz = enemy.son_uyaran_poz
	onceki_mesafe = INF
	takilma_olcum = 0.0
	takilma_toplam = 0.0
	enemy.velocity = Vector3.ZERO

func exit() -> void:
	arama_modu = false
	enemy.velocity = Vector3.ZERO

func physics_update(delta: float) -> void:
	# Fark etti (başka bir yoldan savaşa geçtiyse) kovalamaya geç
	if enemy.farkinda:
		var kovala = state_machine.get_node_or_null("ChaseState")
		if kovala:
			state_machine.transition_to(kovala)
		return
	
	# Yeni bir ses/görüntü başka yerden geldiyse oraya git
	if enemy.son_uyaran_poz.distance_to(hedef_poz) > 3.0:
		hedef_poz = enemy.son_uyaran_poz
		evre = Evre.GIT
		sayac = 0.0
		onceki_mesafe = INF
		takilma_toplam = 0.0
	
	match evre:
		Evre.GIT:
			_git(delta)
		Evre.BAK:
			_bak(delta)

# ------------------------------------------------------------
# 1) Konuma yürü
# ------------------------------------------------------------
func _git(delta: float) -> void:
	var fark: Vector3 = hedef_poz - enemy.global_position
	fark.y = 0.0
	var mesafe: float = fark.length()
	if mesafe <= varis_mesafesi:
		_bakmaya_gec()
		return
	
	var dir: Vector3 = fark / mesafe
	var hiz: float = (arama_hizi if arama_modu else yurume_hizi) * enemy.hiz_carpani
	_yuzu_don(dir, delta)
	enemy.velocity.x = dir.x * hiz
	enemy.velocity.z = dir.z * hiz
	enemy.move_and_slide()
	_anim_oynat(kosma_animasyonu if arama_modu else yurume_animasyonu)
	
	# Takılma kontrolü: yarım saniyede neredeyse hiç ilerlemediyse engel var demektir
	takilma_olcum += delta
	if takilma_olcum >= 0.5:
		if onceki_mesafe - mesafe < 0.2:
			takilma_toplam += takilma_olcum
		else:
			takilma_toplam = 0.0
		onceki_mesafe = mesafe
		takilma_olcum = 0.0
		if takilma_toplam >= takilma_suresi:
			_bakmaya_gec()

func _bakmaya_gec() -> void:
	evre = Evre.BAK
	sayac = 0.0
	taban_yaw = enemy.rotation.y
	enemy.velocity = Vector3.ZERO

# ------------------------------------------------------------
# 2) Etrafa bak (sağa sola tarar), sonra pes et
# ------------------------------------------------------------
func _bak(delta: float) -> void:
	sayac += delta
	var sure: float = arama_bakinma_suresi if arama_modu else bakinma_suresi
	var yaw: float = taban_yaw + sin(sayac * 1.8) * deg_to_rad(bakinma_acisi)
	enemy.rotation.y = lerp_angle(enemy.rotation.y, yaw, clampf(donus_hizi * delta, 0.0, 1.0))
	_anim_oynat(bekleme_animasyonu)
	if sayac >= sure:
		enemy.pasife_don()

# ------------------------------------------------------------
# YARDIMCILAR
# ------------------------------------------------------------
func _yuzu_don(dir: Vector3, delta: float) -> void:
	var yaw: float = atan2(-dir.x, -dir.z)
	enemy.rotation.y = lerp_angle(enemy.rotation.y, yaw, clampf(donus_hizi * delta, 0.0, 1.0))

func _anim_oynat(isim: String) -> void:
	if anim == null:
		anim = enemy.find_child("AnimationPlayer", true, false)
	if anim == null or not anim.has_animation(isim):
		return
	if anim.current_animation != isim or not anim.is_playing():
		anim.play(isim, 0.2)
