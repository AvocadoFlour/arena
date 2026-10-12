class_name SpawnPicker
extends RefCounted
## Chooses a spawn point that no living enemy can see.
## A candidate is "safe" when no enemy eye has line of sight to the spawn's head height.
## Among safe candidates the one farthest from the nearest enemy wins. Fallback when all
## are seen: fewest watching enemies, then farthest. With no enemies, returns cands[default_index].

const EYE := Vector3(0, 1.5, 0)

## los: Callable(from: Vector3, to: Vector3) -> bool (true = clear line of sight).
static func pick(cands: Array, enemy_eyes: Array, los: Callable, default_index := 0) -> Vector3:
    if cands.is_empty():
        return Vector3.ZERO
    if enemy_eyes.is_empty():
        return cands[default_index % cands.size()]
    var best: Vector3 = cands[0]
    var best_seen := 1 << 30
    var best_dist := -1.0
    for c in cands:
        var head: Vector3 = c + EYE
        var seen := 0
        var nearest := INF
        for e in enemy_eyes:
            nearest = minf(nearest, head.distance_to(e))
            if los.call(e, head):
                seen += 1
        if seen < best_seen or (seen == best_seen and nearest > best_dist):
            best = c
            best_seen = seen
            best_dist = nearest
    return best

## Physics line-of-sight against world collision (layer 1), ignoring the given bodies.
static func physics_los(space: PhysicsDirectSpaceState3D, exclude: Array[RID] = []) -> Callable:
    return func(from: Vector3, to: Vector3) -> bool:
        var q := PhysicsRayQueryParameters3D.create(from, to, 1, exclude)
        return space.intersect_ray(q).is_empty()

## Convenience for the spawner: picks for `hero` among `cands` using live enemies in group "heroes".
static func pick_for(hero: Node3D, cands: Array, default_index := 0) -> Vector3:
    var eyes: Array = []
    var ex: Array[RID] = []
    for h in hero.get_tree().get_nodes_in_group("heroes"):
        if h is CollisionObject3D:
            ex.append(h.get_rid())
        if h != hero and h.team != hero.team and not h.dead:
            eyes.append(h.eye_position())
    return pick(cands, eyes, physics_los(hero.get_world_3d().direct_space_state, ex), default_index)
