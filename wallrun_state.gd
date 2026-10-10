extends State

const ParkurYardimci = preload("res://parkur_yardimci.gd")

# ============================================================
# DUVARDA KOŞMA (WALL RUN)
# ============================================================

enum Faz { YAN, YUKARI, HAVA }

@export var debug: bool = true

# Algılama
@export var min_hiz: float = 4.5
@export var duvar_mesafesi: float = 0.9
@export var yukari_kosu_aktif: bool = true
@export var yukari_esigi: float = 0.8
@export var maks_art_arda_duvar: int = 2

# Yan koşu
@export var yan_hiz: float = 8.0
@export var yan_maks_sure: float = 1.6
@export var yukselme_baslangic: float = 2.2
@export var istenen_mesafe: float = 0.45

# Yukarı koşu
@export var yukari_hiz: float = 6.5
@export var yukari_sure: float = 0.55

# Duvardan zıplama ve hava
@export var duvar_ziplama_yatay: float = 5.5
@export var duvar_ziplama_dikey: float = 5.5
@export var hava_hizi: float = 7.0
@export var hava_kontrol: float = 2.0
@export var hava_max_sure: float = 1.4

# Görünüm
@export var egim_acisi: float = 14.0
@export var egim_yonu: float = -1.0
@export var birakma_bekleme: float = 0.35
@export var model_ileri_z: bool = true
@export var yedek_duvar_kosu: String = "Sprint"
@export var yedek_hava: String = "Jump"

var oyuncu = null
var anim: AnimationPlayer
var veri: Dictionary = {}
var faz: int = Faz.YAN
var mod: String = "yan"
var n: Vector3 = Vector3.RIGHT
var t: Vector3 = Vector3.FORWARD
var taraf: float = 1.0
var sayac: float = 0.0
var hava_sayac: float = 0.0
var yatay_hiz: float = 8.0
var girdi_yok: float = 0.0
var kullanilan: int = 0
var son_bitis_ms: int = 0
var son_duvar_n: Vector3 = Vector3.ZERO

func duvar_tara(yon_istek: Vector3, yerde: bool) -> Dictionary:
	oyuncu = state_machine.get_parent()
	
	if oyuncu.is_on_floor() or Time.get_ticks_msec() - son_bitis_ms > 1500:
		kullanilan = 0
	if kullanilan >= maks_art_arda_duvar:
		return {}
	
	var yon_h: Vector3 = Vector3(yon_istek.x, 0.0, yon_istek.z).normalized()
	if yon_h == Vector3.ZERO:
		return {}
	var hiz: float = Vector2(oyuncu.velocity.x, oyuncu.velocity.z).length()
	if hiz < min_hiz:
		return {}
	
	var ayak: Vector3 = oyuncu.global_position
	var gogus: Vector3 = ayak + Vector3.UP * 1.0
	
	var en_iyi: Dictionary = {}
	var en_yakin: float = 999.0
	for aci in [-80.0, -45.0, 0.0, 45.0, 80.0]:
		var d: Vector3 = yon_h.rotated(Vector3.UP, deg_to_rad(aci))
		var r: Dictionary = ParkurYardimci.isin(oyuncu, gogus, gogus + d * duvar_mesafesi)
		if r.is_empty():
			continue
		if absf(r["normal"].y) > 0.25:
			continue
		var m: float = gogus.distance_to(r["position"])
		if m < en_yakin:
			en_yakin = m
			en_iyi = r
	if en_iyi.is_empty():
		return {}
	
	var nn: Vector3 = Vector3(en_iyi["normal"].x, 0.0, en_iyi["normal"].z).normalized()
	
	for h in [0.3, 1.0, 1.7]:
		var bas: Vector3 = ayak + Vector3.UP * h
		if ParkurYardimci.isin(oyuncu, bas + nn * 0.2, bas - nn * 1.0).is_empty():
			return {}
	
	var dik: float = yon_h.dot(-nn)
	var secilen_mod: String = ""
	if dik >= yukari_esigi:
		if not yukari_kosu_aktif:
			return {}
		secilen_mod = "yukari"
	elif dik >= -0.1:
		secilen_mod = "yan"
	else:
		return {}
	
	var teget: Vector3 = yon_h - nn * yon_h.dot(nn)
	if teget.length() < 0.2:
		teget = nn.cross(Vector3.UP)
	teget = teget.normalized()
	if teget.dot(yon_h) < 0.0:
		teget = -teget
	var sag: Vector3 = teget.cross(Vector3.UP)
	var duvar_tarafi: float = 1.0 if (-nn).dot(sag) > 0.0 else -1.0
	
	if debug:
		print("[DUVAR] ", secilen_mod.to_upper(), " bulundu | dik=", snappedf(dik, 0.01), " | hız=", snappedf(hiz, 0.1), " | yerde=", yerde)
	
	return {
		"tip": "duvar",
		"mod": secilen_mod,
		"n": nn,
		"t": teget,
		"taraf": duvar_tarafi,
		"hiz": hiz,
	}

