extends StaticBody3D
@export var hasar_sayisi_sahnesi: PackedScene
@export var max_can: int = 100
var can: int = 100

func _ready():
	can = max_can

func take_damage(miktar: int) -> void:
	can -= miktar
	print("🎯 Düşman canı: ", can)
	
	# Hasar sayısı göster
	if hasar_sayisi_sahnesi:
		var sayi = hasar_sayisi_sahnesi.instantiate()
		get_tree().current_scene.add_child(sayi)
		sayi.global_position = global_position + Vector3(0, 2.5, 0)
		sayi.baslat(miktar)
	
	if can <= 0:
		print("💀 Düşman öldü!")
		queue_free()
