class_name Ability
extends RefCounted
## Base ability (INTERFACES.md section 2.2). Subclasses override _do() / on_landed().
var id := ""
var hero
var def: Dictionary
var cooldown: Cooldown

func _init(h, d: Dictionary) -> void:
    hero = h
    def = d
    id = String(d.get("id", d.get("type", "")))
    cooldown = Cooldown.new(float(d.get("cooldown", 0.0)))

func can_activate() -> bool:
    return cooldown.is_ready()

func activate() -> bool:
    if not can_activate():
        return false
    if not _do():
        return false
    cooldown.trigger()
    return true

func _do() -> bool:
    return true

func tick(dt: float) -> void:
    cooldown.tick(dt)

func on_landed() -> void:
    pass
