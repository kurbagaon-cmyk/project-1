extends State

# ============================================================
# KAN EMME (ISIRMA)
# Sersemlemiş (parry edilmiş, kırmızı parlayan) düşmana yaklaşıp tuşa basınca:
#   - düşman yakalanır, kısa bir süre ısırılır
#   - düşman hasar alır (canı azsa ölür)
#   - oyuncu can yeniler ve kan barı dolar
# Isırma sırasında oyuncu savunmasızdır: diğer düşmanlar vurabilir.
# ============================================================

@export var isirma_suresi: float = 1.1        # toplam süre (gerçek saniye)
@export var vurus_noktasi: float = 0.55       # ısırmanın gerçekleştiği an
@export var isirma_hasari: int = 45           # düşmana verilen hasar
@export var can_yenileme: float = 25.0        # oyuncunun yenilediği can
@export var kan_kazanci: float = 35.0         # oyuncunun kazandığı kan
@export var gizli_can_yenileme: float = 15.0  # farkında olmayan düşmanı arkadan öldürünce yenilenen can
@export var gizli_kan_kazanci: float = 25.0   # ve kazanılan kan
@export var yaklasma_mesafesi: float = 1.0    # düşmana bu kadar yaklaşır
@export var yaklasma_hizi: float = 5.0
@export var yedek_animasyon: String = "Interact"
# Karakter modeli +Z yönüne mi bakıyor? (DodgeState'teki ayarla aynı olmalı)
@export var model_ileri_z: bool = true

var oyuncu = null
var dusman = null
var anim: AnimationPlayer
var baslangic_ms: int = 0
var vurdu: bool = false
var dondurulmus: bool = false
var gizli: bool = false   # true: farkında olmayan düşman arkadan sessizce öldürülür

# Oyuncu scripti geçişten ÖNCE çağırır
func hedef_ayarla(d, oldur: bool = false) -> void:
	dusman = d
	gizli = oldur

func enter() -> void:
	oyuncu = state_machine.get_parent()
	anim = oyuncu.anim
	
	if not is_instance_valid(dusman):
		state_machine.transition_to($"../IdleState")
		return
	
	baslangic_ms = Time.get_ticks_msec()
	vurdu = false
	
	# Isırma saldırıyı iptal eder, dodge/parry kapanır
	oyuncu.set_meta("attack_pressed", false)
	if oyuncu.hitbox:
		oyuncu.hitbox.monitoring = false
	oyuncu.dodge_aktif = true
	oyuncu.parry_durumda = true
	
	# Düşmanın sersemliğini devral: ısırma bitene kadar donuk kalır
	if dusman.has_method("sersemi_iptal"):
		dusman.sersemi_iptal()
	if dusman.has_method("dondur"):
		dusman.dondur()
		dondurulmus = true
	
	_dusmana_don()
	_anim_oynat()

func exit() -> void:
	if dondurulmus and is_instance_valid(dusman) and dusman.has_method("coz"):
		dusman.coz()
	dondurulmus = false
	if oyuncu:
		oyuncu.dodge_aktif = false
		oyuncu.parry_durumda = false
		oyuncu.set_meta("attack_pressed", false)

func physics_update(delta: float) -> void:
	if oyuncu == null:
		return
	var gecen: float = float(Time.get_ticks_msec() - baslangic_ms) / 1000.0
	
	# İlk anda düşmana yaklaş, sonra yerinde dur
	var hedef_hiz: Vector3 = Vector3.ZERO
	if is_instance_valid(dusman):
		var fark: Vector3 = dusman.global_position - oyuncu.global_position
		fark.y = 0.0
		if fark.length() > yaklasma_mesafesi and gecen < 0.4:
			hedef_hiz = fark.normalized() * yaklasma_hizi
	oyuncu.velocity.x = move_toward(oyuncu.velocity.x, hedef_hiz.x, 40.0 * delta)
	oyuncu.velocity.z = move_toward(oyuncu.velocity.z, hedef_hiz.z, 40.0 * delta)
	oyuncu.move_and_slide()
	
	if not vurdu and gecen >= vurus_noktasi:
		vurdu = true
		_isir()
	
	if gecen >= isirma_suresi:
		_bitir()

func _isir() -> void:
	print("🧛 KAN EMME!")
	var can: float = can_yenileme
	var kan: float = kan_kazanci
	if is_instance_valid(dusman):
		if gizli:
			# Sessiz öldürme: tek hamlede ölür, uyarı vermez, slow-motion yok
			dusman.set("sessiz_olum", true)
			dusman.take_damage(99999)
			can = gizli_can_yenileme
			kan = gizli_kan_kazanci
		else:
			# Ölürse ol() fonksiyonu ölüm animasyonunu yönetir, yaşarsa exit() düşmanı serbest bırakır
			dusman.take_damage(isirma_hasari)
	oyuncu.ekran_salla(0.15)
	if oyuncu.has_method("iyiles"):
		oyuncu.iyiles(can)
	if oyuncu.has_method("kan_kazan"):
		oyuncu.kan_kazan(kan)

func _bitir() -> void:
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir.length() > 0.1:
		state_machine.transition_to($"../RunState")
	else:
		state_machine.transition_to($"../IdleState")

func _dusmana_don() -> void:
	if not is_instance_valid(dusman):
		return
	var f: Vector3 = dusman.global_position - oyuncu.global_position
	f.y = 0.0
	if f.length() < 0.01:
		return
	f = f.normalized()
	var aci: float = atan2(f.x, f.z)
	if not model_ileri_z:
		aci += PI
	oyuncu.mesh.global_rotation.y = aci

# "bite", "feed" ya da "drain" geçen animasyonu bulur, yoksa yedeği kullanır
func _anim_bul() -> String:
	if anim == null:
		return ""
	for adi in anim.get_animation_list():
		var kucuk: String = String(adi).to_lower()
		if kucuk.contains("bite") or kucuk.contains("feed") or kucuk.contains("drain"):
			return String(adi)
	if anim.has_animation(yedek_animasyon):
		return yedek_animasyon
	return ""

func _anim_oynat() -> void:
	var adi: String = _anim_bul()
	if adi == "" or anim == null:
		return
	var uzunluk: float = anim.get_animation(adi).length
	anim.play(adi, 0.05, uzunluk / isirma_suresi)
