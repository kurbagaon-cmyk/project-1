extends MeshInstance3D

@export var trail_base: Node3D
@export var trail_tip: Node3D
@export var max_points: int = 15
@export var trail_lifetime: float = 0.3
@export var min_distance: float = 0.05
@export var renk: Color = Color(0.8, 0.9, 1.0, 0.8)

var points: Array = []
var trail_active: bool = false

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY   # ← BU SATIR EKLENDİ
	mesh = ImmediateMesh.new()
	# ... geri kalan aynı
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	material_override = mat

func _process(delta: float) -> void:
	if not trail_active:
		if points.size() > 0:
			points.clear()
			mesh.clear_surfaces()
		return
	
	# Yeni nokta ekle (yeterince hareket ettiyse)
	if trail_base and trail_tip:
		var yeni_base = trail_base.global_position
		var yeni_tip = trail_tip.global_position
		var ekle = points.is_empty()
		if not ekle:
			var son = points[-1]
			if yeni_base.distance_to(son["base"]) > min_distance:
				ekle = true
		if ekle:
			points.append({
				"base": yeni_base,
				"tip": yeni_tip,
				"time": 0.0
			})
	
	# Yaşlandır
	var i = points.size() - 1
	while i >= 0:
		points[i]["time"] += delta
		if points[i]["time"] > trail_lifetime:
			points.remove_at(i)
		i -= 1
	
	while points.size() > max_points:
		points.pop_front()
	
	_mesh_yenile()

func _mesh_yenile() -> void:
	mesh.clear_surfaces()
	if points.size() < 2:
		return
	
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in points:
		var yas = p["time"] / trail_lifetime
		var alfa = 1.0 - yas
		var renk_nokta = Color(renk.r, renk.g, renk.b, renk.a * alfa)
		mesh.surface_set_color(renk_nokta)
		mesh.surface_add_vertex(p["base"])
		mesh.surface_set_color(renk_nokta)
		mesh.surface_add_vertex(p["tip"])
	mesh.surface_end()

func trail_baslat() -> void:
	trail_active = true

func trail_durdur() -> void:
	trail_active = false
