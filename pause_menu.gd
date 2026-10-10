extends CanvasLayer

func _ready():
	visible = false
	# Bu menü, oyun duraklatıldığında çalışsın
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		print("ESC BASILDI")
		if get_tree().paused:
			visible = false
			get_tree().paused = false
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			visible = true
			get_tree().paused = true
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
func _durdur():
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _devam_et():
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# Buton fonksiyonları
func _on_devam_pressed():
	_devam_et()

func _on_ana_menu_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _on_cikis_pressed():
	get_tree().quit()
