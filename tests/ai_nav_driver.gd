extends Node3D
## AI integration tests on the real map: navmesh bake, path around cover, bot reaching a goal
## behind cover, and low-health cover seeking.
const HERO := "res://src/heroes/archive/kestrel.json"
const MAP := "res://src/maps/arena01.json"
var results: Array = []
var done := false
var frame := 0
var map: Node3D
var walker: Hero
var hider: Hero
var enemy: Hero
var hider_brain: BotBrain
var goal := Vector3(0, 0, 4)
var reached_at := -1

class GoalSource:
    var brain: BotBrain
    var goal: Vector3
    func poll(h) -> InputFrame:
        var f := InputFrame.new()
        f.move = brain._follow(h, goal)
        var d: Vector3 = brain._move_world(h, f.move)
        brain._aim(h, f, d, 1.0 / 60.0, false)
        return f

func _rec(n: String, ok: bool, info: String) -> void:
    results.append([n, ok, info])

func _ready() -> void:
    map = MapLoader.build(MAP)
    add_child(map)
    var region := BotNav.ensure_region(map)
    var nm := region.navigation_mesh
    _rec("navmesh_baked", nm.get_polygon_count() > 10, "polygons=%d" % nm.get_polygon_count())
    _rec("region_reused", BotNav.ensure_region(map) == region, "")
    walker = _hero(0, Vector3(0, 0.2, 12))
    var gs := GoalSource.new()
    gs.brain = BotBrain.new({"use_abilities": false})
    gs.goal = goal
    walker.input_source = gs
    walker.yaw = 0.0
    enemy = _hero(1, Vector3(-2, 0.2, -8))
    hider = _hero(0, Vector3(-9, 0.2, -2))
    hider_brain = BotBrain.new({"use_abilities": false, "difficulty": "hard"})
    hider.input_source = hider_brain

func _hero(team: int, pos: Vector3) -> Hero:
    var h := Hero.from_def(HERO)
    h.set_team(team)
    h.spawn_point = pos
    add_child(h)
    h.global_position = pos
    return h

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    if frame == 30:
        var p := BotNav.path(walker, goal)
        var maxx := 0.0
        for v in p:
            maxx = maxf(maxx, absf(v.x))
        var m := get_world_3d().navigation_map
        _rec("path_goes_around_cover", p.size() >= 3 and maxx > 0.8, "points=%d max|x|=%.2f it=%d verts=%d closest=%s" % [p.size(), maxx, NavigationServer3D.map_get_iteration_id(m), map.get_node("BotNavRegion").navigation_mesh.get_vertices().size(), NavigationServer3D.map_get_closest_point(m, walker.global_position)])
        hider.health.hp = hider.health.max_hp * 0.2
    if reached_at < 0 and Vector2(walker.global_position.x - goal.x, walker.global_position.z - goal.z).length() < 0.8:
        reached_at = frame
    if frame == 300:
        _rec("bot_reaches_goal_behind_cover", reached_at > 0, "frame=%d pos=%s nav_used=%s" % [reached_at, walker.global_position, walker.input_source.brain.nav_used])
    if frame == 90:
        _rec("low_hp_enters_cover_state", hider_brain.state == "cover", "state=%s" % hider_brain.state)
    if frame == 270:
        var q := PhysicsRayQueryParameters3D.create(enemy.eye_position(), hider.global_position + Vector3(0, 1.0, 0))
        q.exclude = [enemy.get_rid()]
        var hit := get_world_3d().direct_space_state.intersect_ray(q)
        var hidden: bool = not hit.is_empty() and hit.collider != hider
        _rec("hides_out_of_enemy_sight", hidden and hider_brain.state == "cover", "pos=%s state=%s" % [hider.global_position, hider_brain.state])
        _rec("hider_alive", not hider.dead, "")
    if frame >= 300:
        done = true
