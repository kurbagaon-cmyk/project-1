extends Sprite3D

var maksimum_genislik: float = 100.0   # Piksel cinsinden bar genişliği

func _ready() -> void:
	# Kendi texture'ını oluştur (kod ile)
	texture = _arka_plan_olustur()

func _arka_plan_olustur() -> ImageTexture:
	var boyut = Vector2i(int(maksimum_genislik), 10)
	var img = Image.create(boyut.x, boyut.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.2, 0.2, 0.8))   # koyu gri arka plan
	return ImageTexture.create_from_image(img)

func can_guncelle(miktar: int, maksimum: int) -> void:
	var oran = clamp(float(miktar) / float(maksimum), 0.0, 1.0)
	# Kırmızıdan yeşile geçen renk
	var renk = Color(1.0 - oran, oran, 0.0, 0.9)
	var genislik = int(maksimum_genislik * oran)
	
	if genislik < 1:
		visible = false
		return
	visible = true
	
	var boyut = Vector2i(max(genislik, 1), 10)
	var img = Image.create(boyut.x, boyut.y, false, Image.FORMAT_RGBA8)
	img.fill(renk)
	texture = ImageTexture.create_from_image(img)
