extends CharacterBody3D

@export var hasar_sayisi_sahnesi: PackedScene
@export var knockback_gucu: float = 6.0
@export var stagger_cooldown: float = 0.8
@export var vurus_parcacigi_sahnesi: PackedScene

var parcacik_havuzu: Array = []
var aktif_parcaciklar: Array = []
var knockback_velocity: Vector3 = Vector3.ZERO
var mesh_instance: MeshInstance3D
var orijinal_material: Material
var stagger_bekleme: float = 0.0
var saldiri_bekleme: float = 0.0
# Parry sonrası sersemleyen düşman ısırılabilir
var isirilabilir: bool = false
var sersem_id: int = 0
@export var parry_sersem_suresi: float = 1.6

# --- Gizlilik / farkındalık ---
# false yaparsan eski davranış: oyuncu algılama alanına girince düşman hemen fark eder
@export var gizlilik_aktif: bool = true
@export var gorus_mesafesi: float = 14.0
@export var gorus_acisi: float = 110.0        # düşmanın önündeki toplam görüş açısı (derece)
@export var gorus_hizi: float = 1.6           # görünce farkındalığın dolma hızı (saniyede)
@export var duyma_hizi: float = 2.0           # duyunca farkındalığın dolma hızı
@export var duyma_kosu: float = 9.0           # koşan oyuncuyu bu mesafeden duyar
@export var duyma_yuru: float = 3.5           # yürüyen oyuncuyu bu mesafeden duyar
@export var uyari_yaricapi: float = 10.0      # fark edince yakındaki düşmanları uyarır
@export var egilme_gorus_carpani: float = 0.5   # oyuncu eğilirken görüş mesafesi çarpanı
@export var egilme_duyma_carpani: float = 0.3   # oyuncu eğilirken duyma mesafesi çarpanı
var farkinda: bool = false
var farkindalik: float = 0.0
var oyuncu_alanda = null
var sessiz_olum: bool = false

# --- Algı sistemi (şüphe, araştırma, arama) ---
@export var esik_suphe: float = 0.25          # bu farkındalıkta şüphelenir (sese/görüntüye döner)
@export var esik_arastir: float = 0.6         # bu farkındalıkta oraya gidip araştırır
@export var azalma_hizi: float = 0.25         # uyaran yoksa farkındalık saniyede bu kadar düşer
@export var algi_siniri: float = 25.0         # oyuncu bundan uzaktaysa hiç hesaplama yapılmaz
@export var isaret_yuksekligi: float = 2.6    # "?" ve "!" işaretinin kafanın üstündeki yüksekliği
var oyuncu_ref = null                         # oyuncu (algı için, alandan bağımsız)
var son_uyaran_poz: Vector3 = Vector3.ZERO    # en son görülen/duyulan konum
var son_poz_zamani: int = 0
var onceki_durum = null                       # şüpheden önceki state (Idle/Patrol), araştırma bitince dönülür
var isaret: Label3D = null
var isaret_id: int = 0
@onready var vurus_sesi: AudioStreamPlayer3D = $VurusSesi
@onready var detection_area: Area3D = $DetectionArea
@onready var state_machine: EnemyStateMachine = $EnemyStateMachine
@onready var health: Node = $Health

# ============================================================
# READY
# ============================================================
func _ready() -> void:
	detection_area.body_entered.connect(_on_player_detected)
	detection_area.body_exited.connect(_on_player_lost)
	
	if health:
		health.can_degisti.connect(_on_can_degisti)
	
	var can_bar = find_child("CanBar", true, false)
	if can_bar and health:
		can_bar.can_guncelle(health.can, health.max_can)
	
	# MeshInstance3D'yi bul (hit_flash için)
	for child in find_children("*", "MeshInstance3D", true, false):
		mesh_instance = child
		break
	if mesh_instance and mesh_instance.get_surface_override_material(0):
		orijinal_material = mesh_instance.get_surface_override_material(0)
	
	# Parçacık havuzunu doldur
	if vurus_parcacigi_sahnesi:
		for i in range(2):
			var parca = vurus_parcacigi_sahnesi.instantiate()
			parca.visible = false
			add_child(parca)
			parcacik_havuzu.append(parca)

