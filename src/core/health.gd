class_name Health
extends RefCounted
var max_hp: float
var hp: float

func _init(m: float = 100.0) -> void:
    max_hp = m
    hp = m

func is_dead() -> bool:
    return hp <= 0.0

## Returns the damage actually applied (clamped to remaining hp, 0 if dead).
func apply(amount: float) -> float:
    if is_dead() or amount <= 0.0:
        return 0.0
    var d := minf(amount, hp)
    hp -= d
    return d

func heal(a: float) -> void:
    if not is_dead():
        hp = minf(max_hp, hp + a)

func reset() -> void:
    hp = max_hp

func fraction() -> float:
    return hp / max_hp
