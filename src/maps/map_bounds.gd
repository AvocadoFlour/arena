class_name MapBounds
extends Node3D
## Out-of-bounds handling + fall recovery (maps queue 3), map root child "Bounds". Data: map JSON "out_of_bounds".
## No physics bodies: every rule is a fixed-tick position check against the data (deterministic, collision golden
## untouched, nothing visual, identical in low quality). Host/offline (authority) decides; clients never act.
##
##   "out_of_bounds": {
##     "bounds":  {"min": [x, y, z], "max": [x, y, z]},   playable box: x/z = inside faces of the outer walls,
##                                                        min.y = kill plane, max.y = ceiling
##     "below":   {"mode": "recover"|"kill", "damage": 10}  feet below min.y (fell through / into the void)
##     "outside": {"mode": "recover"|"kill", "damage": 10}  outside the walls in x/z, or above the ceiling
##     "volumes": [{"id", "pos", "size", "mode", "damage"?, "stand"?: bool, "dwell"?: s}]
##                pits / void (mode kill) or no-stand areas such as outer-wall rims and spawn-room wall tops
##                (mode recover, stand = only counts while the hero is not moving vertically, |vy| < 0.5,
##                for `dwell` s in a row, so a hero flying through is never touched)
##     "credit_window": 4.0   s: a kill or a lethal penalty is credited to the last enemy that damaged the hero
##   }
## Missing key: bounds = the floor blocks' x/z extent, kill plane 3 m below the floor top, ceiling 20 m above it,
## both modes "recover", damage 10.
##
## recover: teleport to the nearest safe point (MapGrid, 1 m cells inside the box: flat 3x3 cells, 0.8 m clear of
## every block, reachable from the spawns, not in spawn rooms / barriers / spawn areas / zones / pickups / pads /
## volumes, not next to a spawn), nearest to the hero's last in-bounds position, skipping points another living
## hero stands on; velocity reset; then `damage` with kind "fall" (credited only if it is lethal).
## kill: take_damage(lethal, credit, pos, "fall") -> Events.killed {killer = credit or null, kind "fall"}.
## If the kill is refused (e.g. a damage-immune / spawn-shielded hero) the hero is recovered instead, so nobody is
## ever left outside the map.
## Signal (host/offline): out_of_bounds({hero, mode, reason: below|outside|ceiling|volume, volume_id, from, to,
## damage, credit, killed}); also emitted on Events.out_of_bounds when core adds that signal (see requests).

signal out_of_bounds(ev: Dictionary)

const TICK := 1.0 / 60.0
const KILL_DAMAGE := 1.0e6
const SAFE_CELL := 1.0
const CLEAR := 0.8              ## m: safe points keep this far (x/z) from every block above the feet
const CLEAR_H := 2.0            ## m: ... up to this height above the feet
const STAND_VY := 0.5

var lo := Vector3.ZERO
var hi := Vector3.ZERO
var below := {"mode": "recover", "damage": 10.0}
var outside := {"mode": "recover", "damage": 10.0}
var volumes: Array = []         ## [{id, aabb, mode, damage, stand, dwell_ticks}]
var credit_window := 4.0
var authority_override := -1    ## tests: -1 ask Net, 0 client, 1 host
var tick := 0
var _def: Dictionary = {}
var _safe: Array = []           ## Array[Vector3] in grid order (deterministic)
var _safe_built := false
var _st := {}                   ## hero instance id -> {last: Vector3|null, dwell: {vol_index: ticks}}
var _hits := {}                 ## victim instance id -> {source, tick}

