extends Area3D

@export var hasar: int = 10
@export var koni_acisi: float = 0.3   # 0.3 = ~72° koni (rahat), 0.7 = ~45° (sıkı)
var vurdu_mu: bool = false

func _ready() -> void:
	monitoring = false
	body_entered.connect(_on_body_entered)

func vurmayi_baslat() -> void:
	vurdu_mu = false
	monitoring = true
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		_vur(body)

func vurmayi_durdur() -> void:
	monitoring = false

func _on_body_entered(body: Node3D) -> void:
	_vur(body)

func _vur(body: Node3D) -> void:
	if vurdu_mu:
		return
	if not body.has_method("take_damage"):
		return
	
	# === YÖN KONTROLÜ: Düşmanın ÖNÜNDE Mİ? ===
	var dusman = get_parent() as CharacterBody3D
	if not dusman:
		return
	
	var dusman_pos = dusman.global_position
	var dusman_ileri = -dusman.global_transform.basis.z  # Godot'ta -Z ileri
	var hedefe_yon = body.global_position - dusman_pos
	
	# Y eksenini sıfırla (yukarı-aşağı fark önemsiz)
	dusman_ileri.y = 0
	hedefe_yon.y = 0
	
	if hedefe_yon.length() < 0.1:
		return
	
	# Dot product: 1.0 = tam önde, 0 = yanda, -1 = tam arkada
	var dot = dusman_ileri.normalized().dot(hedefe_yon.normalized())
	
	if dot < koni_acisi:
		# Hedef yanda veya arkada → vurma
		return
	
	# Önde → hasar ver
	vurdu_mu = true
	body.take_damage(hasar)
	print("💥 DÜŞMAN VURDU: ", hasar)
