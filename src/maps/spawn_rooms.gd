class_name SpawnRooms
extends Node3D
## Protected spawn rooms (map root child "SpawnRooms"). Data (map JSON):
##   "spawn_rooms": {"<team>": {"pos","size","barriers"?: [{"pos","size"}]}}   rooms with walls (arena02)
##   "spawn_areas": {"<team>": [{"pos","size"}]}   open protected areas (arena01; kept out of spawn_rooms because
##                  GameConfig.allies_for treats a team-0 spawn room as a team map)
##   "spawn_shield": s   (optional, default 2.0) spawn shield duration
##   theme "team_colors": ["#hex", "#hex"]   barrier colours (default soft blue / red)
## Each team owns keep-out volumes = its room box + its barrier boxes (+ its open areas). Enemies of that team can't
## be inside them; the owner passes freely. No physics bodies: hero rays (hitscan, projectiles, bot LOS) use the
## default all-layers mask, so a team-layer StaticBody would also stop bullets and sight. Instead the host resolves
## positions every fixed tick (push-out to the face nearest the hero's previous position, inward velocity zeroed),
## deterministic and independent of physics callback order. Collision golden unchanged.
## Host/offline only; clients use `resolve()` for prediction (pure function of map data).
## Spawn shield hook (host): a hero that becomes alive (spawn, respawn, hero swap) gets a shield for `shield_time` s;
## if it spawned inside its own room/area the shield ends early when it leaves. Query `is_shielded(hero)`,
## `shield_left(hero)`, `in_own_room(hero)`; signals below; `Events.spawn_shield` too once core adds it.

signal spawn_shield_changed(ev: Dictionary)   ## {hero, active: bool, left: float, reason: "spawn"|"timeout"|"left_room"|"died"}
signal own_room_changed(ev: Dictionary)       ## {hero, inside: bool}
signal pushed_out(ev: Dictionary)             ## {hero, team (room owner), pos}

const TICK := 1.0 / 60.0
const CLEARANCE := 3.0      ## keep-out reaches this far above a volume's top (no hopping over a door panel)
const EPS := 0.01
const DEFAULT_RADIUS := 0.4
const DEFAULT_COLORS := ["#5a8ad8", "#e06a6a"]

var volumes: Array = []     ## [{team, kind: room|barrier|area, aabb: AABB}] in data order
var shield_time := 2.0
var authority_override := -1   ## tests: -1 ask Net, 0 client, 1 host
var _st := {}                  ## hero instance id -> {alive, shield (ticks), from_room, inside, prev: Vector3}

static func has_data(d: Dictionary) -> bool:
    return not d.get("spawn_rooms", {}).is_empty() or not d.get("spawn_areas", {}).is_empty()

static func from_def(d: Dictionary, theme: Dictionary = {}) -> SpawnRooms:
    var s := SpawnRooms.new()
    s.name = "SpawnRooms"
    s.process_physics_priority = 100   # after heroes moved this tick
    s.shield_time = float(d.get("spawn_shield", 2.0))
    var rooms: Dictionary = d.get("spawn_rooms", {})
    var teams: Array = rooms.keys()
    teams.sort()
    for t in teams:
        var r: Dictionary = rooms[t]
        s.volumes.append({"team": int(t), "kind": "room", "aabb": _box(r.pos, r.size)})
        for b in r.get("barriers", []):
            s.volumes.append({"team": int(t), "kind": "barrier", "aabb": _box(b.pos, b.size)})
    var areas: Dictionary = d.get("spawn_areas", {})
    teams = areas.keys()
    teams.sort()
    for t in teams:
        for a in areas[t]:
            s.volumes.append({"team": int(t), "kind": "area", "aabb": _box(a.pos, a.size)})
    s._build_visuals(theme if not theme.is_empty() else d.get("theme", {}))
    return s

