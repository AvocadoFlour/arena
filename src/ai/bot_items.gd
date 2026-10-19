class_name BotItems
extends RefCounted
## Health packs and jump pads for bots (maps MapObjects, map root child "Objects"; INTERFACES §6.x).
## Bots run on the host only, so pickup state (active / respawn left) is read straight from MapObjects.
## - Packs: pure cost model (travel time, respawn wait, danger) + a per-map claim board so teammates
##   do not all rush the same pack.
## - Pads: one-way NavigationLink3D per pad (pad -> simulated landing), so navmesh paths use pads as
##   shortcuts and bots can use them to escape.

const PACK_WAIT := 1.5        ## s a bot will wait at a pack for its respawn (arrive at most this early)
const DANGER_R := 10.0        ## m: enemies this close to a pack make it dangerous
const DANGER_COST := 3.0      ## s added per enemy near the pack
const THREAT_NEARER_COST := 3.0   ## s added when our current target is closer to the pack than we are
const LINKS_NAME := "BotPadLinks"

static var _claims := {}      ## "map:pack" -> [hero, team, expiry physics frame]

static func objects(map_root: Node) -> Node:
    if map_root == null or not is_instance_valid(map_root):
        return null
    var o := map_root.get_node_or_null("Objects")
    return o if o != null and "pickups" in o else null

## Pure (unit-tested): seconds of "cost" for going to a pack, INF if not worth it / not usable in time.
## eta: travel time; active/left: pickup state; danger: enemies near it; threat_nearer: target closer to it than us.
static func pack_cost(eta: float, active: bool, left: float, danger: int, threat_nearer: bool) -> float:
    if not active and left > eta + PACK_WAIT:
        return INF   # respects the respawn timer: never walks to a pack that is still down on arrival
    var wait := 0.0 if active else maxf(0.0, left - eta)
    return eta + wait + DANGER_COST * danger + (THREAT_NEARER_COST if threat_nearer else 0.0)

## Pure (unit-tested): pack instead of cover? cover_eta < 0 = no cover available.
static func pack_beats_cover(pack_cost_s: float, max_eta: float, cover_eta: float, over_cover := 4.0) -> bool:
    if pack_cost_s > max_eta:
        return false
    return cover_eta < 0.0 or pack_cost_s <= cover_eta + over_cover

static func path_length(p: PackedVector3Array) -> float:
    var l := 0.0
    for i in range(1, p.size()):
        l += p[i].distance_to(p[i - 1])
    return l

static func _ckey(map_root: Node, id: int) -> String:
    return "%d:%d" % [map_root.get_instance_id(), id]

static func claim(h, map_root: Node, id: int) -> void:
    _claims[_ckey(map_root, id)] = [h, h.team, Engine.get_physics_frames() + 30]

static func release(h, map_root: Node, id: int) -> void:
    if map_root == null or not is_instance_valid(map_root):
        return
    var k := _ckey(map_root, id)
    if _claims.has(k) and _claims[k][0] == h:
        _claims.erase(k)

## True when a living teammate (not `h`) currently claims pack `id`.
static func claimed_by_mate(h, map_root: Node, id: int) -> bool:
    var c = _claims.get(_ckey(map_root, id))
    if c == null:
        return false
    var o = c[0]
    if not is_instance_valid(o) or o.dead or int(c[2]) < Engine.get_physics_frames():
        _claims.erase(_ckey(map_root, id))
        return false
    return o != h and int(c[1]) == h.team

static func reset() -> void:   ## tests
    _claims.clear()

