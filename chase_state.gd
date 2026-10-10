extends AIState

@export var chase_speed: float = 4.0
# Saldırıya geçme mesafesi. Vuruş kutusunun erişebildiği mesafeden uzun olmamalı.
@export var attack_range: float = 2.5
# Düşman oyuncuya bu kadar yaklaşınca koşmayı bırakıp durur.
@export var durma_mesafesi: float = 1.8
# Oyuncu bundan daha yakına girerse düşman yavaşça geri çekilir.
@export var geri_cekilme_mesafesi: float = 0.9
# Saldırı hakkı (token) yoksa ya da bekleme süresi bitmediyse, düşman oyuncuya bu mesafeden
# fazla yaklaşmaz; CircleState'e geçip etrafında dolaşır.
@export var cember_giris_mesafesi: float = 5.0
@export var ayrilma_gucu: float = 1.5
@export var kosma_animasyonu: String = "Sprint"
# Menzilde saldırı beklerken oynayacak animasyon. Adı yanlışsa animasyon durdurulur.
@export var bekleme_animasyonu: String = "Idle"

var anim: AnimationPlayer

func enter() -> void:
	enemy.velocity = Vector3.ZERO
	_anim_oynat(kosma_animasyonu)

func physics_update(delta: float) -> void:
	if not player or not is_instance_valid(player):
		state_machine.transition_to($"../IdleState")
		return
	
	# Geri savrulurken hareketi enemy scripti yönetiyor, çift hareket olmasın.
	if enemy.knockback_velocity.length() > 0.1:
		return
	
	# Yatay mesafe ve yön (yükseklik farkı hesabı bozmasın)
	var fark: Vector3 = player.global_position - enemy.global_position
	fark.y = 0.0
	var mesafe: float = fark.length()
	var dir: Vector3 = fark / mesafe if mesafe > 0.01 else Vector3.ZERO
	
	# Saldırı hakkı yoksa (ya da bekleme sürüyorsa) yakına gelmeden etrafında dolaş
	var cember = state_machine.get_node_or_null("CircleState")
	var hakki_var: bool = SavasYoneticisi.sahip_mi(enemy)
	if cember and mesafe <= cember_giris_mesafesi and (not hakki_var or enemy.saldiri_bekleme > 0.0):
		state_machine.transition_to(cember)
		return
	
	# Her zaman oyuncuya bak
	if dir != Vector3.ZERO:
		enemy.look_at(enemy.global_position + dir, Vector3.UP)
	
	var hiz_vektoru: Vector3 = Vector3.ZERO
	if mesafe < geri_cekilme_mesafesi:
		# Çok yakın: yavaşça geri çekil
		hiz_vektoru = -dir * (chase_speed * enemy.hiz_carpani) * 0.6
		_anim_oynat(kosma_animasyonu)
	elif mesafe <= durma_mesafesi:
		# Yeterince yakın: dur ve bekle (yerinde koşma animasyonu oynamasın)
		_bekleme_animasyonu_oynat()
	else:
		# Uzakta: kovala (diğer düşmanlardan hafifçe ayrılarak)
		hiz_vektoru = dir * (chase_speed * enemy.hiz_carpani) + SavasYoneticisi.ayrilma(enemy) * ayrilma_gucu
		hiz_vektoru.y = 0.0
		if hiz_vektoru.length() > (chase_speed * enemy.hiz_carpani):
			hiz_vektoru = hiz_vektoru.normalized() * (chase_speed * enemy.hiz_carpani)
		_anim_oynat(kosma_animasyonu)
	
	enemy.velocity.x = hiz_vektoru.x
	enemy.velocity.z = hiz_vektoru.z
	enemy.move_and_slide()
	
	# Menzildeyse, bekleme süresi bittiyse ve saldırı hakkı varsa saldır
	# (CircleState yoksa hak aranmaz, eski davranış korunur)
	if mesafe <= attack_range and enemy.saldiri_bekleme <= 0.0 and (hakki_var or cember == null):
		state_machine.transition_to($"../AttackState")

func _anim_oynat(isim: String) -> void:
	if anim == null:
		anim = enemy.find_child("AnimationPlayer", true, false)
	if anim == null or not anim.has_animation(isim):
		return
	if anim.current_animation != isim or not anim.is_playing():
		anim.play(isim)

func _bekleme_animasyonu_oynat() -> void:
	if anim == null:
		anim = enemy.find_child("AnimationPlayer", true, false)
	if anim == null:
		return
	if anim.has_animation(bekleme_animasyonu):
		_anim_oynat(bekleme_animasyonu)
	else:
		anim.pause()