static func _box(p, sz) -> AABB:
    var size := Vector3(sz[0], sz[1], sz[2])
    return AABB(Vector3(p[0], p[1], p[2]) - size * 0.5, size)

func is_authority() -> bool:
    if authority_override >= 0:
        return authority_override == 1
    var ml := Engine.get_main_loop()
    if ml is SceneTree:
        var net: Node = (ml as SceneTree).root.get_node_or_null("Net")
        if net != null and net.has_method("is_authority"):
            return bool(net.is_authority())
    return true

# ------------------------------------------------------------------ queries (pure)

## Team owning the protected volume at pos (-1 = none). Rooms/areas/barriers, xz + vertical clearance.
func owner_at(pos: Vector3, radius := 0.0) -> int:
    for v in volumes:
        if _inside(v.aabb, pos, radius):
            return v.team
    return -1

func in_team_volume(team: int, pos: Vector3) -> bool:
    for v in volumes:
        if v.team == team and _inside(v.aabb, pos, 0.0):
            return true
    return false

func in_own_room(hero) -> bool:
    return in_team_volume(int(hero.team), hero.global_position)

func teams() -> Array:
    var out: Array = []
    for v in volumes:
        if not out.has(v.team):
            out.append(v.team)
    return out

static func _inside(b: AABB, p: Vector3, r: float) -> bool:
    return p.x > b.position.x - r and p.x < b.end.x + r and p.z > b.position.z - r and p.z < b.end.z + r \
        and p.y >= b.position.y - 0.5 and p.y <= b.end.y + CLEARANCE

## Pure keep-out rule (host step and client prediction use the same one): a hero of `team` at `pos` (previous
## tick at `prev`) is moved out of every enemy volume (grown by `radius`) to the face nearest `prev`, and the
## velocity component pointing back in is zeroed. Returns [pos, vel, pushed_by_team (-1 = not pushed)].
func resolve(team: int, pos: Vector3, vel: Vector3, prev: Vector3, radius := DEFAULT_RADIUS) -> Array:
    if team < 0:
        return [pos, vel, -1]
    var by := _enemy_at(team, pos, radius)
    if by < 0:
        return [pos, vel, -1]
    # Exit candidates: faces of the containing enemy volumes; a candidate that lands in another enemy volume
    # expands with that volume's faces (overlapping room + door boxes). Pick the valid one nearest to `prev`.
    var frontier: Array = [pos]
    var best := pos
    var bd := INF
    for _depth in 3:
        var nxt: Array = []
        for p in frontier:
            for v in volumes:
                if v.team == team or not _inside(v.aabb, p, radius):
                    continue
                var bx: AABB = v.aabb
                for c in [Vector3(bx.position.x - radius - EPS, p.y, p.z), Vector3(bx.end.x + radius + EPS, p.y, p.z),
                        Vector3(p.x, p.y, bx.position.z - radius - EPS), Vector3(p.x, p.y, bx.end.z + radius + EPS)]:
                    if _enemy_at(team, c, radius) >= 0:
                        nxt.append(c)
                        continue
                    var dd: float = Vector2(c.x - prev.x, c.z - prev.z).length_squared()
                    if dd < bd - 1e-6:
                        bd = dd
                        best = c
        if bd < INF or nxt.is_empty():
            break
        frontier = nxt
    var dlt := best - pos
    for ax in [0, 2]:
        if absf(dlt[ax]) > 0.0 and vel[ax] * dlt[ax] < 0.0:   # moving back into the volume
            vel[ax] = 0.0
    return [best, vel, by]

func _enemy_at(team: int, pos: Vector3, radius: float) -> int:
    for v in volumes:
        if v.team != team and _inside(v.aabb, pos, radius):
            return v.team
    return -1

# ------------------------------------------------------------------ host tick

func _physics_process(_dt: float) -> void:
    if is_authority():
        step(get_tree().get_nodes_in_group("heroes"))

