extends RefCounted
var errors: Array = []
func check(cond: bool, msg: String) -> void:
    if not cond:
        errors.append(msg)
func near(a: float, b: float, eps: float, msg: String) -> void:
    check(absf(a - b) <= eps, "%s (got %s, want %s)" % [msg, a, b])
