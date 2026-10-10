extends CanvasLayer

func _ready():
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	# Butonları bul (direkt child olarak)
	for child in get_children():
		if child is Button:
			child.pressed.connect(_buton_basildi.bind(child.name))
		if child is Control:
			for alt in child.get_children():
				if alt is Button:
					alt.pressed.connect(_buton_basildi.bind(alt.name))

func _buton_basildi(buton_adi: String) -> void:
	print("BASILDI: ", buton_adi)
	get_tree().paused = false
	
	if "restart" in buton_adi.to_lower() or "tekrar" in buton_adi.to_lower():
		get_tree().reload_current_scene()
	elif "menu" in buton_adi.to_lower() or "ana" in buton_adi.to_lower():
		get_tree().change_scene_to_file("res://main_menu.tscn")
	elif "quit" in buton_adi.to_lower() or "cikis" in buton_adi.to_lower():
		get_tree().quit()

func show_death_screen():
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