static func from_def(d: Dictionary) -> MapBounds:
    var b := MapBounds.new()
    b.name = "Bounds"
    b._def = d
    var o: Dictionary = d.get("out_of_bounds", {})
    var floor_top := 0.0
    var fmin := Vector2(INF, INF)
    var fmax := Vector2(-INF, -INF)
    for blk in d.get("blocks", []):
        if String(blk.get("kind", "")) == "floor":
            var p := _v(blk.pos)
            var s := _v(blk.size)
            floor_top = p.y + s.y * 0.5
            fmin = Vector2(minf(fmin.x, p.x - s.x * 0.5), minf(fmin.y, p.z - s.z * 0.5))
            fmax = Vector2(maxf(fmax.x, p.x + s.x * 0.5), maxf(fmax.y, p.z + s.z * 0.5))
    if o.has("bounds"):
        b.lo = _v(o.bounds.min)
        b.hi = _v(o.bounds.max)
    elif fmin.x < INF:
        b.lo = Vector3(fmin.x, floor_top - 3.0, fmin.y)
        b.hi = Vector3(fmax.x, floor_top + 20.0, fmax.y)
    else:
        var h := float(d.get("bounds", 17))
        b.lo = Vector3(-h, -3.0, -h)
        b.hi = Vector3(h, 20.0, h)
    b.below = _rule(o.get("below", {}))
    b.outside = _rule(o.get("outside", {}))
    b.credit_window = float(o.get("credit_window", 4.0))
    var i := 0
    for v in o.get("volumes", []):
        var r := _rule(v)
        r["id"] = String(v.get("id", "v%d" % i))
        r["aabb"] = AABB(_v(v.pos) - _v(v.size) * 0.5, _v(v.size))
        r["stand"] = bool(v.get("stand", false))
        r["dwell_ticks"] = int(round(float(v.get("dwell", 0.0)) * 60.0))
        b.volumes.append(r)
        i += 1
    return b

static func _rule(r: Dictionary) -> Dictionary:
    var mode := String(r.get("mode", "recover"))
    if mode != "kill":
        mode = "recover"   # unknown modes fall back to the safe option
    return {"mode": mode, "damage": float(r.get("damage", 10.0))}

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
    if ev != null and ev.has_signal("damage_dealt"):
        ev.connect("damage_dealt", _on_damage)
    if is_authority():
        safe_points()   # build at load on the host, never mid-match

func _physics_process(_dt: float) -> void:
    if is_authority():
        step(get_tree().get_nodes_in_group("heroes"))

func _on_damage(ev: Dictionary) -> void:
    if is_authority() and ev.get("source") != null and ev.get("target") != null:
        note_hit(ev.target, ev.source)

## Remember who last damaged `target` (kill credit). Self/ally damage and environment hits are ignored.
func note_hit(target, source) -> void:
    if source == null or target == null or source == target or not is_instance_valid(source):
        return
    if "team" in source and "team" in target and int(source.team) == int(target.team):
        return
    _hits[target.get_instance_id()] = {"source": source, "tick": tick}

## Enemy credited for an environmental death of `h` right now, or null.
func credit_for(h):
    var e = _hits.get(h.get_instance_id())
    if e == null or tick - int(e.tick) > int(round(credit_window * 60.0)):
        return null
    var s = e.source
    if not is_instance_valid(s):
        return null
    return s

## Where a position stands. Returns {} if in bounds, else {mode, damage, reason, volume_id, index}.
## `vy` = vertical velocity (stand volumes only count while |vy| < 0.5).
func classify(p: Vector3, vy := 0.0) -> Dictionary:
    for i in volumes.size():
        var v: Dictionary = volumes[i]
        if v.aabb.has_point(p) and (not v.stand or absf(vy) < STAND_VY):
            return {"mode": v.mode, "damage": v.damage, "reason": "volume", "volume_id": v.id, "index": i}
    if p.y < lo.y:
        return {"mode": below.mode, "damage": below.damage, "reason": "below", "volume_id": "", "index": -1}
    if p.x < lo.x or p.x > hi.x or p.z < lo.z or p.z > hi.z:
        return {"mode": outside.mode, "damage": outside.damage, "reason": "outside", "volume_id": "", "index": -1}
    if p.y > hi.y:
        return {"mode": outside.mode, "damage": outside.damage, "reason": "ceiling", "volume_id": "", "index": -1}
    return {}

func in_bounds(p: Vector3) -> bool:
    return classify(p).is_empty()

