extends Node3D

@onready var label: Label3D = $Label3D

var yukseklik_hizi: float = 1.5
var yasam_suresi: float = 1.0
var sayac: float = 0.0
var yatay_hiz: float = 0.0

func baslat(miktar: int) -> void:
	label.text = str(miktar)
	
	# Rastgele yöne dağıl
	var aci = randf() * TAU
	var yaricap = randf_range(0.3, 0.8)
	position.x += cos(aci) * yaricap
	position.z += sin(aci) * yaricap
	position.y += randf_range(0.0, 0.3)
	yatay_hiz = cos(aci) * 0.5

func _process(delta: float) -> void:
	position.y += yukseklik_hizi * delta
	position.x += yatay_hiz * delta
	sayac += delta
	
	if sayac > yasam_suresi * 0.5:
		var kalan = 1.0 - (sayac - yasam_suresi * 0.5) / (yasam_suresi * 0.5)
		label.modulate.a = clamp(kalan, 0.0, 1.0)
	
	if sayac >= yasam_suresi:
		queue_free()