# ============================================================
# CAN
# ============================================================
func _on_can_degisti(miktar: int, maksimum: int) -> void:
	var can_bar = find_child("CanBar", true, false)
	if can_bar:
		can_bar.can_guncelle(miktar, maksimum)

# ============================================================
# OYUNCU ALGILAMA
# ============================================================
func _on_player_detected(body: Node3D) -> void:
	if body.is_in_group("player"):
		oyuncu_alanda = body
		# Gizlilik kapalıysa eski davranış: alana girince hemen fark eder
		if not gizlilik_aktif:
			_farkinda_ol(body)

func _on_player_lost(body: Node3D) -> void:
	if body.is_in_group("player"):
		oyuncu_alanda = null
		var savastaydi: bool = farkinda
		farkinda = false
		for state in state_machine.get_children():
			if state is AIState:
				state.player = null
		print("Oyuncu kaybedildi")
		# Savaşı bıraktıysa son bilinen konuma gidip etrafı arar
		if savastaydi:
			son_uyaran_poz = body.global_position
			farkindalik = esik_arastir
			_arastirmaya_gec(true)

# ============================================================
# ALGI SİSTEMİ (görme + duyma + ses olayları)
# Farkındalık 0..1:
#   0.25 şüphelenir: sesin/görüntünün yönüne döner       (SuspiciousState)
#   0.60 araştırır: oraya yürür, etrafına bakar          (InvestigateState)
#   1.00 oyuncuyu fark eder, savaşa girer                (ChaseState)
# Oyuncuyu kaybedince son bilinen konuma gidip arar, bulamazsa eski işine döner.
# ============================================================
func _oyuncuyu_bul() -> void:
	if oyuncu_ref == null or not is_instance_valid(oyuncu_ref):
		oyuncu_ref = get_tree().get_first_node_in_group("player")

func _farkindalik_guncelle(delta: float) -> void:
	if not gizlilik_aktif or farkinda or health.can <= 0:
		return
	_oyuncuyu_bul()
	if oyuncu_ref == null or not is_instance_valid(oyuncu_ref):
		return
	
	var fark: Vector3 = oyuncu_ref.global_position - global_position
	fark.y = 0.0
	var mesafe: float = fark.length()
	var artis: float = 0.0
	
	if mesafe <= algi_siniri:
		var egilmis: bool = oyuncu_ref.get("egiliyor") == true
		var gorulen: bool = false
		
		# Görme: önünde, menzilde ve araya engel girmemiş (eğilen oyuncu daha zor görülür)
		var etkin_gorus: float = gorus_mesafesi * (egilme_gorus_carpani if egilmis else 1.0)
		if mesafe <= etkin_gorus and _goruyor_mu(fark, mesafe):
			artis = gorus_hizi * (1.0 + (1.0 - mesafe / etkin_gorus))   # yakındakini daha çabuk fark eder
			gorulen = true
			son_uyaran_poz = oyuncu_ref.global_position
		
		# Duyma: arkasında bile duyar. Koşan uzaktan, yürüyen yakından duyulur, eğilmek sessizdir.
		var hiz: float = Vector2(oyuncu_ref.velocity.x, oyuncu_ref.velocity.z).length()
		var duyma_yaricapi: float = 0.0
		if hiz > 6.5:
			duyma_yaricapi = duyma_kosu
		elif hiz > 0.5:
			duyma_yaricapi = duyma_yuru
		if egilmis:
			duyma_yaricapi *= egilme_duyma_carpani
		if duyma_yaricapi > 0.0 and mesafe <= duyma_yaricapi:
			if _engel_var(oyuncu_ref.global_position):
				duyma_yaricapi *= 0.6   # duvar sesi zayıflatır
			if mesafe <= duyma_yaricapi:
				var d_artis: float = duyma_hizi * (0.5 + (1.0 - mesafe / duyma_yaricapi))
				artis = maxf(artis, d_artis)
				if not gorulen:
					_ses_konumu_guncelle(oyuncu_ref.global_position, mesafe)
	
	if artis > 0.0:
		farkindalik = minf(farkindalik + artis * delta, 1.0)
	else:
		farkindalik = maxf(farkindalik - azalma_hizi * delta, 0.0)
	_algi_esikleri()

