class_name ParkurYardimci
extends RefCounted

# ============================================================
# PARKUR YARDIMCILARI
# LedgeState ve WallRunState'in ortak kullandığı fonksiyonlar.
# ============================================================

# Oyuncunun basılı tuşlardan hesaplanan yatay yönü.
static func girdi_yonu(oyuncu) -> Vector3:
	var g: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if g.length() < 0.1:
		return Vector3.ZERO
	var cam: Basis = oyuncu.camera_pivot.global_transform.basis
	var ileri: Vector3 = Vector3(-cam.z.x, 0.0, -cam.z.z).normalized()
	var sag: Vector3 = Vector3(cam.x.x, 0.0, cam.x.z).normalized()
	return (sag * g.x + ileri * (-g.y)).normalized()

# Zıplama tuşuna bu karede basıldı mı?
static func zipla_basildi() -> bool:
	for ad in ["jump", "ui_accept"]:
		if InputMap.has_action(ad) and Input.is_action_just_pressed(ad):
			return true
	return false

static func egil_basildi() -> bool:
	return InputMap.has_action("crouch") and Input.is_action_just_pressed("crouch")

# Işın atar, ilk çarptığı şeyi döndürür.
static func isin(oyuncu, bas: Vector3, son: Vector3) -> Dictionary:
	var sorgu: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(bas, son)
	var haric: Array[RID] = [oyuncu.get_rid()]
	for d in oyuncu.get_tree().get_nodes_in_group("enemy"):
		if d is CollisionObject3D:
			haric.append(d.get_rid())
	sorgu.exclude = haric
	var sonuc: Dictionary = oyuncu.get_world_3d().direct_space_state.intersect_ray(sorgu)
	if not sonuc.is_empty() and sonuc["collider"] is CharacterBody3D:
		return {}
	return sonuc

# Bir yol üzerinde geçen süreye karşılık gelen konumu bulur.
static func yoldaki_konum(yol: Array, sureler: Array, t: float) -> Vector3:
	var kalan: float = t
	var son_parca: int = sureler.size() - 1
	for i in sureler.size():
		var sure: float = sureler[i]
		if kalan <= sure or i == son_parca:
			var k: float = clampf(kalan / sure, 0.0, 1.0)
			if sureler.size() == 1:
				k = smoothstep(0.0, 1.0, k)
			elif i == 0:
				k = 1.0 - cos(k * PI * 0.5)
			elif i == son_parca:
				k = sin(k * PI * 0.5)
			return yol[i].lerp(yol[i + 1], k)
		kalan -= sure
	return yol[yol.size() - 1]

# Karakter modelini verilen yöne çevirir.
static func mesh_don(oyuncu, f: Vector3, model_ileri_z: bool) -> void:
	var yatay: Vector3 = Vector3(f.x, 0.0, f.z)
	if yatay.length() < 0.01:
		return
	yatay = yatay.normalized()
	var aci: float = atan2(yatay.x, yatay.z)
	if not model_ileri_z:
		aci += PI
	oyuncu.mesh.global_rotation.y = aci

# Animasyon adını anahtar kelimelere göre bulur; yoksa yedek adı dener.
static func anim_bul(anim: AnimationPlayer, anahtarlar: Array, yedek: String) -> String:
	if anim == null:
		return ""
	for adi in anim.get_animation_list():
		var kucuk: String = String(adi).to_lower()
		for k in anahtarlar:
			if kucuk.contains(k):
				return String(adi)
	if anim.has_animation(yedek):
		return yedek
	return ""

# Animasyonu oynatır.
static func anim_oynat(anim: AnimationPlayer, anahtarlar: Array, yedek: String, hiz: float = 1.0, yeniden_baslat: bool = false) -> void:
	var adi: String = anim_bul(anim, anahtarlar, yedek)
	if adi == "":
		return
	if not yeniden_baslat and anim.current_animation == adi and anim.is_playing():
		return
	anim.play(adi, 0.1, hiz)