## Simulated landing of a pad launch: a 0.4 m sphere (hero feet) flies the launch with gravity and air
## control steering along `wish`, sliding along walls/lips like move_and_slide. Returns the first
## upward-facing map surface at least 1 m above the pad hit while falling, or Vector3.INF.
static func pad_landing(map_root: Node3D, start: Vector3, launch: Vector3, wish := Vector3.INF) -> Vector3:
    var space := map_root.get_world_3d().direct_space_state
    var dirh := Vector3(launch.x, 0, launch.z)
    dirh = dirh.normalized() if dirh.length() > 0.01 else Vector3.ZERO
    if wish == Vector3.INF:
        wish = dirh
    var sphere := SphereShape3D.new()
    sphere.radius = 0.4
    var q := PhysicsShapeQueryParameters3D.new()
    q.shape = sphere
    var ex: Array[RID] = []
    for hh in map_root.get_tree().get_nodes_in_group("heroes"):
        if hh is CollisionObject3D:
            ex.append(hh.get_rid())
    q.exclude = ex
    var up := Vector3(0, 0.45, 0)
    var p := start
    var v := launch
    var dt := 1.0 / 60.0
    for i in 240:
        v = Motion.step_velocity(v, wish, false, false, {}, dt)
        var motion := v * dt
        q.transform = Transform3D(Basis(), p + up)
        q.motion = motion
        var r := space.cast_motion(q)
        if r.size() < 2 or r[1] >= 1.0:
            p += motion
        else:
            p += motion * r[0]
            q.transform = Transform3D(Basis(), p + up + motion * (r[1] - r[0]))
            q.motion = Vector3.ZERO
            var info := space.get_rest_info(q)
            var n: Vector3 = info.get("normal", Vector3.UP)
            var floor_y = _floor_below(space, map_root, p) if n.y > 0.7 and v.y < 0.0 else null
            if floor_y != null:
                if floor_y > start.y + 1.0:
                    return Vector3(p.x, floor_y, p.z) + wish * 0.6   # a bit past the edge: inside the eroded navmesh
                return Vector3.INF          # came back down to the pad's level
            v -= n * minf(0.0, v.dot(n))    # slide along walls / lips / edges
        if p.y < start.y - 0.5:
            return Vector3.INF
    return Vector3.INF

## Height of a flat map surface right under foot point `p` (within 0.5 m), else null.
static func _floor_below(space: PhysicsDirectSpaceState3D, map_root: Node, p: Vector3):
    var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.3, 0), p - Vector3(0, 0.5, 0))
    var hit := space.intersect_ray(q)
    if hit.is_empty() or hit.normal.y < 0.7 or not (hit.collider is Node) or not map_root.is_ancestor_of(hit.collider):
        return null
    return hit.position.y

## Best landing over a few air-steering choices (straight, then turning up to 90 deg either way).
static func best_pad_landing(map_root: Node3D, start: Vector3, launch: Vector3) -> Vector3:
    var dirh := Vector3(launch.x, 0, launch.z)
    if dirh.length() < 0.01:
        return pad_landing(map_root, start, launch, Vector3.ZERO)
    dirh = dirh.normalized()
    for deg in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
        var e := pad_landing(map_root, start, launch, dirh.rotated(Vector3.UP, deg_to_rad(deg)))
        if e != Vector3.INF:
            return e
    return Vector3.INF

## Adds (once per map) a one-way NavigationLink3D per jump pad. Needs physics (call from a physics tick).
## Returns [{id, start, end}] (also stored as map meta "bot_pad_links").
static func ensure_pad_links(map_root: Node3D) -> Array:
    if map_root == null:
        return []
    if map_root.has_meta("bot_pad_links"):
        return map_root.get_meta("bot_pad_links")
    var out: Array = []
    var o := objects(map_root)
    if o != null:
        var holder := Node3D.new()
        holder.name = LINKS_NAME
        map_root.add_child(holder)
        for pad in o.pads:
            var end := best_pad_landing(map_root, pad.pos, pad.launch)
            if end == Vector3.INF:
                continue
            var l := NavigationLink3D.new()
            l.bidirectional = false
            l.start_position = pad.pos
            l.end_position = end
            holder.add_child(l)   # map-local == world (pickup/pad data is map-local, maps sit at the origin)
            out.append({"id": int(pad.id), "start": pad.pos, "end": end})
    map_root.set_meta("bot_pad_links", out)
    return out