func hazirla(plan: Dictionary) -> void:
	veri = plan

func enter() -> void:
	oyuncu = state_machine.get_parent()
	anim = oyuncu.anim
	
	oyuncu.dodge_aktif = true
	oyuncu.set_meta("attack_pressed", false)
	if oyuncu.hitbox:
		oyuncu.hitbox.monitoring = false
	
	if veri.get("tip", "") == "hava":
		_havaya_gec(veri["hiz"], veri.get("son_duvar_n", Vector3.ZERO))
	else:
		_baslat(veri)

func _baslat(plan: Dictionary) -> void:
	mod = plan["mod"]
	n = plan["n"]
	t = plan["t"]
	taraf = plan["taraf"]
	kullanilan += 1
	sayac = 0.0
	girdi_yok = 0.0
	yatay_hiz = maxf(plan["hiz"], yan_hiz * 0.9)
	
	if mod == "yukari":
		faz = Faz.YUKARI
		oyuncu.velocity = Vector3.UP * yukari_hiz
		ParkurYardimci.mesh_don(oyuncu, -n, model_ileri_z)
	else:
		faz = Faz.YAN
		oyuncu.velocity = t * yatay_hiz + Vector3.UP * yukselme_baslangic
		ParkurYardimci.mesh_don(oyuncu, t, model_ileri_z)
	ParkurYardimci.anim_oynat(anim, ["wall run", "wallrun", "wall_run"], yedek_duvar_kosu, 1.1, true)
	if debug:
		print("[DUVAR] koşu başladı: ", mod)

func exit() -> void:
	if oyuncu:
		oyuncu.dodge_aktif = false
		oyuncu.parkur_bekleme = birakma_bekleme
		oyuncu.havada_idi = false
		oyuncu.dusus_baslangic_y = oyuncu.global_position.y
		oyuncu.mesh.rotation.z = 0.0
	son_bitis_ms = Time.get_ticks_msec()
	veri = {}
	if anim and not anim.is_playing():
		anim.stop()

func physics_update(delta: float) -> void:
	if oyuncu == null:
		return
	match faz:
		Faz.YAN:
			_yan(delta)
		Faz.YUKARI:
			_yukari(delta)
		Faz.HAVA:
			_hava(delta)

func _yan(delta: float) -> void:
	sayac += delta
	var gogus: Vector3 = oyuncu.global_position + Vector3.UP * 1.0
	
	var r: Dictionary = ParkurYardimci.isin(oyuncu, gogus, gogus - n * (duvar_mesafesi + 0.3))
	if r.is_empty() or absf(r["normal"].y) > 0.3:
		_havaya_cik()
		return
	n = Vector3(r["normal"].x, 0.0, r["normal"].z).normalized()
	var yeni_t: Vector3 = n.cross(Vector3.UP).normalized()
	if yeni_t.dot(t) < 0.0:
		yeni_t = -yeni_t
	t = yeni_t
	
	var mesafe: float = (gogus - r["position"]).dot(n)
	var duzelt: float = (istenen_mesafe - mesafe) * 10.0
	var ilerleme: float = clampf(sayac / yan_maks_sure, 0.0, 1.0)
	var hiz: float = lerpf(yatay_hiz, yatay_hiz * 0.65, ilerleme)
	var dikey: float = lerpf(yukselme_baslangic, -0.8, clampf(ilerleme * 1.3, 0.0, 1.0))
	oyuncu.velocity = t * hiz + n * duzelt + Vector3.UP * dikey
	oyuncu.move_and_slide()
	_egim_uygula(delta)
	ParkurYardimci.mesh_don(oyuncu, t, model_ileri_z)
	
	if not ParkurYardimci.isin(oyuncu, gogus, gogus + t * 0.7).is_empty():
		_havaya_cik()
		return
	if sayac >= yan_maks_sure:
		_havaya_cik()
		return
	if sayac > 0.25 and oyuncu.is_on_floor():
		_bitir()
		return
	
	var g: Vector3 = ParkurYardimci.girdi_yonu(oyuncu)
	if g.dot(t) < 0.2:
		girdi_yok += delta
	else:
		girdi_yok = 0.0
	if girdi_yok > 0.25:
		_havaya_cik()
		return
	if sayac > 0.15 and ParkurYardimci.zipla_basildi():
		_duvar_ziplamasi()
		return
	if sayac > 0.15 and ParkurYardimci.egil_basildi():
		_havaya_cik()