## One fixed host tick. heroes: objects with team, dead, global_position, velocity (def.collider.radius optional).
func step(heroes: Array) -> void:
    if not is_authority():
        return
    var seen := {}
    for h in heroes:
        var id: int = h.get_instance_id()
        seen[id] = true
        if not _st.has(id):
            _st[id] = {"alive": false, "shield": 0, "from_room": false, "inside": false, "prev": h.global_position}
        var s: Dictionary = _st[id]
        if h.dead:
            if s.shield > 0:
                s.shield = 0
                _shield_ev(h, false, 0.0, "died")
            s.alive = false
            s.prev = h.global_position
            continue
        if not s.alive:   # (re)spawned: the hero's own position is trusted for this tick
            s.alive = true
            s.prev = h.global_position
            s.from_room = in_team_volume(int(h.team), h.global_position)
            s.shield = int(round(shield_time * 60.0))
            if s.shield > 0:
                _shield_ev(h, true, shield_time, "spawn")
        var r := resolve(int(h.team), h.global_position, h.velocity, s.prev, _radius(h))
        if r[2] >= 0:
            h.global_position = r[0]
            h.velocity = r[1]
            pushed_out.emit({"hero": h, "team": r[2], "pos": r[0]})
        s.prev = h.global_position
        var inside := in_team_volume(int(h.team), h.global_position)
        if inside != s.inside:
            s.inside = inside
            own_room_changed.emit({"hero": h, "inside": inside})
        if s.shield > 0:
            s.shield -= 1
            if s.from_room and not inside:
                s.shield = 0
                _shield_ev(h, false, 0.0, "left_room")
            elif s.shield == 0:
                _shield_ev(h, false, 0.0, "timeout")
    for id in _st.keys():
        if not seen.has(id):
            _st.erase(id)

func is_shielded(hero) -> bool:
    var s = _st.get(hero.get_instance_id())
    return s != null and int(s.shield) > 0 and not hero.dead

func shield_left(hero) -> float:
    var s = _st.get(hero.get_instance_id())
    return 0.0 if s == null else float(s.shield) * TICK

func _shield_ev(h, active: bool, left: float, reason: String) -> void:
    var ev := {"hero": h, "active": active, "left": left, "reason": reason}
    spawn_shield_changed.emit(ev)
    var ml := Engine.get_main_loop()
    var bus: Node = (ml as SceneTree).root.get_node_or_null("Events") if ml is SceneTree else null
    if bus != null and bus.has_signal("spawn_shield"):
        bus.emit_signal("spawn_shield", ev)

static func _radius(h) -> float:
    var d = h.get("def")
    if d is Dictionary and d.get("collider") is Dictionary:
        return float(d.collider.get("radius", DEFAULT_RADIUS))
    return DEFAULT_RADIUS

# ------------------------------------------------------------------ visuals (toon, team colour, no collision)