# Duyulan sesin konumu tam bilinmez: mesafeyle orantılı bir sapma eklenir
func _ses_konumu_guncelle(poz: Vector3, mesafe: float) -> void:
	var simdi: int = Time.get_ticks_msec()
	if simdi - son_poz_zamani < 500:
		return
	son_poz_zamani = simdi
	son_uyaran_poz = poz + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * (mesafe * 0.2)

# Farkındalık eşikleri: Idle/Patrol -> Şüphe -> Araştırma -> Savaş
func _algi_esikleri() -> void:
	if farkinda or state_machine == null or state_machine.current_state == null:
		return
	if farkindalik >= 1.0:
		_oyuncuyu_bul()
		if oyuncu_ref != null and is_instance_valid(oyuncu_ref):
			_farkinda_ol(oyuncu_ref)
		return
	var ad: String = String(state_machine.current_state.name)
	if (ad == "IdleState" or ad == "PatrolState") and farkindalik >= esik_suphe:
		_supheye_gec()
	elif ad == "SuspiciousState" and farkindalik >= esik_arastir:
		_arastirmaya_gec(false)

func _supheye_gec() -> void:
	var s = state_machine.get_node_or_null("SuspiciousState")
	if s == null:
		return
	onceki_durum = state_machine.current_state
	print("[ALGI] şüphelendi | farkındalık=", snappedf(farkindalik, 0.01))
	_isaret_goster("?", Color(1.0, 0.85, 0.2), 1.5)
	state_machine.transition_to(s)

func _arastirmaya_gec(arama: bool) -> void:
	var s = state_machine.get_node_or_null("InvestigateState")
	if s == null:
		return
	s.arama_modu = arama
	print("[ALGI] ", "oyuncuyu arıyor" if arama else "araştırmaya gidiyor", " | konum=", son_uyaran_poz)
	_isaret_goster("?", Color(1.0, 0.5, 0.1), 1.5)
	state_machine.transition_to(s)

# Şüphe/araştırma bitti: eski işine (bekleme/devriye) döner
func pasife_don() -> void:
	farkindalik = minf(farkindalik, 0.15)
	farkinda = false
	var hedef = onceki_durum
	if hedef == null or not is_instance_valid(hedef):
		hedef = state_machine.get_node_or_null("IdleState")
	print("[ALGI] sakinleşti, eski işine dönüyor")
	if hedef:
		state_machine.transition_to(hedef)

# Dışarıdan bir ses olayı (savaş sesi, ölen düşman, vb.)
func ses_duy(poz: Vector3, yaricap: float, siddet: float = 0.6) -> void:
	if not gizlilik_aktif or farkinda or health.can <= 0:
		return
	var mesafe: float = global_position.distance_to(poz)
	if _engel_var(poz):
		yaricap *= 0.6
	if mesafe > yaricap:
		return
	var yakinlik: float = 1.0 - mesafe / yaricap
	farkindalik = minf(farkindalik + siddet * (0.5 + yakinlik), 1.0)
	son_poz_zamani = Time.get_ticks_msec()
	son_uyaran_poz = poz + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * (mesafe * 0.15)
	_algi_esikleri()

func _goruyor_mu(fark: Vector3, mesafe: float) -> bool:
	if mesafe < 0.01:
		return true
	var ileri: Vector3 = -global_transform.basis.z
	var aci: float = rad_to_deg(ileri.angle_to(fark / mesafe))
	if aci > gorus_acisi * 0.5:
		return false
	return not _engel_var(oyuncu_ref.global_position)

# Düşmanın gözünden hedefe doğru araya duvar vb. girmiş mi
func _engel_var(hedef: Vector3) -> bool:
	var uzay: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var sorgu: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.5, 0),
		hedef + Vector3(0, 1.0, 0))
	var haric: Array[RID] = [get_rid()]
	if oyuncu_ref != null and is_instance_valid(oyuncu_ref):
		haric.append(oyuncu_ref.get_rid())
	sorgu.exclude = haric
	return not uzay.intersect_ray(sorgu).is_empty()

