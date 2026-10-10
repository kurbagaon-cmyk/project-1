extends Node3D

@onready var particles: GPUParticles3D = $GPUParticles3D

func patlat() -> void:
	particles.emitting = false
	particles.restart()
	particles.emitting = true
