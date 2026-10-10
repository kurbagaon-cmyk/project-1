class_name OyunDurumu
extends RefCounted

# ============================================================
# OYUN BOYUNCA KALICI DEĞERLER
# Sahneye eklemek gerekmez, her yerden çağrılır: OyunDurumu.karanlik_kazan(...)
# Değerler sahne yeniden yüklense de (ölüm, bölüm geçişi) kalır, oyun kapanınca sıfırlanır.
# İleride kaydetme sistemi eklenince disk'e yazılacak.
#
# KARANLIK: karanlık barut ve karanlık büyü kullanıldıkça artar. Oyunun sonu bu değere bağlanacak.
#   Seviye 0: 0-24, 1: 25-49, 2: 50-74, 3: 75-99, 4: 100 (tam karanlık)
# ============================================================

const MAX_KARANLIK: float = 100.0

static var karanlik: float = 0.0

static func karanlik_kazan(miktar: float, kaynak: Node = null) -> void:
	var onceki: int = karanlik_seviyesi()
	karanlik = clampf(karanlik + miktar, 0.0, MAX_KARANLIK)
	if karanlik_seviyesi() > onceki:
		print("🌑 KARANLIK SEVİYESİ YÜKSELDİ: ", karanlik_seviyesi(), " (", snappedf(karanlik, 0.1), "/", MAX_KARANLIK, ")")
	_hud_guncelle(kaynak)

static func karanlik_seviyesi() -> int:
	return int(karanlik / 25.0)

# Yeni oyun başlarken çağır
static func sifirla() -> void:
	karanlik = 0.0

# HUD'da karanlık barı varsa günceller (fonksiyon adı farklıysa buraya ekle)
static func _hud_guncelle(kaynak: Node) -> void:
	if kaynak == null:
		return
	var hud = kaynak.get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	for ad in ["update_darkness", "update_karanlik"]:
		if hud.has_method(ad):
			hud.call(ad, karanlik, MAX_KARANLIK)
			return