## Barrier panels: a vertical sheet with a soft vertical alpha fade (strong at the floor, faint on top), a thin
## opaque team-colour frame (top bar, posts, floor strip) with merged black hulls. Rooms draw panels on their
## barrier boxes only (the room itself has walls); open areas draw a low fence on all four sides.
## Per team: 3 merged meshes (fill, frame, hulls). Kept in low quality (gameplay readability).
func _build_visuals(theme: Dictionary) -> void:
    var cols: Array = theme.get("team_colors", DEFAULT_COLORS)
    var w := float(theme.get("outline_width", 0.08)) * 0.5
    var oc := Color(String(theme.get("outline_color", "#16161e")))
    var per_team := {}
    for v in volumes:
        if v.kind == "room":
            continue
        if not per_team.has(v.team):
            per_team[v.team] = []
        var b: AABB = v.aabb
        if v.kind == "barrier":
            per_team[v.team].append(_panel_of(b, b.size.y))
        else:
            var h := minf(b.size.y, 1.2)
            var y0 := b.position.y
            for p in [[Vector3(b.position.x, y0, b.position.z), Vector3(b.end.x, y0, b.position.z)],
                    [Vector3(b.end.x, y0, b.position.z), Vector3(b.end.x, y0, b.end.z)],
                    [Vector3(b.end.x, y0, b.end.z), Vector3(b.position.x, y0, b.end.z)],
                    [Vector3(b.position.x, y0, b.end.z), Vector3(b.position.x, y0, b.position.z)]]:
                per_team[v.team].append({"a": p[0], "b": p[1], "h": h})
    var tkeys: Array = per_team.keys()
    tkeys.sort()
    for t in tkeys:
        var c := Color(String(cols[clampi(t, 0, cols.size() - 1)]))
        var fill := SurfaceTool.new()
        fill.begin(Mesh.PRIMITIVE_TRIANGLES)
        var frame := SurfaceTool.new()
        frame.begin(Mesh.PRIMITIVE_TRIANGLES)
        var hull := SurfaceTool.new()
        hull.begin(Mesh.PRIMITIVE_TRIANGLES)
        for pn in per_team[t]:
            _add_panel(fill, frame, hull, pn, c, w)
        var n := Node3D.new()
        n.name = "barriers_team%d" % t
        n.set_meta("panel_count", per_team[t].size())
        add_child(n)
        n.add_child(_mi("Fill", fill.commit(), _fill_mat()))
        n.add_child(_mi("Frame", frame.commit(), _flat_mat(c.lerp(Color.WHITE, 0.25))))
        var hm := _flat_mat(oc)
        hm.cull_mode = BaseMaterial3D.CULL_FRONT
        n.add_child(_mi("Outlines", hull.commit(), hm))

## Thin barrier box -> panel along its long horizontal axis, through its centre.
static func _panel_of(b: AABB, h: float) -> Dictionary:
    var c := b.get_center()
    var y0 := b.position.y
    if b.size.x <= b.size.z:
        return {"a": Vector3(c.x, y0, b.position.z), "b": Vector3(c.x, y0, b.end.z), "h": h}
    return {"a": Vector3(b.position.x, y0, c.z), "b": Vector3(b.end.x, y0, c.z), "h": h}

func _add_panel(fill: SurfaceTool, frame: SurfaceTool, hull: SurfaceTool, pn: Dictionary, c: Color, w: float) -> void:
    var a: Vector3 = pn.a
    var b: Vector3 = pn.b
    var h: float = pn.h
    var up := Vector3(0, h, 0)
    var lo := Color(c, 0.34)
    var hi := Color(c, 0.04)
    for tri in [[a, b, b + up], [a, b + up, a + up]]:
        for p in tri:
            fill.set_color(hi if p.y > a.y + 0.5 * h else lo)
            fill.add_vertex(p)
    var dir := (b - a)
    var len := dir.length()
    var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))   # local x along the panel
    var mid := (a + b) * 0.5
    var t := 0.08
    var bars := [
        [mid + Vector3(0, h, 0), Vector3(len, t, t)],            # top bar
        [mid + Vector3(0, 0.02, 0), Vector3(len, 0.04, 0.24)],   # floor strip
        [a + Vector3(0, h * 0.5, 0), Vector3(t, h, t)],          # posts
        [b + Vector3(0, h * 0.5, 0), Vector3(t, h, t)]]
    for bar in bars:
        var bm := BoxMesh.new()
        bm.size = bar[1]
        frame.append_from(bm, 0, Transform3D(basis, bar[0]))
        var hm := BoxMesh.new()
        hm.size = bar[1] + Vector3.ONE * (2.0 * w)
        hull.append_from(hm, 0, Transform3D(basis, bar[0]))

static func _mi(n: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.name = n
    mi.mesh = mesh
    mi.material_override = mat
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return mi

static func _fill_mat() -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.vertex_color_use_as_albedo = true
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    return m

static func _flat_mat(c: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = c
    return m
