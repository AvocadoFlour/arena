class_name Weapon
extends RefCounted
## Primary-fire state machine: fire rate, magazine, reload. Pure logic, no nodes.
var damage: float
var fire_interval: float
var mag_size: int
var reload_time: float
var spread_deg: float
var max_range: float
var ammo: int
var _shot_cd := 0.0
var _reload_left := 0.0

func _init(def: Dictionary = {}) -> void:
    damage = float(def.get("damage", 10.0))
    fire_interval = 1.0 / float(def.get("fire_rate", 8.0))
    mag_size = int(def.get("mag", 30))
    reload_time = float(def.get("reload_time", 1.5))
    spread_deg = float(def.get("spread_deg", 1.0))
    max_range = float(def.get("range", 80.0))
    ammo = mag_size

func reloading() -> bool:
    return _reload_left > 0.0

func reload_fraction() -> float:
    return 0.0 if reload_time <= 0.0 else _reload_left / reload_time

func tick(dt: float) -> void:
    _shot_cd = maxf(0.0, _shot_cd - dt)
    if _reload_left > 0.0:
        _reload_left -= dt
        if _reload_left <= 0.0:
            _reload_left = 0.0
            ammo = mag_size

## True if a shot leaves the barrel this tick. Auto-reloads on empty.
func try_fire() -> bool:
    if reloading() or _shot_cd > 0.0:
        return false
    if ammo <= 0:
        start_reload()
        return false
    ammo -= 1
    _shot_cd = fire_interval
    if ammo == 0:
        start_reload()
    return true

func start_reload() -> bool:
    if reloading() or ammo == mag_size:
        return false
    _reload_left = reload_time
    return true
