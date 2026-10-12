class_name UltMeter
extends RefCounted
## Ultimate charge, filled by damage dealt (1 point per HP of damage).
var cost: float
var charge := 0.0

func _init(c: float = 100.0) -> void:
    cost = c

func add(a: float) -> void:
    charge = minf(cost, charge + maxf(a, 0.0))

func is_full() -> bool:
    return charge >= cost

func fraction() -> float:
    return 1.0 if cost <= 0.0 else charge / cost

func consume() -> bool:
    if not is_full():
        return false
    charge = 0.0
    return true
