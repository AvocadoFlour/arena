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
    map_root.add_child(r)
    return r

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
        if not (c is StaticBody3D) or not String(c.name).to_lower().contains("cover"):
            continue
        for s in c.get_children():
            if s is CollisionShape3D and s.shape is BoxShape3D:
                var size: Vector3 = s.shape.size
                out.append({"pos": c.global_position, "half": size * 0.5, "height": size.y})
    return out

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
