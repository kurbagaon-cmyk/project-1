extends Control

# Dilim renkleri (Türleri kesinleştirildi)
var base_color: Color = Color(0.1, 0.1, 0.1, 0.7) # Yarı saydam koyu gri
var highlight_color: Color = Color(0.8, 0.2, 0.2, 0.8) # Vampir temasına uygun kırmızı

var active_slice: int = -1 # Hangi dilimin seçili olduğu (-1: Hiçbiri, 0: Silah, 1: Mod, 2: Vampir, 3: Büyü)

# Dilim isimleri
var slice_names: Array[String] = ["Silah", "Ateşli Silah Modu", "Vampir Özellikleri", "Büyü"]

func _draw() -> void:
	var center: Vector2 = get_viewport_rect().size / 2.0 # Ekranın tam ortası
	var inner_radius: float = 50.0 # İç boşluk yarıçapı
	var outer_radius: float = 200.0 # Dış yarıçap
	
	# 4 dilimi çiziyoruz (Her dilim 90 derece = PI / 2 radyan)
	for i in range(4):
		var start_angle: float = i * (PI / 2.0) - (PI / 4.0)
		var end_angle: float = start_angle + (PI / 2.0)
		
		# Eğer bu dilim aktifse vurgu rengini, değilse temel rengi kullan
		var current_color: Color = highlight_color if i == active_slice else base_color
		
		# Daire diliminin yayını (Arc) oluşturup çiziyoruz
		_draw_pie_slice(center, inner_radius, outer_radius, start_angle, end_angle, current_color)
		
		# Dilimlerin ortasına yazıları yerleştiriyoruz
		var mid_angle: float = start_angle + (PI / 4.0)
		var text_pos: Vector2 = center + Vector2(cos(mid_angle), sin(mid_angle)) * ((inner_radius + outer_radius) / 2.0)
		draw_string(ThemeDB.fallback_font, text_pos - Vector2(30, -5), slice_names[i], HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.WHITE)

# Yardımcı Poligon Çizim Fonksiyonu (Daire Dilimi İçin)
func _draw_pie_slice(center: Vector2, inner_r: float, outer_r: float, start_a: float, end_a: float, color: Color) -> void:
	var points := PackedVector2Array()
	var nb_points: int = 32 # Yumuşak kavis için nokta sayısı

	for i in range(nb_points + 1):
		var angle: float = lerp(start_a, end_a, float(i) / nb_points)
		points.append(center + Vector2(cos(angle), sin(angle)) * outer_r)
		
	for i in range(nb_points + 1):
		var angle: float = lerp(end_a, start_a, float(i) / nb_points)
		points.append(center + Vector2(cos(angle), sin(angle)) * inner_r)
		
	draw_polygon(points, [color])
func _process(_delta: float) -> void:
	# 1. Ekranın tam ortasını ve farenin şu anki konumunu alıyoruz 📍
	var center: Vector2 = get_viewport_rect().size / 2.0
	var mouse_pos: Vector2 = get_local_mouse_position()
	
	# 2. Merkezden fareye doğru giden yön vektörünü ve uzaklığı hesaplıyoruz 📏
	var dir: Vector2 = mouse_pos - center
	var distance: float = dir.length()
	
	# 3. ÖLÜ BÖLGE (DEADZONE) KONTROLÜ 🛑
	# Eğer fare merkezden 30 pikselden daha yakınsa, seçim yapılmamış sayılır (-1)
	if distance < 30.0:
		if active_slice != -1:
			active_slice = -1
			queue_redraw() # Ekranı yeniden çiz
		return

	# 4. AÇI HESABI (atan2) 📐
	# atan2(y, x) bize farenin yaptığı açıyı radyan cinsinden (-PI ile +PI arası) verir.
	var angle: float = atan2(dir.y, dir.x)
	
	# 5. AÇIYI DİLİME DÖNÜŞTÜRME 🍕
	# Çarkımızı 4'e böldüğümüz için her dilim PI / 2 (90 derece) genişliğindedir.
	# Başlangıç açısını çizimimizle eşitlemek için (PI / 4) offset ekliyoruz.
	var adjusted_angle: float = fposmod(angle + (PI / 4.0), TAU) # TAU = 2 * PI (360 derece)
	var new_slice: int = int(adjusted_angle / (PI / 2.0))
	
	# 6. EĞER SEÇİM DEĞİŞTİYSE EKRANI YENİDEN ÇİZ 🎨
	if new_slice != active_slice:
		active_slice = new_slice
		queue_redraw() # _draw() fonksiyonunu tekrar çalıştırır
