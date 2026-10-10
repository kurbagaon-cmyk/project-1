extends CanvasLayer

@export var health_bar: ProgressBar
@export var blood_bar: ProgressBar
@onready var combo_yazi: Label = $ComboYazi

func combo_goster(sayi: int) -> void:
	if sayi < 2:
		combo_yazi.text = ""
		return
	combo_yazi.text = str(sayi) + "x COMBO!"
	combo_yazi.modulate.a = 1.0
	combo_yazi.scale = Vector2(1.3, 1.3)
	var tween = create_tween()
	tween.tween_property(combo_yazi, "scale", Vector2(1.0, 1.0), 0.15)

func combo_gizle() -> void:
	combo_yazi.text = ""
func update_health(current: float, max_value: float):
	health_bar.max_value = max_value
	health_bar.value = current

func update_blood(current: float, max_value: float):
	blood_bar.max_value = max_value
	blood_bar.value = current