func _farkinda_ol(body) -> void:
	if farkinda or body == null:
		return
	var simdiki = state_machine.current_state
	var ad: String = String(simdiki.name) if simdiki != null else ""
	if ad == "IdleState" or ad == "PatrolState":
		onceki_durum = simdiki
	farkinda = true
	farkindalik = 1.0
	for state in state_machine.get_children():
		if state is AIState:
			state.player = body
	_isaret_goster("!", Color(1.0, 0.15, 0.15), 1.2)
	print("Oyuncu algılandı")
	# Şüphe/araştırma durumundaysa doğrudan savaşa geç
	if ad == "SuspiciousState" or ad == "InvestigateState":
		var kovala = state_machine.get_node_or_null("ChaseState")
		if kovala:
			state_machine.transition_to(kovala)
	# Yakındaki diğer düşmanları uyar
	for d in get_tree().get_nodes_in_group("enemy"):
		if d != self and is_instance_valid(d) and d is Node3D and d.has_method("uyar"):
			if global_position.distance_to(d.global_position) <= uyari_yaricapi:
				d.uyar(body)

# Başka bir düşman oyuncuyu fark edince çağrılır
func uyar(body) -> void:
	if farkinda or not is_instance_valid(body):
		return
	await get_tree().create_timer(0.4).timeout
	if is_instance_valid(self) and health.can > 0:
		_farkinda_ol(body)

# Kafanın üstünde "?" ya da "!" gösterir
func _isaret_goster(metin: String, renk: Color, sure: float) -> void:
	if isaret == null or not is_instance_valid(isaret):
		isaret = Label3D.new()
		isaret.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		isaret.no_depth_test = true
		isaret.pixel_size = 0.005
		isaret.font_size = 72
		isaret.outline_size = 16
		isaret.position = Vector3(0, isaret_yuksekligi, 0)
		add_child(isaret)
	isaret.text = metin
	isaret.modulate = renk
	isaret.visible = true
	isaret_id += 1
	var id: int = isaret_id
	await get_tree().create_timer(sure).timeout
	if is_instance_valid(self) and isaret != null and is_instance_valid(isaret) and id == isaret_id:
		isaret.visible = false

# ============================================================
# BÖLGE HASARI (baş / gövde / bacak)
# Ateşli silah vuruşun bölgesini bildirir. Baş: ağır sersemleme, gövde: hafif sarsılma,
# bacak: bir süre yavaşlar. Hasar çarpanını silahı kullanan taraf (AimState) uygular.
# ============================================================
var hiz_carpani: float = 1.0       # bacak vurulunca düşer, state'ler hızlarını bununla çarpar
var yavaslama_id: int = 0

func bolge_hasari(bolge: String, miktar: int) -> void:
	if health.can <= 0:
		return
	if bolge == "bas":
		stagger_bekleme = 0.0   # kafa vuruşu sersemlemeyi bekleme süresine bakmadan tetikler
	take_damage(miktar)
	if health.can <= 0:
		return
	var oynatici = find_child("AnimationPlayer", true, false)
	match bolge:
		"bas":
			if oynatici and oynatici.has_animation("Hit_Head"):
				oynatici.play("Hit_Head", 0.05)
		"govde":
			if oynatici and oynatici.has_animation("Hit_Chest"):
				oynatici.play("Hit_Chest", 0.05)
		"bacak":
			_yavaslat(0.45, 2.5)

func _yavaslat(carpan: float, sure: float) -> void:
	yavaslama_id += 1
	var id: int = yavaslama_id
	hiz_carpani = carpan
	await get_tree().create_timer(sure).timeout
	if is_instance_valid(self) and id == yavaslama_id:
		hiz_carpani = 1.0

# ============================================================
# HASAR ALMA
# ============================================================
func take_damage(miktar) -> void:
	# Zaten ölmüşse hasar alma
	if health.can <= 0:
		return
	
	# Vurulan düşman oyuncuyu fark eder (sessiz öldürmede uyarı vermez)
	if not farkinda and not sessiz_olum:
		var vuran = get_tree().get_first_node_in_group("player")
		if vuran and is_instance_valid(vuran):
			_farkinda_ol(vuran)
	
	var hasar_int = int(miktar)
	health.hasar_al(hasar_int)
	hit_flash()
	if vurus_sesi:
		vurus_sesi.play()
	
	# Vuruş parçacıkları
	parcacik_cikar()
	
	# Knockback
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		var yon = (global_position - player.global_position).normalized()
		yon.y = 0
		knockback_velocity = yon * knockback_gucu
	
	# Stagger (cooldown varsa)
	if stagger_bekleme <= 0.0 and health.can > 0:
		stagger_bekleme = stagger_cooldown
		if state_machine:
			var stagger = state_machine.get_node_or_null("StaggerState")
			if stagger:
				state_machine.transition_to(stagger)
	
	# Ölüm
	if health.can <= 0:
		ol()

