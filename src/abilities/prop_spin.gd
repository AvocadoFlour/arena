extends Node3D
## Spins a prop visual around Y (visual only).
var speed := 9.0
func _process(dt: float) -> void:
    rotation.y += dt * speed
