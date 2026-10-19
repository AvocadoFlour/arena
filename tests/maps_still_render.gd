extends SceneTree
## Fixed-camera map render for pixel before/after diffs (maps queue 4):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 --rendering-driver opengl3 -s tests/maps_still_render.gd -- --map=arena02 --lq=1 --out=/tmp/x
var f := 0
var cams := [[Vector3(0, 9, 30), Vector3(0, 1, 0)], [Vector3(-34, 6, 20), Vector3(-10, 2, -5)], [Vector3(14, 2, -6), Vector3(-6, 1.5, 10)]]
var ci := 0
var cam: Camera3D
var a := {}
func _initialize():
    for s in OS.get_cmdline_user_args():
        if s.begins_with("--"): a[s.substr(2).get_slice("=", 0)] = s.get_slice("=", 1)
    var m := MapLoader.build("res://src/maps/%s.json" % a.map, {"low_quality": a.lq == "1"})
    root.add_child(m)
    cam = Camera3D.new(); cam.fov = 75; root.add_child(cam)
    _place()
func _place():
    cam.position = cams[ci][0]; cam.look_at(cams[ci][1])
func _process(_d):
    f += 1
    if f % 20 == 0:
        root.get_viewport().get_texture().get_image().save_png("%s-cam%d.png" % [a.out, ci])
        ci += 1
        if ci >= cams.size(): quit(); return false
        _place()
    return false
