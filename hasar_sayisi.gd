extends Node3D

@onready var label: Label3D = $Label3D
var yatay_hiz: float = 0.0
var yukseklik_hizi: float = 1.5      # Yukarı çıkma hızı
var yasam_suresi: float = 1.0        # Kaç saniye görünsün
var sayac: float = 0.0

func baslat(miktar: float, kritik: bool = false) -> void:
	label.text = str(int(miktar))
	if kritik:
		label.modulate = Color(1, 0.9, 0.2)
		label.font_size = 48
	else:
		label.modulate = Color(1, 0.2, 0.2)
		label.font_size = 32
	
	# Rastgele yönde dağıl (360°)
	var aci = randf() * TAU   # 0-360 derece
	var yaricap = randf_range(0.3, 1.0)
	position.x += cos(aci) * yaricap
	position.z += sin(aci) * yaricap
	position.y += randf_range(-0.1, 0.5)
	
	# Yukarı çıkarken yana kaysın
	yatay_hiz = cos(aci) * 0.5

func _process(delta: float) -> void:
	# Yukarı süzül
	position.y += yukseklik_hizi * delta
	# Yana kay
	position.x += yatay_hiz * delta
	
	sayac += delta
	
	# Solma efekti (son %50'de)
	if sayac > yasam_suresi * 0.5:
		var kalan = 1.0 - (sayac - yasam_suresi * 0.5) / (yasam_suresi * 0.5)
		label.modulate.a = clamp(kalan, 0.0, 1.0)
	
	# Süre bitince sil
	if sayac >= yasam_suresi:
		queue_free()
