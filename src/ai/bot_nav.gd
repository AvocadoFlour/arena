class_name BotNav
extends RefCounted
## Navmesh support for bots (INTERFACES.md section 5 hook, owned by src/ai).
## Lazily adds a NavigationRegion3D under the map root and bakes it from the map's static
## colliders, so no map-loader change is needed. Falls back to direct steering until the
## navigation map has synced (one physics frame after the bake).

const REGION_NAME := "BotNavRegion"

## Finds the map root for a hero: a sibling node with the `spawns` meta (MapLoader.build output).
static func find_map_root(h: Node) -> Node3D:
    var p := h.get_parent()
    if p == null:
        return null
    for c in p.get_children():
        if c is Node3D and c.has_meta("spawns"):
            return c
    return null

static func make_navmesh(agent_radius: float = 0.5, agent_height: float = 2.0) -> NavigationMesh:
    var nm := NavigationMesh.new()
    nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
    nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
    nm.cell_size = 0.25
    nm.cell_height = 0.25
    nm.agent_radius = agent_radius
    nm.agent_height = agent_height
    nm.agent_max_climb = 0.5
    nm.agent_max_slope = 46.0
    return nm

## Returns the (possibly new) baked region under `map_root`. Synchronous bake (main thread).
static func ensure_region(map_root: Node3D) -> NavigationRegion3D:
    if map_root == null:
        return null
    var r := map_root.get_node_or_null(REGION_NAME) as NavigationRegion3D
    if r:
        return r
    var nm := make_navmesh()
    var src := NavigationMeshSourceGeometryData3D.new()
    NavigationServer3D.parse_source_geometry_data(nm, src, map_root)
    NavigationServer3D.bake_from_source_geometry_data(nm, src)
    r = NavigationRegion3D.new()
    r.name = REGION_NAME
    r.navigation_mesh = nm
    r.set_meta("static_src", src)      # parsed map geometry, reused for dynamic rebakes
    r.set_meta("dyn_sig", "")
    r.set_meta("version", 0)
    r.set_meta("checked_frame", -1)
    map_root.add_child(r)
    return r

## Dynamic obstacles: StaticBody3D boxes that are siblings of the map root (e.g. shield walls,
## which abilities add to the world node). Returns [{xform: Transform3D, size: Vector3}].
static func dynamic_boxes(map_root: Node3D) -> Array:
    var out: Array = []
    var world := map_root.get_parent() if map_root else null
    if world == null:
        return out
    for c in world.get_children():
        if c == map_root or not (c is StaticBody3D) or c.is_queued_for_deletion() or not c.is_inside_tree():
            continue
        if c.collision_layer & 1 == 0:
            continue
        for s in c.get_children():
            if s is CollisionShape3D and s.shape is BoxShape3D and not s.disabled:
                out.append({"xform": s.global_transform, "size": s.shape.size})
    return out

static func _sig(boxes: Array) -> String:
    var parts: PackedStringArray = []
    for b in boxes:
        var t: Transform3D = b.xform
        parts.append("%.1f,%.1f,%.1f,%.2f" % [t.origin.x, t.origin.y, t.origin.z, t.basis.get_euler().y])
    return ";".join(parts)

## Footprint corners (XZ) of a box obstacle, in `to_local` space (pure; unit-tested).
static func box_footprint(xform: Transform3D, size: Vector3) -> PackedVector3Array:
    var hx := size.x * 0.5
    var hz := size.z * 0.5
    var out := PackedVector3Array()
    for c in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]:
        out.append(xform * c)
    return out

## Rebakes the region when the set of dynamic obstacles changed (checked once per physics
## frame per region). Obstacles are projected obstructions, so the navmesh routes around them
## with agent-radius clearance. Returns the region's navmesh version (bumps on every rebake).
static func sync_dynamic(map_root: Node3D) -> int:
    var r := ensure_region(map_root)
    if r == null:
        return 0
    var fr := Engine.get_physics_frames()
    if int(r.get_meta("checked_frame")) == fr:
        return int(r.get_meta("version"))
    r.set_meta("checked_frame", fr)
    var boxes := dynamic_boxes(map_root)
    var sig := _sig(boxes)
    if sig == String(r.get_meta("dyn_sig")):
        return int(r.get_meta("version"))
    r.set_meta("dyn_sig", sig)
    var nm := make_navmesh()
    var src := NavigationMeshSourceGeometryData3D.new()
    src.merge(r.get_meta("static_src"))
    var inv := map_root.global_transform.affine_inverse()
    for b in boxes:
        var t: Transform3D = inv * b.xform
        var size: Vector3 = b.size
        var corners := box_footprint(t, size)
        var bottom := t.origin.y - size.y * 0.5
        src.add_projected_obstruction(corners, bottom, size.y, false)
    NavigationServer3D.bake_from_source_geometry_data(nm, src)
    r.navigation_mesh = nm
    r.set_meta("version", int(r.get_meta("version")) + 1)
    return int(r.get_meta("version"))

