extends AIState

# ============================================================
# SAVAŞ BEKLEME DURUŞU (ÇEMBER)
# Saldırı hakkı olmayan düşman oyuncuya dönük durur, çoğunlukla yerinde bekler,
# ara sıra kısa bir yan adım atar. ASLA geri çekilmez, sadece uzaktaysa yaklaşır.
# Hak (token) boşalınca ve bekleme süresi bitince ChaseState'e geçip saldırır.
# ============================================================

@export var yan_adim_hizi: float = 1.6
@export var yaklasma_hizi: float = 3.0
# Düşman oyuncudan bu aralıkta durur. Bundan uzaktaysa yaklaşır, yakındaysa yerinde kalır.
@export var halka_min: float = 2.8
@export var halka_max: float = 4.0
@export var tolerans: float = 0.5
# Diğer düşmanlardan hafifçe ayrılma (üst üste binmesinler)
@export var ayrilma_yaricapi: float = 1.5
@export var ayrilma_gucu: float = 1.2
# Yerinde bekleme ve yan adım süreleri (saniye). Bekleme uzun, yan adım kısa: az hareket.
@export var bekleme_min: float = 1.5
@export var bekleme_max: float = 3.5
@export var yan_adim_min: float = 0.5
@export var yan_adim_max: float = 0.9
# Saldırı hakkını kaç saniyede bir kontrol eder
@export var slot_deneme_araligi: float = 0.35
# Bu mesafeden uzaktaysa saldırı hakkı istemez
@export var token_mesafesi: float = 6.0
# Oyuncu bu mesafeden fazla uzaklaşırsa ChaseState'e dönüp koşarak yetişir
@export var cikis_mesafesi: float = 7.0
# Oyuncu bu kadar yakına gelirse hak olmasa bile kendini savunur (saldırır)
@export var savunma_mesafesi: float = 1.6
@export var yurume_animasyonu: String = "Walk"
@export var bekleme_animasyonu: String = "Sword_Idle"

var anim: AnimationPlayer
var halka: float = 3.4
var yan_yon: float = 1.0
var yan_adimda: bool = false
var faz_sayaci: float = 0.0
var slot_sayaci: float = 0.0

func enter() -> void:
	SavasYoneticisi.slot_birak(enemy)
	halka = randf_range(halka_min, halka_max)
	yan_yon = 1.0 if randf() < 0.5 else -1.0
	yan_adimda = false
	faz_sayaci = randf_range(bekleme_min, bekleme_max)
	slot_sayaci = randf_range(0.0, slot_deneme_araligi)
	enemy.velocity = Vector3.ZERO

func physics_update(delta: float) -> void:
	if not player or not is_instance_valid(player):
		state_machine.transition_to($"../IdleState")
		return
	
	# Geri savrulurken hareketi enemy scripti yönetiyor
	if enemy.knockback_velocity.length() > 0.1:
		return
	
	var fark: Vector3 = player.global_position - enemy.global_position
	fark.y = 0.0
	var mesafe: float = fark.length()
	var dir: Vector3 = fark / mesafe if mesafe > 0.01 else Vector3.ZERO
	
	# Çok uzaklaştıysa koşarak yetiş
	if mesafe > cikis_mesafesi:
		var kovala = state_machine.get_node_or_null("ChaseState")
		if kovala:
			state_machine.transition_to(kovala)
			return
	
	# Oyuncu iyice yaklaştıysa kendini savun
	if mesafe <= savunma_mesafesi and enemy.saldiri_bekleme <= 0.0:
		var saldiri = state_machine.get_node_or_null("AttackState")
		if saldiri:
			state_machine.transition_to(saldiri)
			return
	
	if dir == Vector3.ZERO:
		return
	
	# Her zaman oyuncuya bak
	enemy.look_at(enemy.global_position + dir, Vector3.UP)
	
	var hiz: Vector3 = Vector3.ZERO
	if mesafe > halka + tolerans:
		# Uzakta: yaklaş (geri çekilme yok)
		hiz = dir * (yaklasma_hizi * enemy.hiz_carpani)
		yan_adimda = false
	else:
		# Yakında: çoğunlukla yerinde dur, ara sıra kısa yan adım at
		faz_sayaci -= delta
		if faz_sayaci <= 0.0:
			if yan_adimda:
				yan_adimda = false
				faz_sayaci = randf_range(bekleme_min, bekleme_max)
			else:
				yan_adimda = true
				yan_yon = -yan_yon
				faz_sayaci = randf_range(yan_adim_min, yan_adim_max)
		if yan_adimda:
			hiz = dir.cross(Vector3.UP) * yan_yon * (yan_adim_hizi * enemy.hiz_carpani)
	
	hiz += SavasYoneticisi.ayrilma(enemy, ayrilma_yaricapi) * ayrilma_gucu
	hiz.y = 0.0
	if hiz.length() > (yaklasma_hizi * enemy.hiz_carpani):
		hiz = hiz.normalized() * (yaklasma_hizi * enemy.hiz_carpani)
	enemy.velocity.x = hiz.x
	enemy.velocity.z = hiz.z
	enemy.move_and_slide()
	
	# Hareket ediyorsa yürüme, duruyorsa bekleme animasyonu
	if hiz.length() > 0.5:
		_anim_oynat(yurume_animasyonu)
	else:
		_anim_oynat(bekleme_animasyonu)
	
	# Saldırı hakkı iste: hak alırsan ChaseState'e geçip saldırıya yaklaşırsın
	slot_sayaci -= delta
	if slot_sayaci <= 0.0:
		slot_sayaci = slot_deneme_araligi
		if enemy.saldiri_bekleme <= 0.0 and mesafe <= token_mesafesi and SavasYoneticisi.slot_iste(enemy):
			var kovala2 = state_machine.get_node_or_null("ChaseState")
			if kovala2:
				state_machine.transition_to(kovala2)

func _anim_oynat(isim: String) -> void:
	if anim == null:
		anim = enemy.find_child("AnimationPlayer", true, false)
	if anim == null or not anim.has_animation(isim):
		return
	if anim.current_animation != isim or not anim.is_playing():
		anim.play(isim)
