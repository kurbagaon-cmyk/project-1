extends AIState

@export var attack_range: float = 2.5
@export var min_mesafe: float = 1.5
@export var max_mesafe: float = 5.0
@export var chase_speed: float = 4.5
@export var strafe_hizi: float = 2.5
@export var strafe_yonu: float = 1.0
@export var strafe_degistirme_suresi: float = 2.0
@export var devriye_hizi: float = 1.8
@export var noktaya_varis_mesafesi: float = 0.75
@export var noktada_bekleme_suresi: float = 1.0
@export var yedek_devriye_yaricapi: float = 3.0

var strafe_zamanlayici: float = 0.0
var anim: AnimationPlayer
var devriye_noktalari: Array[Vector3] = []
var devriye_sirasi: int = 0
var devriye_bekliyor: bool = false
var devriye_bekleme: float = 0.0
var onceki_yol_noktasi_mesafesi: float = -1.0

func enter() -> void:
	if anim == null:
		anim = enemy.find_child("AnimationPlayer", true, false)
	if nav_agent:
		onceki_yol_noktasi_mesafesi = nav_agent.path_desired_distance
		nav_agent.path_desired_distance = maxf(
			nav_agent.path_desired_distance,
			noktaya_varis_mesafesi
		)
	_rota_hazirla()
	devriye_sirasi = 0
	devriye_bekliyor = false
	devriye_bekleme = 0.0
	enemy.velocity = Vector3.ZERO
	strafe_zamanlayici = strafe_degistirme_suresi
	_anim_oynat("Sprint" if _oyuncu_var_mi() else "Walk")
	_hedefi_ayarla()

func exit() -> void:
	if nav_agent and onceki_yol_noktasi_mesafesi >= 0.0:
		nav_agent.path_desired_distance = onceki_yol_noktasi_mesafesi
		onceki_yol_noktasi_mesafesi = -1.0

func physics_update(delta: float) -> void:
	if not _oyuncu_var_mi():
		_devriye_yap(delta)
		return

	_anim_oynat("Sprint")
	
	var mesafe = enemy.global_position.distance_to(player.global_position)
	
	# Çok yakınsa geri çekil
	if mesafe < min_mesafe:
		var geri_yon = (enemy.global_position - player.global_position)
		geri_yon.y = 0
		geri_yon = geri_yon.normalized()
		enemy.velocity = geri_yon * strafe_hizi
		_face_direction(-geri_yon)
		enemy.move_and_slide()
		check_transitions()
		return
	
	# Menzildeyse dur ve saldır
	if mesafe <= attack_range:
		enemy.velocity = Vector3.ZERO
		check_transitions()
		return
	
	# Uzaktaysa yaklaş + strafe
	var ileri_yon = (player.global_position - enemy.global_position)
	ileri_yon.y = 0
	ileri_yon = ileri_yon.normalized()
	
	var yan_yon = Vector3(-ileri_yon.z, 0, ileri_yon.x) * strafe_yonu
	var hareket = (ileri_yon * 0.5 + yan_yon * 0.5).normalized()
	
	enemy.velocity = hareket * chase_speed
	_face_direction(ileri_yon)
	enemy.move_and_slide()
	
	strafe_zamanlayici -= delta
	if strafe_zamanlayici <= 0.0:
		strafe_yonu *= -1.0
		strafe_zamanlayici = strafe_degistirme_suresi
	
	check_transitions()

func _oyuncu_var_mi() -> bool:
	return player != null and is_instance_valid(player)

