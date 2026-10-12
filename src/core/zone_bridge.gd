class_name ZoneBridge
extends Node
## Forwards one CaptureZone (src/maps) to the Events bus as the single capture contract:
## capture_progress (<= 10 Hz, immediate on contested flip) and capture_completed.
const INTERVAL := 0.1
var zone
var _last := -1.0
var _pending := false
var _last_contested := false
var _ev := {}

static func wire(z) -> ZoneBridge:
    var b := ZoneBridge.new()
    b.zone = z
    z.add_child(b)
    z.state_changed.connect(b._on_state)
    z.captured.connect(b._on_captured)
    return b

static func to_progress(ev: Dictionary) -> Dictionary:
    var capt := int(ev.get("capturing_team", -1))
    var owner := int(ev.get("owner", -1))
    return {"zone_id": String(ev.get("zone", "")), "team": capt if capt >= 0 else owner,
        "progress": clampf(float(ev.get("progress", 0.0)), 0.0, 1.0), "contested": bool(ev.get("contested", false)), "owner": owner}

func _now() -> float:
    return Time.get_ticks_msec() / 1000.0 if not Engine.is_in_physics_frame() else float(Engine.get_physics_frames()) / Engine.physics_ticks_per_second

func _on_state(ev: Dictionary) -> void:
    _ev = to_progress(ev)
    var flip: bool = _ev.contested != _last_contested
    if flip or _now() - _last >= INTERVAL:
        _send()
    else:
        _pending = true

func _send() -> void:
    _last = _now()
    _pending = false
    _last_contested = _ev.contested
    Events.capture_progress.emit(_ev)

func _physics_process(_dt: float) -> void:
    if _pending and _now() - _last >= INTERVAL:
        _send()

func _on_captured(ev: Dictionary) -> void:
    if _pending:
        _send()
    Events.capture_completed.emit({"zone_id": String(ev.get("zone", "")), "team": int(ev.get("team", -1)), "previous": int(ev.get("previous", -1))})
