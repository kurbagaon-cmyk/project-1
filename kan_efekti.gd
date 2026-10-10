extends Node3D

@onready var parca: GPUParticles3D = $GPUParticles3D

func _ready() -> void:
	parca.emitting = true
	await get_tree().create_timer(1.2).timeout
	queue_free()
