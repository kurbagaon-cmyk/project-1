extends State

const ParkurYardimci = preload("res://parkur_yardimci.gd")

# ============================================================
# KENARDA ASILMA (LEDGE HANG)
# ============================================================

enum Evre { ASILI, CEKILME }

@export var debug: bool = true
# ParkourState ile aynı olmalı:
@export var el_yuksekligi: float = 1.7
@export var duvar_aralik: float = 0.4
@export var mantle_ic_mesafe: float = 0.55
@export var bos_yukseklik: float = 1.9

@export var shimmy_hizi: float = 1.8
@export var otomatik_cekilme: bool = true
@export var otomatik_cekilme_gecikme: float = 0.18
@export var cekilme_sureleri: Array[float] = [0.45, 0.3]
@export var cikis_hizi: float = 2.0
@export var birakma_bekleme: float = 0.45
@export var geri_ziplama_hizi: float = 5.5
@export var geri_ziplama_yukseklik: float = 5.5
@export var model_ileri_z: bool = true
@export var yedek_asili: String = "Jump"
@export var yedek_cekilme: String = "Jump"

var oyuncu = null
var anim: AnimationPlayer
var veri: Dictionary = {}
var evre: Evre = Evre.ASILI
var ic: Vector3 = Vector3.FORWARD
var yan: Vector3 = Vector3.RIGHT
var konum: Vector3 = Vector3.ZERO
var y_ust: float = 0.0
var sayac: float = 0.0
var asili_sayac: float = 0.0
var yol: Array = []
var sureler: Array = []
var toplam_sure: float = 0.0
var cikis_bekleme: float = 0.25

func hazirla(plan: Dictionary) -> void:
	veri = plan

func enter() -> void:
	oyuncu = state_machine.get_parent()
	anim = oyuncu.anim
	if veri.is_empty():
		_cik()
		return
	
	ic = veri["yon"]
	y_ust = veri["y_ust"]
	var duvar: Vector3 = veri["duvar"]
	yan = ic.cross(Vector3.UP).normalized()
	konum = Vector3(duvar.x - ic.x * duvar_aralik, y_ust - el_yuksekligi, duvar.z - ic.z * duvar_aralik)
	
	evre = Evre.ASILI
	sayac = 0.0
	asili_sayac = 0.0
	cikis_bekleme = 0.25
	
	oyuncu.dodge_aktif = true
	oyuncu.set_meta("attack_pressed", false)
	if oyuncu.hitbox:
		oyuncu.hitbox.monitoring = false
	oyuncu.velocity = Vector3.ZERO
	oyuncu.global_position = konum
	ParkurYardimci.mesh_don(oyuncu, ic, model_ileri_z)
	_anim_asili(false)
	if debug:
		print("[KENAR] asıldı | kenar yüksekliği=", snappedf(y_ust, 0.01))

func exit() -> void:
	if oyuncu:
		oyuncu.dodge_aktif = false
		oyuncu.parkur_bekleme = cikis_bekleme
		oyuncu.havada_idi = false
		oyuncu.dusus_baslangic_y = oyuncu.global_position.y
	veri = {}
	if anim and not anim.is_playing():
		anim.stop()

func physics_update(delta: float) -> void:
	if oyuncu == null:
		return
	sayac += delta
	oyuncu.velocity = Vector3.ZERO
	match evre:
		Evre.ASILI:
			_asili(delta)
		Evre.CEKILME:
			_cekilme()

func _asili(delta: float) -> void:
	asili_sayac += delta
	var g: Vector3 = ParkurYardimci.girdi_yonu(oyuncu)
	var ileri_g: float = g.dot(ic)
	var yan_g: float = g.dot(yan)
	var zipla: bool = asili_sayac > 0.2 and ParkurYardimci.zipla_basildi()
	
	if zipla and ileri_g < -0.3:
		_geri_zipla()
		return
	if ileri_g < -0.6 or (asili_sayac > 0.2 and ParkurYardimci.egil_basildi()):
		_birak()
		return
	if zipla or (otomatik_cekilme and ileri_g > 0.5 and asili_sayac > otomatik_cekilme_gecikme):
		if _cekilme_baslat():
			return
	if absf(yan_g) > 0.3:
		_shimmy(delta, signf(yan_g))
		_anim_asili(true)
	else:
		_anim_asili(false)

