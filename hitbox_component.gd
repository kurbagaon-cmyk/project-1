extends Area3D

@export var hasar: int = 10
var vurdu_mu: bool = false

func _ready() -> void:
	monitoring = false
	body_entered.connect(_on_body_entered)
	
func vurmayi_baslat() -> void:
	vurdu_mu = false
	monitoring = true
	# İçerde zaten duran oyuncuya hemen vur
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
	if body.has_method("take_damage"):
		vurdu_mu = true
		body.take_damage(hasar)
		print("💥 DÜŞMAN VURDU: ", hasar)
