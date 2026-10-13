class_name MapObjects
extends Node3D
## Health packs and jump pads (map JSON "pickups" / "jump_pads"), map root child "Objects".
## No physics bodies: triggers are fixed-tick position checks against the data (deterministic, no
## Area3D callback ordering, collision golden untouched). Ids = index in their JSON array.
## Host/offline (authority) decides everything in _physics_process; clients only apply state:
##   apply_pickup(id, active, respawn_left)   one pickup changed (from host event)
##   apply_state(state())                     late join / resync, state() = {"pickups": [[id, active, left], ...]}
## Signals (host/offline): pickup_taken({id, hero, amount}), pickup_respawned({id}), pad_launched({id, hero, velocity}).
## When core adds Events.pickup_changed / Events.pad_launched these are also emitted on the bus (see requests).
##
## Jump pad prediction: launch velocity is a pure function of data (`pad_velocity(id)`), so a predicted client
## hero can apply it locally with `MapObjects.predict_pad(map_def_objects, pos, vel)` in its own step and match
## the host exactly; without that the client is corrected by normal reconciliation (snap > 0.15 m) one RTT later.

signal pickup_taken(ev: Dictionary)
signal pickup_respawned(ev: Dictionary)
signal pad_launched(ev: Dictionary)

const TICK := 1.0 / 60.0
const PAD_REARM := 0.5          ## s before the same hero can be launched by the same pad again

var pickups: Array = []         ## [{id, kind, pos: Vector3, amount, respawn, radius, active, left, node}]
var pads: Array = []            ## [{id, pos: Vector3, size: Vector3, launch: Vector3, aabb: AABB, node}]
var authority_override := -1    ## tests: -1 ask Net, 0 client, 1 host
var _rearm := {}                ## "pad:heroid" -> ticks left

static func from_def(d: Dictionary, mats_color := {}) -> MapObjects:
    var o := MapObjects.new()
    o.name = "Objects"
    var i := 0
    for p in d.get("pickups", []):
        var e := {"id": i, "kind": String(p.get("kind", "health")), "pos": _v(p.pos),
            "amount": float(p.get("amount", 50.0)), "respawn": float(p.get("respawn", 15.0)),
            "radius": float(p.get("radius", 1.0)), "active": true, "left": 0.0}
        e.node = _pickup_visual(e)
        o.add_child(e.node)
        o.pickups.append(e)
        i += 1
    i = 0
    for p in d.get("jump_pads", []):
        var pos := _v(p.pos)
        var size := _v(p.get("size", [2, 1, 2]))
        var e := {"id": i, "pos": pos, "size": size, "launch": _v(p.launch),
            "aabb": AABB(pos - Vector3(size.x * 0.5, 0.1, size.z * 0.5), Vector3(size.x, size.y, size.z))}
        e.node = _pad_visual(e)
        o.add_child(e.node)
        o.pads.append(e)
        i += 1
    return o

static func _v(a) -> Vector3:
    return Vector3(a[0], a[1], a[2])

func is_authority() -> bool:
    if authority_override >= 0:
        return authority_override == 1
    var ml := Engine.get_main_loop()
    if ml is SceneTree:
        var net: Node = (ml as SceneTree).root.get_node_or_null("Net")
        if net != null and net.has_method("is_authority"):
            return bool(net.is_authority())
    return true

func _bus() -> Node:
    var ml := Engine.get_main_loop()
    return (ml as SceneTree).root.get_node_or_null("Events") if ml is SceneTree else null

func _ready() -> void:
    var ev := _bus()
    if ev != null and ev.has_signal("pickup_changed"):
        ev.connect("pickup_changed", func(e: Dictionary): if not is_authority(): apply_pickup(int(e.id), bool(e.active), float(e.get("left", 0.0))))

func _physics_process(_dt: float) -> void:
    if is_authority():
        step(get_tree().get_nodes_in_group("heroes"))

