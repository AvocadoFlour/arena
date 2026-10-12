extends Node3D
## Lead integration test: AI navmesh on arena02 (multi-level, ramps) and bots vs Rampart shield walls.
## Phase 1 (arena02): bot paths from red spawn up a ramp onto the west platform (y=4).
## Phase 2 (arena01): a shield wall drops across a bot's path; bot must still reach its goal.
var results: Array = []
var done := false
var frame := 0
var map: Node3D
var walker: Hero
var gs
var goal := Vector3.ZERO
var reached_at := -1
var phase := 1
var wall_frame := -1
var wall_ab

class GoalSource:
    var brain: BotBrain
    var goal: Vector3
    func poll(h) -> InputFrame:
        var f := InputFrame.new()
        f.move = brain._follow(h, goal)
        var d: Vector3 = brain._move_world(h, f.move)
        brain._aim(h, f, d, 1.0 / 60.0, false)
        if h.is_on_floor() and f.move.length() > 0.1 and Vector2(h.velocity.x, h.velocity.z).length() < 0.5 and randf() < 0.05:
            f.jump = true
        return f

func _rec(n: String, ok: bool, info: String) -> void:
    results.append([n, ok, info])

func _load(path: String) -> void:
    if map:
        for c in get_children():
            c.queue_free()
    map = MapLoader.build(path)
    add_child(map)
    var region := BotNav.ensure_region(map)
    _rec("navmesh_baked_" + path.get_file().get_basename(), region.navigation_mesh.get_polygon_count() > 10, "polygons=%d" % region.navigation_mesh.get_polygon_count())

func _walker(pos: Vector3, g: Vector3) -> void:
    walker = Hero.from_def("res://src/heroes/the_best.json")
    walker.set_team(1)
    add_child(walker)
    walker.global_position = pos
    walker.spawn_point = pos
    gs = GoalSource.new()
    gs.brain = BotBrain.new({"use_abilities": false})
    gs.goal = g
    walker.input_source = gs
    goal = g
    reached_at = -1

func _ready() -> void:
    _load("res://src/maps/arena02.json")
    _walker(Vector3(-4, 0.2, -27), Vector3(-28, 4.0, 2))

func _near() -> bool:
    return Vector2(walker.global_position.x - goal.x, walker.global_position.z - goal.z).length() < 1.2 and absf(walker.global_position.y - goal.y) < 1.0

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    if reached_at < 0 and walker and _near():
        reached_at = frame
    if phase == 1:
        if frame == 20:
            var p := BotNav.path(walker, goal)
            var top := -INF
            for v in p:
                top = maxf(top, v.y)
            _rec("arena02_path_climbs_to_platform", p.size() >= 2 and top > 3.5, "points=%d max_y=%.2f" % [p.size(), top])
        if frame == 1200 or reached_at > 0:
            _rec("arena02_bot_reaches_upper_level", reached_at > 0, "frame=%d pos=%s nav_used=%s" % [reached_at, walker.global_position, gs.brain.nav_used])
            phase = 2
            frame = 0
            _load("res://src/maps/arena01.json")
            _walker(Vector3(-3.5, 0.2, 17), Vector3(-3.5, 0.2, 2))
            var r := Hero.from_def("res://src/heroes/cob.json")
            r.set_team(0)
            add_child(r)
            r.global_position = Vector3(-3.5, 0.2, 13)
            r.yaw = 0.0
            r.rotation.y = 0.0
            r.input_source = null
            wall_ab = r.abilities["ability2"]
            _rec("shield_wall_deployed_on_path", wall_ab.activate(), "")
            r.global_position = Vector3(15, 0.2, 15)
            r.spawn_point = r.global_position
    else:
        if frame == 200:
            _rec("bot_not_through_wall_while_up", reached_at < 0 or wall_ab.active() == false or walker.global_position.z < 11.0, "z=%.2f wall_active=%s" % [walker.global_position.z, wall_ab.active()])
        if frame == 900 or (reached_at > 0 and frame > 10):
            _rec("bot_reaches_goal_despite_shield_wall", reached_at > 0, "frame=%d (wall lasts 300) pos=%s" % [reached_at, walker.global_position])
            done = true
