extends CanvasLayer

@onready var flash: ColorRect = $Flash

func _ready() -> void:
	flash.color = Color(1, 1, 1, 0)
	flash.visible = false

func flash_goster(renk: Color = Color(1, 1, 1, 0.6), sure: float = 0.08) -> void:
	flash.color = renk
	flash.visible = true
	
	# Görünür yap, sonra hızlıca kaybol
	var tween = create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(flash, "color:a", 0.0, sure)
	tween.tween_callback(func(): flash.visible = false)