## One fixed host tick. heroes: objects with team, dead, global_position, velocity, heal(amount) -> float.
func step(heroes: Array) -> void:
    if not is_authority():
        return   # clients never decide pickups/launches
    for p in pickups:
        if not p.active:
            p.left = maxf(0.0, p.left - TICK)
            if p.left <= 0.0:
                _set_pickup(p, true, 0.0)
                pickup_respawned.emit({"id": p.id})
            continue
        for h in heroes:
            if h.dead or p.pos.distance_to(h.global_position) > p.radius:
                continue
            var got: float = h.heal(p.amount)
            if got > 0.0:              # full-HP heroes don't consume it
                _set_pickup(p, false, p.respawn)
                pickup_taken.emit({"id": p.id, "hero": h, "amount": got})
                break
    for k in _rearm.keys():
        _rearm[k] -= 1
        if _rearm[k] <= 0:
            _rearm.erase(k)
    for pad in pads:
        for h in heroes:
            if h.dead or not pad.aabb.has_point(h.global_position):
                continue
            var key := "%d:%d" % [pad.id, h.get_instance_id()]
            if _rearm.has(key) or h.velocity.y > 0.5:
                continue
            h.velocity = pad.launch
            _rearm[key] = int(PAD_REARM * 60.0)
            pad_launched.emit({"id": pad.id, "hero": h, "velocity": pad.launch})
            var bus := _bus()
            if bus != null and bus.has_signal("pad_launched"):
                bus.emit_signal("pad_launched", {"id": pad.id, "hero": h, "velocity": pad.launch})

func _set_pickup(p: Dictionary, active: bool, left: float) -> void:
    p.active = active
    p.left = left
    if p.node:
        p.node.visible = active
    if is_authority():
        var bus := _bus()
        if bus != null and bus.has_signal("pickup_changed"):
            bus.emit_signal("pickup_changed", {"id": p.id, "active": active, "left": left})

## Client entry point: host says pickup `id` is now active/inactive (respawn_left for UI timers).
func apply_pickup(id: int, active: bool, respawn_left := 0.0) -> bool:
    if id < 0 or id >= pickups.size():
        return false
    var p: Dictionary = pickups[id]
    p.active = active
    p.left = respawn_left
    p.node.visible = active
    return true

## Late join / resync.
func state() -> Dictionary:
    var arr: Array = []
    for p in pickups:
        arr.append([p.id, p.active, snappedf(p.left, 0.001)])
    return {"pickups": arr}

func apply_state(s: Dictionary) -> void:
    for e in s.get("pickups", []):
        apply_pickup(int(e[0]), bool(e[1]), float(e[2]))

func pad_velocity(id: int) -> Vector3:
    return pads[id].launch

## Pure prediction helper for a client's own predicted hero: returns the launch velocity if `pos` is on a pad
## and the hero isn't already rising, else `vel` unchanged. Same rule as the host (minus the re-arm timer,
## which only suppresses repeats while still standing on the pad and rising — vel.y > 0.5 covers that).
func predict_pad(pos: Vector3, vel: Vector3) -> Vector3:
    if vel.y > 0.5:
        return vel
    for pad in pads:
        if pad.aabb.has_point(pos):
            return pad.launch
    return vel

static func _mat(c: String, emit := false) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = Color(c)
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    if emit:
        m.emission_enabled = true
        m.emission = Color(c)
    return m

static func _pickup_visual(e: Dictionary) -> Node3D:
    var n := Node3D.new()
    n.name = "pickup_%02d" % e.id
    n.position = e.pos
    var base := MeshInstance3D.new()
    var cm := CylinderMesh.new()
    cm.top_radius = 0.55
    cm.bottom_radius = 0.6
    cm.height = 0.08
    cm.radial_segments = 12
    base.mesh = cm
    base.position.y = 0.04
    base.material_override = _mat("#e8f8e8")
    n.add_child(base)
    var mat := _mat("#40d060", true)
    for s in [Vector3(0.18, 0.55, 0.18), Vector3(0.55, 0.18, 0.18)]:
        var b := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = s
        b.mesh = bm
        b.position.y = 0.75
        b.material_override = mat
        b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        n.add_child(b)
    return n

static func _pad_visual(e: Dictionary) -> Node3D:
    var mi := MeshInstance3D.new()
    mi.name = "pad_%02d" % e.id
    var bm := BoxMesh.new()
    bm.size = Vector3(e.size.x, 0.04, e.size.z)
    mi.mesh = bm
    mi.position = e.pos + Vector3(0, 0.03, 0)
    mi.material_override = _mat("#60c8ff", true)
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return mi
