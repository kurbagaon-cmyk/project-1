extends AIState

# ============================================================
# ŞÜPHELENDİ
# Düşman bir ses duydu ya da bir şey gördü: durur, sesin/görüntünün yönüne döner.
# Farkındalık yükselirse enemy.gd onu InvestigateState'e (araştırma) geçirir,
# düşerse ya da süre dolarsa eski işine (bekleme/devriye) döner.
# ============================================================

@export var donus_hizi: float = 5.0
# Bu süre içinde bir gelişme olmazsa sakinleşir
@export var en_fazla_sure: float = 6.0
@export var bekleme_animasyonu: String = "Sword_Idle"

var sayac: float = 0.0
var anim: AnimationPlayer

func enter() -> void:
	sayac = 0.0
	enemy.velocity = Vector3.ZERO
	_anim_oynat()

func physics_update(delta: float) -> void:
	sayac += delta
	
	# Fark etti (başka bir yoldan savaşa geçtiyse) kovalamaya geç
	if enemy.farkinda:
		var kovala = state_machine.get_node_or_null("ChaseState")
		if kovala:
			state_machine.transition_to(kovala)
		return
	
	# Sesin/görüntünün geldiği yöne doğru dön
	var f: Vector3 = enemy.son_uyaran_poz - enemy.global_position
	f.y = 0.0
	if f.length() > 0.3:
		f = f.normalized()
		var yaw: float = atan2(-f.x, -f.z)
		enemy.rotation.y = lerp_angle(enemy.rotation.y, yaw, clampf(donus_hizi * delta, 0.0, 1.0))
	
	# Farkındalık söndüyse ya da süre dolduysa sakinleş
	if enemy.farkindalik < 0.08 or sayac >= en_fazla_sure:
		enemy.pasife_don()

func _anim_oynat() -> void:
	if anim == null:
		anim = enemy.find_child("AnimationPlayer", true, false)
	if anim == null or not anim.has_animation(bekleme_animasyonu):
		return
	if anim.current_animation != bekleme_animasyonu or not anim.is_playing():
		anim.play(bekleme_animasyonu, 0.2)
