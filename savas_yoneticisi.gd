class_name SavasYoneticisi
extends RefCounted

# ============================================================
# SALDIRI HAKKI (TOKEN) SİSTEMİ
# Aynı anda sadece birkaç düşman oyuncuya saldırabilir.
# Hakkı olmayanlar CircleState'te oyuncunun etrafında dolaşır.
# Sahneye eklemek gerekmez, class_name sayesinde her yerden çağrılır:
#   SavasYoneticisi.slot_iste(dusman)
# ============================================================

# Aynı anda en fazla kaç düşman saldırıya geçebilir (1 = tek tek, 2 = ikili baskı)
static var max_saldirgan: int = 2
# Bir düşman hakkı bu süre (sn) içinde kullanmazsa hak otomatik geri alınır
static var slot_omru: float = 5.0

# dusman instance id -> hakkın verildiği zaman (ms)
static var slotlar: Dictionary = {}

static func _temizle() -> void:
	var simdi: int = Time.get_ticks_msec()
	for id in slotlar.keys():
		var obj = instance_from_id(id)
		if obj == null or not is_instance_valid(obj) or simdi - int(slotlar[id]) > slot_omru * 1000.0:
			slotlar.erase(id)

# Saldırı hakkı ister. Zaten sahipse true döner.
static func slot_iste(dusman: Object) -> bool:
	_temizle()
	var id: int = dusman.get_instance_id()
	if slotlar.has(id):
		return true
	if slotlar.size() < max_saldirgan:
		slotlar[id] = Time.get_ticks_msec()
		return true
	return false

static func sahip_mi(dusman: Object) -> bool:
	_temizle()
	return slotlar.has(dusman.get_instance_id())

static func slot_birak(dusman: Object) -> void:
	slotlar.erase(dusman.get_instance_id())

# Düşmanların üst üste binmemesi için diğer düşmanlardan uzaklaştıran vektör
static func ayrilma(dusman: Node3D, yaricap: float = 2.0) -> Vector3:
	var toplam: Vector3 = Vector3.ZERO
	for diger in dusman.get_tree().get_nodes_in_group("enemy"):
		if diger == dusman or not (diger is Node3D):
			continue
		var fark: Vector3 = dusman.global_position - diger.global_position
		fark.y = 0.0
		var mesafe: float = fark.length()
		if mesafe > 0.001 and mesafe < yaricap:
			toplam += fark / mesafe * (1.0 - mesafe / yaricap)
	return toplam

# Bir ses çıkarır: yarıçap içindeki farkında olmayan düşmanlar duyar, şüphelenir, sese doğru gelir.
# kaynak: sesi çıkaran düğüm (oyuncu ya da ölen düşman), yaricap: metre, siddet: 0..1
static func ses_cikar(kaynak: Node3D, yaricap: float, siddet: float = 0.6) -> void:
	for d in kaynak.get_tree().get_nodes_in_group("enemy"):
		if d == kaynak or not is_instance_valid(d) or not (d is Node3D):
			continue
		if d.has_method("ses_duy"):
			d.ses_duy(kaynak.global_position, yaricap, siddet)
