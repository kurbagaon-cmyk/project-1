extends Node

signal can_degisti(miktar: int, maksimum: int)

@export var max_can: int = 150
var can: int

func _ready() -> void:
	can = max_can

func hasar_al(miktar: int) -> void:
	can -= miktar
	print("Düşman canı: ", can)
	can_degisti.emit(can, max_can)