# Oyuncu saldırıyı parry edince çağrılır.
# sersemlet=true: düşman kısa süre donar (sersemler) ve bu sürede ısırılabilir.
# Finisher sahnesinde sersemlet=false verilir, çünkü sahneyi FinisherState yönetir.
func parry_edildi(sersemlet: bool = true) -> void:
	if health.can <= 0:
		return
	stagger_bekleme = stagger_cooldown
	if state_machine:
		var stagger = state_machine.get_node_or_null("StaggerState")
		if stagger:
			state_machine.transition_to(stagger)
	if vurus_sesi:
		vurus_sesi.play()
	parcacik_cikar()
	if sersemlet:
		_sersem_baslat(parry_sersem_suresi)

func _sersem_baslat(sure: float) -> void:
	sersem_id += 1
	var id: int = sersem_id
	isirilabilir = true
	_sersem_isigi(true)
	dondur()
	await get_tree().create_timer(sure).timeout
	if is_instance_valid(self) and id == sersem_id and isirilabilir:
		isirilabilir = false
		_sersem_isigi(false)
		coz()

# Isırma gibi bir olay sersemliği devralır: zamanlayıcı düşmanı serbest bırakmaz
func sersemi_iptal() -> void:
	sersem_id += 1
	isirilabilir = false
	_sersem_isigi(false)

# Isırılabilir düşman kırmızı parlar (oyuncu fırsatı görsün)
func _sersem_isigi(ac: bool) -> void:
	if not mesh_instance or not is_instance_valid(mesh_instance):
		return
	if ac:
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(0.7, 0.1, 0.15)
		m.emission_enabled = true
		m.emission = Color(0.9, 0.1, 0.2)
		m.emission_energy_multiplier = 1.5
		mesh_instance.material_override = m
	else:
		mesh_instance.material_override = null

# Finisher sahnesi sırasında düşmanın yapay zekasını ve hareketini durdurur
func dondur() -> void:
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	if state_machine:
		state_machine.set_physics_process(false)
	set_physics_process(false)

# Finisher kaçırılınca ya da sahne bölününce düşmanı serbest bırakır
func coz() -> void:
	if health.can <= 0:
		return
	knockback_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	set_physics_process(true)
	if state_machine:
		state_machine.set_physics_process(true)

func hit_flash() -> void:
	if not mesh_instance or not is_instance_valid(mesh_instance):
		return
	var kirmizi = StandardMaterial3D.new()
	kirmizi.albedo_color = Color(1, 0.2, 0.2)
	mesh_instance.material_override = kirmizi
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(mesh_instance):
		mesh_instance.material_override = null

