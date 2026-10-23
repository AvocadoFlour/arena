extends Node3D
## AI integration (arena01, breakable low walls cover_?? at (+-12, 0.75, 10), 300 HP):
## A: a hiding bot whose cover block is broken drops it and picks new cover at once; the navmesh
##    rebakes and paths through the old footprint.
## B: an enemy hides behind a breakable wall. A shooter with breach_time (normal) shoots the wall
##    down and then hits the enemy; the same seed with breach_time 0 (control) does not.
const BOT := "res://src/heroes/cob.json"
const SHOOTER := "res://src/heroes/tomo.json"   # hitscan that still breaks a 300 HP wall inside breach_time; Twin Tails' gun is 6
const WALL := Vector3(-12, 0.75, 10)
var results: Array = []
var done := false
var frame := 0
var run_seed := -1
var phase := 1
var map: Node3D
var bot: Hero
var brain: BotBrain
var enemy: Hero
var broke_at := -1
var old_block = null
var repick_frames := -1
var ver0 := -1
var rebake_frames := -1
var path_through := false
var wall_node = null
var had_wall := false
var forced := false
var hits := {2: 0.0, 3: 0.0}
var broken := {2: false, 3: false}
var breach_frames := {2: 0, 3: 0}
var wall_dmg := {2: 0.0, 3: 0.0}

func _rec(n: String, ok: bool, info: String) -> void:
    results.append([n, ok, info])

func _seed() -> int:
    return run_seed if run_seed >= 0 else 4242

func _hero(path: String, team: int, pos: Vector3, yaw: float) -> Hero:
    var h := Hero.from_def(path)
    h.set_team(team)
    add_child(h)
    h.global_position = pos
    h.spawn_point = pos
    h.yaw = yaw
    h._rng.seed = hash([_seed(), path, team])
    return h

func _load() -> void:
    for c in get_children():
        c.queue_free()
    map = MapLoader.build("res://src/maps/arena01.json")
    add_child(map)
    wall_node = null
    for n in map.find_children("*", "", true, false):
        if n.is_in_group("destructible") and n.global_position.distance_to(WALL) < 0.5:
            wall_node = n
    had_wall = wall_node != null

func _ready() -> void:
    Events.damage_dealt.connect(_on_dmg)
    _start_a()

func _start_a() -> void:
    _load()
    bot = _hero(BOT, 0, Vector3(-12, 0.2, 5), PI)
    brain = BotBrain.new({"difficulty": "hard", "use_abilities": false, "escort_allies": false, "bounds": 17.0, "low_hp_frac": 1.01, "team_play": false})
    brain._rng.seed = hash([_seed(), "a"])
    bot.input_source = brain
    enemy = _hero(SHOOTER, 1, Vector3(-12, 0.2, 20), 0.0)   # stands still, in sight across the wall
    enemy.damage_scale = 0.2

func _start_b(breach: bool) -> void:
    _load()
    bot = _hero(SHOOTER, 0, Vector3(-12, 0.2, 0), PI)
    var p := {"difficulty": "normal", "use_abilities": false, "escort_allies": false, "seek_cover": false, "bounds": 17.0, "team_play": false}
    if not breach:
        p["breach_time"] = 0.0
    brain = BotBrain.new(p)
    brain._rng.seed = hash([_seed(), "b"])
    bot.input_source = brain
    bot.extra_spread_deg = brain.spread_deg
    enemy = _hero(BOT, 1, Vector3(-7, 0.2, 13), 0.0)   # visible first, then ducks behind the wall
    enemy.damage_scale = 0.0