func _rota_hazirla() -> void:
	devriye_noktalari.clear()
	var waypoint_kok: Node3D = enemy.get_node_or_null("Waypoints") as Node3D
	if waypoint_kok:
		for dugum in waypoint_kok.get_children():
			if not dugum is Node3D:
				continue
			var nokta: Vector3 = (dugum as Node3D).global_position
			var spawn_farki: Vector3 = nokta - enemy.global_position
			spawn_farki.y = 0.0
			if spawn_farki.length() < 1.0:
				continue
			var tekrar: bool = false
			for mevcut in devriye_noktalari:
				var yatay_fark: Vector3 = nokta - mevcut
				yatay_fark.y = 0.0
				if yatay_fark.length() < 1.0:
					tekrar = true
					break
			if not tekrar:
				devriye_noktalari.append(nokta)

	# Test sahnesindeki varsayılan marker'lar aynı noktadaysa, düşman küçük
	# bir yerel rota kullanır; asıl haritada tanımlı waypoint'ler korunur.
	if devriye_noktalari.size() < 2:
		devriye_noktalari.clear()
		var yonler: Array[Vector3] = [
			Vector3.RIGHT,
			Vector3.BACK,
			Vector3.LEFT,
			Vector3.FORWARD
		]
		for yon in yonler:
			devriye_noktalari.append(enemy.global_position + yon * yedek_devriye_yaricapi)

func _hedefi_ayarla() -> void:
	if nav_agent and not devriye_noktalari.is_empty():
		nav_agent.target_position = devriye_noktalari[devriye_sirasi]

func _sonraki_noktaya_gec() -> void:
	devriye_sirasi = (devriye_sirasi + 1) % devriye_noktalari.size()
	_hedefi_ayarla()

func _devriye_yap(delta: float) -> void:
	if devriye_noktalari.is_empty():
		_rota_hazirla()
		_hedefi_ayarla()
	if devriye_noktalari.is_empty():
		return

	if devriye_bekliyor:
		enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, devriye_hizi)
		enemy.velocity.z = move_toward(enemy.velocity.z, 0.0, devriye_hizi)
		enemy.move_and_slide()
		devriye_bekleme -= delta
		if devriye_bekleme <= 0.0:
			devriye_bekliyor = false
			_sonraki_noktaya_gec()
		return

	var hedef: Vector3 = devriye_noktalari[devriye_sirasi]
	var hedef_farki: Vector3 = hedef - enemy.global_position
	hedef_farki.y = 0.0
	if hedef_farki.length() <= noktaya_varis_mesafesi:
		devriye_bekliyor = true
		devriye_bekleme = noktada_bekleme_suresi
		enemy.velocity.x = 0.0
		enemy.velocity.z = 0.0
		_anim_oynat("Idle")
		enemy.move_and_slide()
		return

	var hareket_hedefi: Vector3 = hedef
	if nav_agent:
		var yol_noktasi: Vector3 = nav_agent.get_next_path_position()
		var yol_farki: Vector3 = yol_noktasi - enemy.global_position
		yol_farki.y = 0.0
		if yol_farki.length() > 0.05:
			hareket_hedefi = yol_noktasi

	var hareket_yonu: Vector3 = hareket_hedefi - enemy.global_position
	hareket_yonu.y = 0.0
	if hareket_yonu.length() <= 0.05:
		hareket_yonu = hedef_farki
	if hareket_yonu.length() <= 0.05:
		return

	hareket_yonu = hareket_yonu.normalized()
	enemy.velocity.x = hareket_yonu.x * devriye_hizi
	enemy.velocity.z = hareket_yonu.z * devriye_hizi
	_face_direction(hareket_yonu)
	_anim_oynat("Walk" if anim and anim.has_animation("Walk") else "Sprint")
	enemy.move_and_slide()

func _anim_oynat(isim: String) -> void:
	if anim == null:
		anim = enemy.find_child("AnimationPlayer", true, false)
	if anim and anim.has_animation(isim):
		if anim.current_animation != isim or not anim.is_playing():
			anim.play(isim)

func check_transitions() -> void:
	if not player or not is_instance_valid(player):
		state_machine.transition_to($"../IdleState")
		return
	var mesafe = enemy.global_position.distance_to(player.global_position)
	if mesafe <= attack_range:
		state_machine.transition_to($"../AttackState")

func _face_direction(dir: Vector3) -> void:
	if dir.length() > 0.1:
		enemy.look_at(enemy.global_position + dir, Vector3.UP)