# ============================================================
# ÖLÜM
# ============================================================
func ol() -> void:
	print("Düşman ölüyor...")
	
	# Ölüm sesi: yakındaki farkında olmayan düşmanlar duyup araştırmaya gelir (sessiz öldürmede yok)
	if not sessiz_olum:
		SavasYoneticisi.ses_cikar(self, 10.0, 0.7)
	if isaret != null and is_instance_valid(isaret):
		isaret.visible = false
	
	# Saldırı hakkını geri ver, sersemlik zamanlayıcısını iptal et
	SavasYoneticisi.slot_birak(self)
	sersem_id += 1
	isirilabilir = false
	
	# Hareketi ve processing'i durdur
	velocity = Vector3.ZERO
	set_physics_process(false)
	set_process(false)
	
	# State machine'i durdur
	if state_machine:
		state_machine.set_physics_process(false)
		state_machine.set_process(false)
	
	# Collision'ları kapat (set_deferred: fizik sinyali içinden çağrılabilir)
	for child in find_children("*", "CollisionShape3D", true, false):
		child.set_deferred("disabled", true)
	
	# Vurma alanını ZORLA kapat
	var vurma = find_child("VurmaAlani", true, false)
	if vurma:
		vurma.set_deferred("monitoring", false)
		if vurma.has_method("vurmayi_durdur"):
			vurma.vurmayi_durdur()
	
	# Ölüm animasyonu (slow-mo telafisi için speed_scale)
	var anim = find_child("AnimationPlayer", true, false)
	if anim:
		anim.speed_scale = 1.0 if sessiz_olum else 4.0
		anim.play("Death01")
	
	# Ölüm sesi
	var olum_sesi = get_node_or_null("OlumSesi")
	if olum_sesi:
		olum_sesi.play()
	
	# Sessiz ölüm (gizli ısırma): slow-motion ve sinematik yok
	if sessiz_olum:
		await get_tree().create_timer(2.0).timeout
		queue_free()
		return
	
	# Sinematik zoom-in
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player) and player.has_method("cinematic_zoom_in"):
		player.cinematic_zoom_in()
	
	# === SLOW-MOTION ===
	print("SLOW-MOTION BAŞLIYOR")
	Engine.time_scale = 0.25
	await get_tree().create_timer(0.9, true, false, true).timeout
	
	# Yumuşak dönüş
	while Engine.time_scale < 1.0:
		Engine.time_scale = min(Engine.time_scale + 0.03, 1.0)
		await get_tree().create_timer(0.04, true, false, true).timeout
	Engine.time_scale = 1.0
	print("SLOW-MOTION BİTTİ")
	
	# Animasyon hızını normale döndür
	if anim and is_instance_valid(anim):
		anim.speed_scale = 1.0
	
	# Sinematik zoom-out
	if player and is_instance_valid(player) and player.has_method("cinematic_zoom_out"):
		player.cinematic_zoom_out()
	
	# Bekle, sil
	await get_tree().create_timer(2.0).timeout
	queue_free()

# ============================================================
# FİZİK
# ============================================================
func _physics_process(delta: float) -> void:
	_farkindalik_guncelle(delta)
	
	# Bekleme süreleri
	if saldiri_bekleme > 0.0:
		saldiri_bekleme -= delta
	if stagger_bekleme > 0.0:
		stagger_bekleme -= delta
	
	# Knockback (state'lerin hareketinden bağımsız, geri savrulma)
	if knockback_velocity.length() > 0.1:
		velocity.x = knockback_velocity.x
		velocity.z = knockback_velocity.z
		knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 30.0 * delta)
		move_and_slide()

# ============================================================
# HASAR SAYISI
# ============================================================
func hasar_sayisi_goster(miktar: int, kritik: bool = false) -> void:
	if not hasar_sayisi_sahnesi:
		return
	var sayi = hasar_sayisi_sahnesi.instantiate()
	get_tree().current_scene.add_child(sayi)
	sayi.global_position = global_position + Vector3(0, 2.5, 0)
	sayi.baslat(miktar, kritik)

# ============================================================
# PARÇACIK HAVUZU
# ============================================================
func parcacik_cikar() -> void:
	if parcacik_havuzu.is_empty():
		return
	
	var parca = parcacik_havuzu.pop_front()
	parca.global_position = global_position + Vector3(0, 1.0, 0)
	parca.visible = true
	parca.patlat()
	aktif_parcaciklar.append(parca)
	
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(parca):
		parca.visible = false
		aktif_parcaciklar.erase(parca)
		parcacik_havuzu.append(parca)

# ============================================================
# TELEGRAPH (SALDIRI UYARISI)
# ============================================================
func telegraph_baslat(sure: float = 0.5) -> void:
	if not mesh_instance or not is_instance_valid(mesh_instance):
		return
	# Turuncu-kırmızı parla
	var kirmizi = StandardMaterial3D.new()
	kirmizi.albedo_color = Color(1, 0.3, 0.1)
	kirmizi.emission_enabled = true
	kirmizi.emission = Color(1, 0.4, 0.1)
	kirmizi.emission_energy_multiplier = 3.0
	mesh_instance.material_override = kirmizi
	
	# Uyarı sesi (parlama başlarken çalar)
	if has_node("TelegraphSesi"):
		$TelegraphSesi.play()
	
	await get_tree().create_timer(sure).timeout
	
	if is_instance_valid(mesh_instance):
		mesh_instance.material_override = null
