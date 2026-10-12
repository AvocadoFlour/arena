extends Node3D
## AI integration: shield walls are carved into the navmesh (bots path around them), and team play
## (support bot heals a hurt ally; a player-team heal beam targets an allied bot).
const MAP := "res://src/maps/arena01.json"
var results: Array = []
var done := false
var frame := 0
var map: Node3D
var walker: Hero
var gs
var wall_ab
var goal := Vector3(-3.5, 0, 2)
var reached_at := -1
var v0 := 0
var healer: Hero
var healer_brain: BotBrain
var hurt_ally: Hero
var ally_hp0 := 0.0
var player_support: Hero

class GoalSource:
    var brain: BotBrain
    var goal: Vector3
    func poll(h) -> InputFrame:
        var f := InputFrame.new()
        f.move = brain._follow(h, goal)
        brain._aim(h, f, brain._move_world(h, f.move), 1.0 / 60.0, false)
        return f

func _rec(n: String, ok: bool, info: String) -> void:
    results.append([n, ok, info])

func _hero(def: String, team: int, pos: Vector3) -> Hero:
    var h := Hero.from_def("res://src/heroes/%s.json" % def)
    h.set_team(team)
    h.spawn_point = pos
    add_child(h)
    h.global_position = pos
    return h

func _ready() -> void:
    map = MapLoader.build(MAP)
    add_child(map)
    var region := BotNav.ensure_region(map)
    var covers := BotNav.cover_blocks(map)
    _rec("cover_blocks_found_with_kind_NN_names", covers.size() == 8, "found=%d names e.g. %s" % [covers.size(), map.get_child(5).name])
    _rec("navmesh_still_bakes_walls_and_blocks", region.navigation_mesh.get_polygon_count() > 50, "polygons=%d" % region.navigation_mesh.get_polygon_count())
    walker = _hero("kestrel", 0, Vector3(-3.5, 0.2, 17))
    gs = GoalSource.new()
    gs.brain = BotBrain.new({"use_abilities": false})
    gs.goal = goal
    walker.input_source = gs
    var r := _hero("rampart", 0, Vector3(-3.5, 0.2, 13))
    r.yaw = 0.0
    r.rotation.y = 0.0
    wall_ab = r.abilities["ability2"]
    wall_ab.activate()
    r.global_position = Vector3(15, 0.2, 15)
    v0 = int(region.get_meta("version"))
    # team play: willow bot (team 0) + hurt kestrel ally nearby; enemy far away out of sight
    hurt_ally = _hero("kestrel", 0, Vector3(10, 0.2, 2))
    hurt_ally.health.hp = hurt_ally.health.max_hp * 0.4
    ally_hp0 = hurt_ally.health.hp
    healer = _hero("willow", 0, Vector3(10, 0.2, -4))
    healer_brain = BotBrain.new({"difficulty": "hard"})
    healer.input_source = healer_brain
    healer.yaw = PI   # facing away: must turn to the ally
    # player-team support heal beam (no brain) aimed at the allied bot picks it as target
    player_support = _hero("willow", 0, Vector3(-12, 0.2, -10))
    var ally_bot := _hero("kestrel", 0, Vector3(-12, 0.2, -16))
    ally_bot.input_source = BotBrain.new({"use_abilities": false})
    player_support.yaw = 0.0
    player_support.pitch = -0.08
    var picked = player_support.abilities["ability1"].pick_target()
    _rec("player_heal_beam_targets_allied_bot", picked == ally_bot, "picked=%s" % [picked.display_name if picked else "null"])

func _crosses_wall(p: PackedVector3Array) -> bool:
    # wall: centre (-3.5, z~11.4), 4 m wide along x, thin along z
    for i in range(p.size() - 1):
        var a := p[i]
        var b := p[i + 1]
        if (a.z - 11.4) * (b.z - 11.4) <= 0.0 and absf(b.z - a.z) > 0.001:
            var t := (11.4 - a.z) / (b.z - a.z)
            var x := lerpf(a.x, b.x, t)
            if absf(x + 3.5) < 2.0:
                return true
    return false

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    if reached_at < 0 and Vector2(walker.global_position.x - goal.x, walker.global_position.z - goal.z).length() < 0.8:
        reached_at = frame
    if frame == 10:
        var v := int(map.get_node(BotNav.REGION_NAME).get_meta("version"))
        _rec("shield_wall_triggers_rebake", v > v0 or v > 0, "version=%d" % v)
        var p := BotNav.path(walker, goal)
        _rec("path_avoids_active_shield_wall", p.size() >= 2 and not _crosses_wall(p), "points=%d" % p.size())
    if frame == 150:
        _rec("healer_supports_hurt_ally", hurt_ally.health.hp > ally_hp0 + 30.0, "hp %.0f -> %.0f state=%s" % [ally_hp0, hurt_ally.health.hp, healer_brain.state])
    if frame == 280:
        _rec("bot_reaches_goal_before_wall_expires", reached_at > 0 and reached_at < 300, "frame=%d (wall lasts 300) pos=%s" % [reached_at, walker.global_position])
    if frame == 340:
        var v := int(map.get_node(BotNav.REGION_NAME).get_meta("version"))
        _rec("wall_expiry_restores_navmesh", not wall_ab.active() and v >= 2, "version=%d active=%s" % [v, wall_ab.active()])
        done = true
