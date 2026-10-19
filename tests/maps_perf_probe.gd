extends SceneTree
## Perf attribution probe (maps queue 4). Runs main.tscn (user args pass through: --demo=200 --map=arena02 [--low_quality]),
## then alternates 1.5 s windows "everything" vs "X hidden" (3 pairs each) and prints the fps gain per X.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 --rendering-driver opengl3 -s tests/maps_perf_probe.gd -- --demo=200 --map=arena02 --low_quality
var t := 0.0
var frames := 0
var win_t := 0.0
var step := -1
var main: Node
var steps := []
const TOG := ["map_all", "no_heroes", "no_hud", "no_outlines", "no_map_meshes", "no_props", "no_sky"]
var acc := {}
var hidden: Array = []
func _initialize():
    for r in 3:
        for k in TOG:
            steps.append("base"); steps.append(k)
    main = load("res://src/main.tscn").instantiate()
    root.add_child(main)
func _map() -> Node:
    return main.find_child("Map", true, false)
func _toggle(name: String, on: bool):
    var m := _map()
    var nodes: Array = []
    match name:
        "no_map_meshes":
            for c in m.get_children():
                if c is StaticBody3D: nodes.append(c)
        "no_outlines":
            var o = m.get_node_or_null("Outlines"); if o: nodes.append(o)
        "no_spawnroom_vis":
            var s = m.get_node_or_null("SpawnRooms"); if s: nodes += s.get_children()
        "no_props":
            var p = m.get_node_or_null("Props"); if p: nodes.append(p)
        "no_heroes":
            nodes += get_nodes_in_group("heroes")
        "no_hud":
            for c in main.find_children("*", "CanvasLayer", true, false): nodes.append(c)
        "no_sky":
            var we: WorldEnvironment = m.find_children("*", "WorldEnvironment", true, false)[0]
            if on: we.environment.background_mode = Environment.BG_COLOR
            else: we.environment.background_mode = Environment.BG_SKY
        "map_all":
            nodes.append(m)
        "nothing3d":
            nodes.append(m); nodes += get_nodes_in_group("heroes")
    for n in nodes:
        n.visible = not on
func _process(dt):
    t += dt
    if t < 6.0:
        return false
    if step == -1:
        step = 0; win_t = 0; frames = 0; _toggle(steps[0], true)
        return false
    win_t += dt; frames += 1
    if win_t >= 1.5:
        var vp := root.get_viewport_rid()
        var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
        var ob := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
        var pr := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
        var f := frames / win_t
        if steps[step] == "base":
            acc["_last"] = f
        else:
            var k: String = steps[step]
            if not acc.has(k): acc[k] = []
            acc[k].append([acc["_last"], f, dc, pr])
        if step == steps.size() - 1:
            for k in TOG:
                var b := 0.0; var x := 0.0
                for e in acc[k]: b += e[0]; x += e[1]
                print("PROBE %-14s base=%.1f hidden=%.1f  gain=%+.0f%%  %s" % [k, b / 3, x / 3, (x / b - 1.0) * 100.0, acc[k]])
        _toggle(steps[step], false)
        step += 1
        if step >= steps.size():
            quit(); return false
        win_t = 0; frames = 0; _toggle(steps[step], true)
    return false
