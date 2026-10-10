extends StaticBody3D

@export var max_health = 30.0
var health = max_health

func take_damage(amount):
	health -= amount
	print("Hasar alındı! Kalan can: ", health)
	if health <= 0:
		queue_free()  # can bitince yok ol