func _yukari(delta: float) -> void:
	sayac += delta
	var gogus: Vector3 = oyuncu.global_position + Vector3.UP * 1.0
	var r: Dictionary = ParkurYardimci.isin(oyuncu, gogus, gogus - n * (duvar_mesafesi + 0.3))
	var duzelt: float = 0.0
	if not r.is_empty() and absf(r["normal"].y) <= 0.3:
		n = Vector3(r["normal"].x, 0.0, r["normal"].z).normalized()
		duzelt = (istenen_mesafe - (gogus - r["position"]).dot(n)) * 10.0
	elif sayac > 0.1:
		_arka_takla()
		return
	oyuncu.velocity = Vector3.UP * yukari_hiz + n * duzelt
	oyuncu.move_and_slide()
	ParkurYardimci.mesh_don(oyuncu, -n, model_ileri_z)
	
	if sayac > 0.25:
		var ps = state_machine.get_node_or_null("ParkourState")
		if ps:
			var plan: Dictionary = ps.engel_tara(-n, false)
			if not plan.is_empty():
				ps.hazirla(plan)
				state_machine.transition_to(ps)
				return
	
	if sayac > 0.15 and ParkurYardimci.zipla_basildi():
		_duvar_ziplamasi()
		return
	if sayac >= yukari_sure:
		_arka_takla()

func _arka_takla() -> void:
	if debug:
		print("[DUVAR] arka takla")
	_havaya_gec(n * 4.0 + Vector3.UP * 3.0, n)

func _duvar_ziplamasi() -> void:
	var g: Vector3 = ParkurYardimci.girdi_yonu(oyuncu)
	var v: Vector3 = n * duvar_ziplama_yatay
	if mod == "yan":
		v += t * (yatay_hiz * 0.6)
	elif g != Vector3.ZERO:
		v += g * 2.0
	v += Vector3.UP * duvar_ziplama_dikey
	if debug:
		print("[DUVAR] duvardan zıpladı")
	_havaya_gec(v, n)

func _havaya_cik() -> void:
	_havaya_gec(oyuncu.velocity + n * 1.0, n)

func _havaya_gec(hiz: Vector3, duvar_normali: Vector3) -> void:
	faz = Faz.HAVA
	hava_sayac = 0.0
	son_duvar_n = duvar_normali
	oyuncu.velocity = hiz
	oyuncu.mesh.rotation.z = 0.0
	ParkurYardimci.mesh_don(oyuncu, hiz, model_ileri_z)
	ParkurYardimci.anim_oynat(anim, [], yedek_hava, 1.0, true)

func _hava(delta: float) -> void:
	hava_sayac += delta
	var g: Vector3 = ParkurYardimci.girdi_yonu(oyuncu)
	if g != Vector3.ZERO:
		var hedef: Vector3 = g * hava_hizi
		var k: float = clampf(hava_kontrol * delta, 0.0, 1.0)
		oyuncu.velocity.x = lerpf(oyuncu.velocity.x, hedef.x, k)
		oyuncu.velocity.z = lerpf(oyuncu.velocity.z, hedef.z, k)
	oyuncu.move_and_slide()
	var yatay: Vector3 = Vector3(oyuncu.velocity.x, 0.0, oyuncu.velocity.z)
	if yatay.length() > 1.0:
		ParkurYardimci.mesh_don(oyuncu, yatay, model_ileri_z)
	
	if hava_sayac > 0.1 and oyuncu.is_on_floor():
		_bitir()
		return
	
	if hava_sayac > 0.15 and g != Vector3.ZERO:
		var ps = state_machine.get_node_or_null("ParkourState")
		if ps:
			var plan: Dictionary = ps.engel_tara(g, false)
			if not plan.is_empty():
				ps.hazirla(plan)
				state_machine.transition_to(ps)
				return
		var wp: Dictionary = duvar_tara(g, false)
		if not wp.is_empty():
			var ayni_duvar: bool = son_duvar_n != Vector3.ZERO and wp["n"].dot(son_duvar_n) > 0.8
			if not ayni_duvar or hava_sayac > 0.7:
				_baslat(wp)
				return
	
	if hava_sayac >= hava_max_sure:
		_bitir()

func _egim_uygula(delta: float) -> void:
	var hedef: float = taraf * egim_yonu * deg_to_rad(egim_acisi)
	oyuncu.mesh.rotation.z = lerpf(oyuncu.mesh.rotation.z, hedef, clampf(10.0 * delta, 0.0, 1.0))

func _bitir() -> void:
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() > 0.1:
		state_machine.transition_to($"../RunState")
	else:
		state_machine.transition_to($"../IdleState")
