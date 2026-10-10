extends State

@export var saldiri_suresi: float = 0.8
@export var hitbox_acilis: float = 0.25
@export var hitbox_kapanis: float = 0.5
@export var hasar: int = 15

var gecen_sure: float = 0.0
var hitbox_acik: bool = false
var vurulan_hedefler: Array = []

func enter() -> void:
	var player = owner
	gecen_sure = 0.0
	hitbox_acik = false
	vurulan_hedefler.clear()
	
	if player.anim:
		player.anim.play("Sword_Attack", 0.12)
	
	if player.hitbox:
		player.hitbox.monitoring = false

func exit() -> void:
	var player = owner
	if player and player.hitbox:
		player.hitbox.monitoring = false

func physics_update(delta: float) -> void:
	var player = owner
	gecen_sure += delta
	
	# Hareketi yavaşlat
	player.velocity.x = move_toward(player.velocity.x, 0, 20 * delta)
	player.velocity.z = move_toward(player.velocity.z, 0, 20 * delta)
	player.move_and_slide()
	
	# Hitbox açılma/kapanma zamanı
	if gecen_sure >= hitbox_acilis and gecen_sure < hitbox_kapanis:
		if not hitbox_acik:
			hitbox_acik = true
			player.hitbox.monitoring = true
		_hasar_ver(player)
	elif gecen_sure >= hitbox_kapanis and hitbox_acik:
		hitbox_acik = false
		player.hitbox.monitoring = false
	
	# Süre bitti mi?
	if gecen_sure >= saldiri_suresi:
		var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if input_dir.length() > 0.1:
			state_machine.transition_to($"../RunState")
		else:
			state_machine.transition_to($"../IdleState")

func update(delta: float) -> void:
	pass

func _hasar_ver(player) -> void:
	if not player.hitbox:
		return
	
	# Body'ler
	for body in player.hitbox.get_overlapping_bodies():
		if body == player: continue
		if body in vurulan_hedefler: continue
		if body.has_method("take_damage"):
			player.hedefe_vur(body, hasar) 
			vurulan_hedefler.append(body)
			player.hit_pause()
			player.ekran_salla()
			_combo_artir(player)   # ← SADECE yeni hedef vurulunca
	
	# Area'lar
	for area in player.hitbox.get_overlapping_areas():
		var sahip = area.get_parent()
		if sahip == player: continue
		if sahip in vurulan_hedefler: continue
		if sahip and sahip.has_method("take_damage"):
			player.hedefe_vur(sahip, hasar)
			vurulan_hedefler.append(sahip)
			player.hit_pause()
			player.ekran_salla()
			_combo_artir(player)   # ← SADECE yeni hedef vurulunca

func _combo_artir(player) -> void:
	player.combo_sayisi += 1
	player.combo_zamanlayici = 2.0
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("combo_goster"):
		hud.combo_goster(player.combo_sayisi)
