extends SceneTree
## Hero model preview / screenshot tool (visual only, heroes-owned):
##   xvfb-run godot --path . --rendering-driver opengl3 -s src/heroes/models/preview.gd -- \
##       --hero=twin_tails --mode=idle|run|heal|shoot|cast|death --view=front|side|three_quarter|back|ots --out=PNG [--t=S]
## Heroes are puppets (no physics); modes set only replicated fields (velocity, ammo, cooldowns, dead).
var args := {}
var hero
var ally
var _ready_done := false
var cam: Camera3D
var t := 0.0
var shot_at := 1.2
var done := false

func _initialize() -> void:
    pass

## Autoloads (Events, Net) exist only from the first frame, so the scene is built there.
func _setup() -> void:
    for a in OS.get_cmdline_user_args():
        var kv := a.trim_prefix("--").split("=", true, 1)
        args[kv[0]] = kv[1] if kv.size() > 1 else "1"
    shot_at = float(args.get("t", "1.2"))
    var world := Node3D.new()
    root.add_child(world)
    var env := WorldEnvironment.new()
    var e := Environment.new()
    e.background_mode = Environment.BG_COLOR
    e.background_color = Color(0.86, 0.9, 0.95)
    e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    e.ambient_light_color = Color.WHITE
    env.environment = e
    world.add_child(env)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, 35, 0)
    sun.shadow_enabled = true
    world.add_child(sun)
    var floor := MeshInstance3D.new()
    var pm := PlaneMesh.new()
    pm.size = Vector2(30, 30)
    floor.mesh = pm
    var fm := StandardMaterial3D.new()
    fm.albedo_color = Color(0.93, 0.93, 0.9)
    floor.material_override = fm
    world.add_child(floor)
    var hid := String(args.get("hero", "twin_tails"))
    hero = load("res://src/heroes/hero.gd").from_def("res://src/heroes/%s.json" % hid)
    hero.net_role = "puppet"
    world.add_child(hero)
    var mode := String(args.get("mode", "idle"))
    if mode == "heal":
        ally = load("res://src/heroes/hero.gd").from_def("res://src/heroes/cob.json")
        ally.net_role = "puppet"
        world.add_child(ally)
        ally.global_position = Vector3(0.6, 0, -5)
    cam = Camera3D.new()
    world.add_child(cam)
    cam.fov = float(args.get("fov", "24"))
    var view := String(args.get("view", "three_quarter"))
    var tgt := Vector3(0, 0.95, 0)
    match view:
        "front": cam.position = Vector3(0, 1.0, -5.2)
        "side": cam.position = Vector3(5.2, 1.0, 0)
        "back": cam.position = Vector3(0, 1.0, 5.2)
        "ots":
            cam.position = Vector3(0.7, 2.1, 3.4)
            tgt = Vector3(0.3, 1.3, -4)
        _: cam.position = Vector3(3.4, 1.3, -3.9)
    cam.look_at(tgt)

func _process(dt: float) -> bool:
    if done:
        return true
    if not _ready_done:
        _ready_done = true
        _setup()
        return false
    t += dt
    var mode := String(args.get("mode", "idle"))
    match mode:
        "run": hero.velocity = Vector3(0, 0, -7.0)    # replicated velocity (puppet)
        "shoot":
            if fmod(t, 0.3) < dt:
                hero.weapon.ammo -= 1                # replicated ammo drop = shot
        "cast":
            if t > shot_at - 0.25 and hero.abilities.ability2.cooldown.remaining == 0.0:
                hero.abilities.ability2.cooldown.remaining = 5.0
        "heal":
            if t > 0.3 and hero.abilities.ability1.cooldown.remaining == 0.0:
                hero.abilities.ability1.cooldown.remaining = hero.abilities.ability1.cooldown.duration
        "death":
            if t > 0.3 and not hero.dead:
                hero.dead = true
                hero.visible = false
    if t >= shot_at:
        root.get_texture().get_image().save_png(String(args.get("out", "/tmp/preview.png")))
        print("PREVIEW ", args.get("out"))
        done = true
    return false