static func ready_for(h: Node3D) -> bool:
    var m := h.get_world_3d().navigation_map
    return NavigationServer3D.map_get_iteration_id(m) > 0

## Shortest navmesh path from the hero to `goal` (empty if nav not ready / unreachable).
static func path(h: Node3D, goal: Vector3) -> PackedVector3Array:
    var m := h.get_world_3d().navigation_map
    if NavigationServer3D.map_get_iteration_id(m) == 0:
        return PackedVector3Array()
    var to := NavigationServer3D.map_get_closest_point(m, goal)
    return NavigationServer3D.map_get_path(m, h.global_position, to, true)

## Cover blocks of a map root: [{pos: Vector3, half: Vector3, height: float}], tallest-relevant first.
static func cover_blocks(map_root: Node3D) -> Array:
    var out: Array = []
    if map_root == null:
        return out
    for c in map_root.get_children():
        if not (c is StaticBody3D) or not is_cover(c):
            continue
        for s in c.get_children():
            if s is CollisionShape3D and s.shape is BoxShape3D:
                var size: Vector3 = s.shape.size
                out.append({"pos": c.global_position, "half": size * 0.5, "height": size.y, "node": c})
    return out

## Cover = map block of kind "cover": meta `kind` (MapLoader), else name prefix `cover` / `cover_NN`.
static func is_cover(n: Node) -> bool:
    if n.has_meta("kind"):
        return String(n.get_meta("kind")) == "cover"
    return String(n.name).to_lower().begins_with("cover")

## Point behind a cover block, on the far side from `threat` (pure; unit-tested).
static func cover_point(block: Dictionary, threat: Vector3, clearance: float = 0.9) -> Vector3:
    var p: Vector3 = block.pos
    var half: Vector3 = block.half
    var away := Vector3(p.x - threat.x, 0, p.z - threat.z)
    if away.length() < 0.01:
        away = Vector3(0, 0, 1)
    away = away.normalized()
    # distance from centre to the box edge along `away`, plus clearance
    var tx := half.x / maxf(absf(away.x), 0.001)
    var tz := half.z / maxf(absf(away.z), 0.001)
    var d := minf(tx, tz) + clearance
    return Vector3(p.x + away.x * d, p.y - half.y, p.z + away.z * d)

## Peek position for a block: beside the cover point, stepped out past the block's side edge
## (`side` = +1/-1 along the tangent to the threat direction) so the threat is in view (pure; unit-tested).
static func peek_point(block: Dictionary, threat: Vector3, side: float, clearance: float = 0.9) -> Vector3:
    var cp := cover_point(block, threat, clearance)
    var p: Vector3 = block.pos
    var half: Vector3 = block.half
    var away := Vector3(p.x - threat.x, 0, p.z - threat.z)
    if away.length() < 0.01:
        away = Vector3(0, 0, 1)
    away = away.normalized()
    var tan := Vector3(-away.z, 0, away.x) * signf(side if side != 0.0 else 1.0)
    var lateral := absf(half.x * tan.x) + absf(half.z * tan.z)
    return cp + tan * (lateral + clearance)

## Like best_cover, but returns the block dictionary (with "node" when built from a map) or null.
static func best_cover_block(blocks: Array, from: Vector3, threat: Vector3, min_height: float = 1.4, max_dist: float = INF):
    var best = null
    var best_s := INF
    for b in blocks:
        if float(b.height) < min_height:
            continue
        if b.has("node") and not is_instance_valid(b.node):
            continue
        var cp := cover_point(b, threat)
        var d_me := Vector2(cp.x - from.x, cp.z - from.z).length()
        var d_th := Vector2(cp.x - threat.x, cp.z - threat.z).length()
        if d_th < d_me or d_th < 3.0 or d_me > max_dist:
            continue
        if d_me < best_s:
            best_s = d_me
            best = b
    return best

## Best cover for a hero at `from` hiding from `threat`: blocks at least `min_height` tall,
## whose cover point is closer to us than to the threat, scored by travel distance.
static func best_cover(blocks: Array, from: Vector3, threat: Vector3, min_height: float = 1.4):
    var best = null
    var best_s := INF
    for b in blocks:
        if float(b.height) < min_height:
            continue
        var cp := cover_point(b, threat)
        var d_me := Vector2(cp.x - from.x, cp.z - from.z).length()
        var d_th := Vector2(cp.x - threat.x, cp.z - threat.z).length()
        if d_th < d_me or d_th < 3.0:
            continue
        if d_me < best_s:
            best_s = d_me
            best = cp
    return best