## One fixed host tick. heroes: objects with team, dead, global_position, velocity, take_damage(...).
func step(heroes: Array) -> void:
    if not is_authority():
        return
    tick += 1
    for h in heroes:
        var key: int = h.get_instance_id()
        if h.dead:
            _st.erase(key)
            _hits.erase(key)
            continue
        var st: Dictionary = _st.get(key, {"last": null, "dwell": {}})
        _st[key] = st
        var p: Vector3 = h.global_position
        var c := classify(p, h.velocity.y)
        if c.is_empty():
            st.last = p
            st.dwell = {}
            continue
        if c.index >= 0:
            var v: Dictionary = volumes[c.index]
            if v.dwell_ticks > 0:
                var n: int = int(st.dwell.get(c.index, 0)) + 1
                st.dwell = {c.index: n}
                if n < v.dwell_ticks:
                    continue
        st.dwell = {}
        _act(h, c, st, heroes)

func _act(h, c: Dictionary, st: Dictionary, heroes: Array) -> void:
    var from: Vector3 = h.global_position
    var credit = credit_for(h)
    var ev := {"hero": h, "mode": c.mode, "reason": c.reason, "volume_id": c.volume_id, "from": from,
        "to": null, "damage": 0.0, "credit": null, "killed": false}
    if c.mode == "kill":
        h.take_damage(KILL_DAMAGE, credit, from, "fall", "")
        if h.dead:
            ev.damage = KILL_DAMAGE
            ev.credit = credit
            ev.killed = true
            _emit(ev)
            return
        ev.mode = "recover"   # kill refused (immune / shielded): never leave a hero outside the map
        c = {"damage": 0.0}
    var to = nearest_safe(st.last if st.last != null else _clamped(from), heroes, h)
    if to == null:   # no safe point at all (broken data): fall back to the kill
        h.take_damage(KILL_DAMAGE, credit, from, "fall", "")
        ev.mode = "kill"
        ev.killed = bool(h.dead)
        ev.credit = credit
        _emit(ev)
        return
    h.global_position = to
    h.velocity = Vector3.ZERO
    if "dash_time" in h:
        h.dash_time = 0.0
    st.last = to
    ev.to = to
    var dmg: float = c.damage
    if dmg > 0.0:
        var lethal := dmg >= _hp(h)
        ev.credit = credit if lethal else null
        ev.damage = h.take_damage(dmg, ev.credit, to, "fall", "")
        ev.killed = bool(h.dead)
    _emit(ev)

func _emit(ev: Dictionary) -> void:
    out_of_bounds.emit(ev)
    var bus := _bus()
    if bus != null and bus.has_signal("out_of_bounds"):
        bus.emit_signal("out_of_bounds", ev)

static func _hp(h) -> float:
    var hp := INF
    if "health" in h and h.health != null:
        hp = float(h.health.hp)
    elif "hp" in h:
        hp = float(h.hp)
    if "overheal" in h:
        hp += float(h.overheal)
    return hp

func _clamped(p: Vector3) -> Vector3:
    return Vector3(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y + 3.0, hi.y), clampf(p.z, lo.z, hi.z))

## Safe point nearest to `anchor` (3D), skipping points within 1 m of another living hero. Deterministic:
## ties go to the earlier point in grid order. null only if the map has no safe point.
func nearest_safe(anchor: Vector3, heroes: Array = [], self_hero = null):
    var pts := safe_points()
    var best = null
    var bd := INF
    for p in pts:
        var d2: float = (p - anchor).length_squared()
        if d2 >= bd:
            continue
        var taken := false
        for o in heroes:
            if o != self_hero and not o.dead and (o.global_position - p).length_squared() < 1.0:
                taken = true
                break
        if not taken:
            bd = d2
            best = p
    return best

func safe_points() -> Array:
    if not _safe_built:
        _safe = compute_safe_points(_def, self)
        _safe_built = true
    return _safe