func _on_dmg(ev: Dictionary) -> void:
    if phase >= 2 and is_instance_valid(enemy) and ev.target == enemy and ev.source == bot:
        hits[phase] += ev.amount

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    if phase == 1:
        _phase_a()
    elif phase in [2, 3]:
        if frame == 45:
            enemy.global_position = Vector3(-12, 0.2, 12.5)
        if brain.breaching:
            breach_frames[phase] += 1
        if frame % 60 == 0 and OS.get_environment("AI_DEBUG") != "":
            print("ph%d f%d state %s tgt %s lost %.2f breach %s wall %s" % [phase, frame, brain.state, brain.target == enemy, brain._lost, brain.breaching, wall_node.hp if is_instance_valid(wall_node) else -1])
            var q := PhysicsRayQueryParameters3D.create(bot.eye_position(), enemy.global_position + Vector3(0, 1.1, 0))
            q.exclude = [bot.get_rid()]
            var hit := bot.get_world_3d().direct_space_state.intersect_ray(q)
            print("   bot %s hit %s" % [bot.global_position, hit.get("collider")])
        if had_wall and not is_instance_valid(wall_node):   # (a freed object compares == null in Godot 4)
            broken[phase] = true
        if frame == 600:
            wall_dmg[phase] = 300.0 if broken[phase] else 300.0 - float(wall_node.hp)
            if phase == 2:
                phase = 3
                frame = 0
                _start_b(false)
            else:
                # per run: the breacher spends its no-LOS trigger time on the wall, the control does not.
                # Enemy damage is compared over the seeds in tests/ai_destruct_run.gd (flanking makes single runs noisy).
                _rec("shoots_breakable_cover_hider", breach_frames[2] > 30 and wall_dmg[2] >= wall_dmg[3] + 50.0, "wall damage %.0f vs control %.0f (broken %s/%s), breaching %d f, enemy dmg %.0f vs %.0f" % [wall_dmg[2], wall_dmg[3], broken[2], broken[3], breach_frames[2], hits[2], hits[3]])
                _rec("control_never_breaches", breach_frames[3] == 0, "")
                Events.damage_dealt.disconnect(_on_dmg)
                done = true

func _phase_a() -> void:
    if frame == 1:
        _rec("breakable_wall_found", had_wall, "cover block at %s in group destructible" % WALL)
    if not forced and brain.state == "cover" and brain._cover_block != null:
        # pin the session to the breakable wall (the scored pick varies by seed; this test is about the break)
        for b in BotNav.cover_blocks(map):
            if b.get("node") == wall_node:
                brain._cover_block = b
                brain._cover = BotNav.cover_point(b, enemy.global_position)
                forced = true
    if broke_at < 0 and forced and brain.state == "cover" and brain._cphase == "hide" and brain._cover_block != null:
        var n = brain._cover_block.get("node")
        if is_instance_valid(n) and n.is_in_group("destructible"):
            old_block = brain._cover_block
            ver0 = _ver()
            n.take_damage(99999.0)
            broke_at = frame
    if broke_at > 0:
        if repick_frames < 0 and (brain._cover_block != old_block or brain.state != "cover"):
            repick_frames = frame - broke_at
        if rebake_frames < 0 and _ver() > ver0:
            rebake_frames = frame - broke_at
        if rebake_frames >= 0 and frame - broke_at == rebake_frames + 10:   # nav map syncs a few frames after a bake
            var m: RID = bot.get_world_3d().navigation_map
            var p := NavigationServer3D.map_get_path(m, Vector3(-12, 0.2, 7), Vector3(-12, 0.2, 13), true)
            var length := 0.0
            for k in range(1, p.size()):
                length += p[k].distance_to(p[k - 1])
            path_through = p.size() >= 2 and length < 8.0
    if frame == 600 or (broke_at > 0 and frame - broke_at > 120):
        _rec("broken_cover_setup", broke_at > 0, "hid behind the breakable wall at frame %d" % broke_at)
        _rec("drops_broken_cover_at_once", repick_frames >= 0 and repick_frames <= 5, "re-picked %d frames after the break (state %s)" % [repick_frames, brain.state])
        _rec("navmesh_rebakes_after_break", rebake_frames >= 0 and rebake_frames <= 30 and path_through, "rebake after %d frames, straight path through old footprint %s" % [rebake_frames, path_through])
        phase = 2
        frame = 0
        _start_b(true)

func _ver() -> int:
    var r := BotNav.ensure_region(map)
    return int(r.get_meta("version")) if r else -1