func _shimmy(delta: float, isaret: float) -> void:
	var adim: Vector3 = yan * isaret * shimmy_hizi * delta
	var yeni: Vector3 = konum + adim
	
	var govde: Vector3 = konum + Vector3.UP * (el_yuksekligi * 0.6)
	if not ParkurYardimci.isin(oyuncu, govde, govde + yan * isaret * 0.45).is_empty():
		return
	
	var el: Vector3 = yeni + Vector3.UP * (el_yuksekligi - 0.15)
	var duvar: Dictionary = ParkurYardimci.isin(oyuncu, el - ic * 0.1, el + ic * 0.9)
	if duvar.is_empty():
		return
	var n: Vector3 = duvar["normal"]
	if absf(n.y) > 0.3:
		return
	var yeni_ic: Vector3 = Vector3(-n.x, 0.0, -n.z).normalized()
	
	var ust: Vector3 = duvar["position"] + yeni_ic * 0.3
	var asagi: Dictionary = ParkurYardimci.isin(
		oyuncu,
		Vector3(ust.x, y_ust + 0.45, ust.z),
		Vector3(ust.x, y_ust - 0.45, ust.z))
	if asagi.is_empty():
		return
	var ust_n: Vector3 = asagi["normal"]
	if ust_n.y < 0.7:
		return
	
	y_ust = asagi["position"].y
	ic = yeni_ic
	yan = ic.cross(Vector3.UP).normalized()
	konum = Vector3(
		duvar["position"].x - ic.x * duvar_aralik,
		y_ust - el_yuksekligi,
		duvar["position"].z - ic.z * duvar_aralik)
	oyuncu.global_position = konum
	ParkurYardimci.mesh_don(oyuncu, ic, model_ileri_z)

func _cekilme_baslat() -> bool:
	var duvar_xz: Vector3 = konum + ic * duvar_aralik
	var ust_poz: Vector3 = Vector3(
		duvar_xz.x + ic.x * mantle_ic_mesafe,
		y_ust,
		duvar_xz.z + ic.z * mantle_ic_mesafe)
	
	var yuzey: Dictionary = ParkurYardimci.isin(oyuncu, ust_poz + Vector3.UP * 0.3, ust_poz - Vector3.UP * 0.3)
	if yuzey.is_empty():
		if debug:
			print("[KENAR] çekilemiyor: üstünde basılacak yüzey yok")
		return false
	if not ParkurYardimci.isin(oyuncu, ust_poz + Vector3.UP * 0.1, ust_poz + Vector3.UP * bos_yukseklik).is_empty():
		if debug:
			print("[KENAR] çekilemiyor: üstünde tavan var")
		return false
	
	yol = [konum, Vector3(konum.x, y_ust, konum.z), ust_poz]
	sureler = cekilme_sureleri.duplicate()
	toplam_sure = 0.0
	for s in sureler:
		toplam_sure += s
	evre = Evre.CEKILME
	sayac = 0.0
	cikis_bekleme = 0.25
	ParkurYardimci.anim_oynat(
		anim, ["climb", "mantle", "pull up", "pullup", "hang to crouch"], yedek_cekilme,
		_anim_hizi(["climb", "mantle", "pull up", "pullup", "hang to crouch"], yedek_cekilme), true)
	if debug:
		print("[KENAR] çekiliyor")
	return true

func _cekilme() -> void:
	oyuncu.global_position = ParkurYardimci.yoldaki_konum(yol, sureler, sayac)
	if sayac >= toplam_sure:
		oyuncu.global_position = yol[yol.size() - 1]
		oyuncu.velocity = Vector3(ic.x, 0.0, ic.z) * cikis_hizi + Vector3.DOWN * 1.0
		_cik()

func _birak() -> void:
	oyuncu.velocity = -ic * 1.0 + Vector3.DOWN * 1.0
	cikis_bekleme = birakma_bekleme
	if debug:
		print("[KENAR] bıraktı")
	_cik()

func _geri_zipla() -> void:
	var v: Vector3 = Vector3(-ic.x, 0.0, -ic.z) * geri_ziplama_hizi + Vector3.UP * geri_ziplama_yukseklik
	cikis_bekleme = birakma_bekleme
	if debug:
		print("[KENAR] geri zıpladı")
	var wr = state_machine.get_node_or_null("WallRunState")
	if wr:
		wr.hazirla({"tip": "hava", "hiz": v, "son_duvar_n": -ic})
		state_machine.transition_to(wr)
	else:
		oyuncu.velocity = v
		_cik()

func _cik() -> void:
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() > 0.1:
		state_machine.transition_to($"../RunState")
	else:
		state_machine.transition_to($"../IdleState")

func _anim_asili(kayiyor: bool) -> void:
	if kayiyor:
		ParkurYardimci.anim_oynat(anim, ["shimmy", "hang move", "braced hang"], yedek_asili)
	else:
		ParkurYardimci.anim_oynat(anim, ["hanging idle", "hang idle", "braced hang idle", "ledge idle"], yedek_asili)

func _anim_hizi(anahtarlar: Array, yedek: String) -> float:
	var adi: String = ParkurYardimci.anim_bul(anim, anahtarlar, yedek)
	if adi == "" or toplam_sure <= 0.0:
		return 1.0
	return anim.get_animation(adi).length / toplam_sure
