class_name Cooldown
extends RefCounted
var duration: float
var remaining := 0.0

func _init(d: float = 1.0) -> void:
    duration = d

func is_ready() -> bool:
    return remaining <= 0.0

func trigger() -> bool:
    if not is_ready():
        return false
    remaining = duration
    return true

func tick(dt: float) -> void:
    remaining = maxf(0.0, remaining - dt)

func fraction() -> float:
    return 0.0 if duration <= 0.0 else remaining / duration