static func compute_safe_points(d: Dictionary, b: MapBounds) -> Array:
    var g := MapGrid.from_def_region(d, SAFE_CELL, Vector2(b.lo.x, b.lo.z), Vector2(b.hi.x, b.hi.z))
    var reach := {}
    var sp: Dictionary = d.get("spawns", {})
    var starts: Array = []
    for team in sp:
        for s in sp[team]:
            starts.append(_v(s))
    for s in starts:
        var n := g.node_at(s)
        if n >= 0 and not reach.has(n):
            reach.merge(g.flood(n))
    var boxes: Array = []   # block world AABBs (conservative clearance test)
    for blk in d.get("blocks", []):
        var rot: Array = blk.get("rot_deg", [0, 0, 0])
        var basis := Basis.from_euler(Vector3(deg_to_rad(rot[0]), deg_to_rad(rot[1]), deg_to_rad(rot[2])), EULER_ORDER_YXZ)
        boxes.append(Transform3D(basis, _v(blk.pos)) * AABB(-_v(blk.size) * 0.5, _v(blk.size)))
    var keep_out: Array = []   # gameplay data the recovery must never drop a hero into
    for team in d.get("spawn_rooms", {}):
        var r: Dictionary = d.spawn_rooms[team]
        keep_out.append(AABB(_v(r.pos) - _v(r.size) * 0.5, _v(r.size)).grow(1.0))
        for br in r.get("barriers", []):
            keep_out.append(AABB(_v(br.pos) - _v(br.size) * 0.5, _v(br.size)).grow(1.0))
    for team in d.get("spawn_areas", {}):
        for a in d.spawn_areas[team]:
            keep_out.append(AABB(_v(a.pos) - _v(a.size) * 0.5, _v(a.size)).grow(1.0))
    for z in d.get("zones", []):
        keep_out.append(AABB(_v(z.pos) - _v(z.size) * 0.5, _v(z.size)).grow(0.5))
    for p in d.get("pickups", []):
        var r := float(p.get("radius", 1.0)) + 0.5
        keep_out.append(AABB(_v(p.pos) - Vector3(r, 0.5, r), Vector3(r, 1.5, r) * 2.0))
    for p in d.get("jump_pads", []):
        var s := _v(p.get("size", [2, 1, 2]))
        keep_out.append(AABB(_v(p.pos) - Vector3(s.x * 0.5, 0.1, s.z * 0.5), s).grow(1.0))
    for s in starts:
        keep_out.append(AABB(s - Vector3(1.5, 1.0, 1.5), Vector3(3.0, 3.0, 3.0)))
    for v in b.volumes:
        keep_out.append((v.aabb as AABB).grow(0.5))
    var out: Array = []
    var ids: Array = reach.keys()
    ids.sort()
    for n in ids:
        var ci: int = n >> 4
        var ix := ci % g.nx
        var iz := ci / g.nx
        var p := g.node_pos(n)
        if not b.in_bounds(p) or p.y > b.hi.y - CLEAR_H:
            continue
        var flat := true
        for dz in [-1, 0, 1]:
            for dx in [-1, 0, 1]:
                var jx: int = ix + dx
                var jz: int = iz + dz
                if jx < 0 or jz < 0 or jx >= g.nx or jz >= g.nz:
                    flat = false
                    continue
                var ok := false
                for hh in g.columns[jz * g.nx + jx]:
                    if absf(hh - p.y) < 0.05:
                        ok = true
                if not ok:
                    flat = false
        if not flat:
            continue
        var hero_box := AABB(p + Vector3(-CLEAR, 0.05, -CLEAR), Vector3(CLEAR * 2.0, CLEAR_H, CLEAR * 2.0))
        var clear := true
        for bx in boxes:
            if (bx as AABB).intersects(hero_box):
                clear = false
                break
        if clear:
            for k in keep_out:
                if (k as AABB).has_point(p + Vector3(0, 0.1, 0)):
                    clear = false
                    break
        if clear:
            out.append(p + Vector3(0, 0.05, 0))
    return out
