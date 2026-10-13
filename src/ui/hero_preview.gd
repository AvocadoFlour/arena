class_name HeroPreview
extends SubViewportContainer
## Slowly rotating 3D preview of a hero in its own SubViewport/World3D (no gameplay nodes: nothing joins
## the "heroes" group, no physics). Model source, in order:
##   1. def.model_scene.path (GLB) via the heroes module's HeroModel.create (same toon look as in game),
##   2. the raw GLB PackedScene if HeroModel is unavailable,
##   3. the def's primitive "model" parts (INTERFACES §2), built read-only here like hero.gd does.
## Cheap: renders only while visible (UPDATE_WHEN_VISIBLE + stops rotating when hidden); low_quality
## halves the render resolution, disables MSAA and shadows. Drag (mouse or touch) to rotate.
const SPIN := 0.5          ## rad/s
const DRAG := 0.01         ## rad per px
const TEAM_PREVIEW := Color("#3ea0ff")
var vp: SubViewport
var pivot: Node3D
var cam: Camera3D
var light: DirectionalLight3D
var model: Node3D
var source := ""           ## "scene" | "glb" | "primitive" | "none" (tests/debug)
var def_id := ""
var _dragging := false
var _low := false

func _ready() -> void:
    custom_minimum_size = Vector2(320, 320)
    stretch = true
    mouse_filter = Control.MOUSE_FILTER_STOP
    vp = SubViewport.new()
    vp.own_world_3d = true
    vp.transparent_bg = true
    vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
    add_child(vp)
    var env := WorldEnvironment.new()
    var e := Environment.new()
    e.background_mode = Environment.BG_CLEAR_COLOR
    e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    e.ambient_light_color = Color(0.55, 0.6, 0.7)
    e.ambient_light_energy = 0.8
    env.environment = e
    vp.add_child(env)
    light = DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-40, 35, 0)
    light.light_energy = 1.2
    vp.add_child(light)
    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-20, -140, 0)
    fill.light_energy = 0.4
    vp.add_child(fill)
    pivot = Node3D.new()
    vp.add_child(pivot)
    cam = Camera3D.new()
    cam.position = Vector3(0, 1.1, 3.4)
    cam.fov = 40
    vp.add_child(cam)
    cam.look_at(Vector3(0, 0.85, 0))
    cam.current = true
    apply_quality(Settings.low_quality)
    Settings.low_quality_changed.connect(apply_quality)

func _exit_tree() -> void:
    if Settings.low_quality_changed.is_connected(apply_quality):
        Settings.low_quality_changed.disconnect(apply_quality)

func apply_quality(low: bool) -> void:
    _low = low
    stretch_shrink = 2 if low else 1
    vp.msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
    light.shadow_enabled = not low

## Shows the hero from a def dictionary. Replaces any previous model.
func show_def(def: Dictionary) -> void:
    if model:
        pivot.remove_child(model)
        model.queue_free()
        model = null
    def_id = str(def.get("id", ""))
    source = "none"
    var ms = def.get("model_scene")
    if ms is Dictionary and ResourceLoader.exists(str(ms.get("path", ""))):
        model = _from_scene(ms)
    if model == null and def.get("model", []).size() > 0:
        model = build_primitives(def.model)
        source = "primitive"
    if model:
        pivot.add_child(model)
    pivot.rotation.y = 0.0

func _from_scene(ms: Dictionary) -> Node3D:
    if ClassDB.class_exists("HeroModel") or ResourceLoader.exists("res://src/heroes/hero_model.gd"):
        var hm = load("res://src/heroes/hero_model.gd").create(ms)
        if hm != null:
            source = "scene"
            return hm
    var ps = load(str(ms.path))
    if ps is PackedScene:
        var n: Node3D = Node3D.new()
        n.add_child(ps.instantiate())
        n.rotation_degrees.y = float(ms.get("yaw_deg", 180.0))
        n.scale = Vector3.ONE * float(ms.get("scale", 1.0))
        source = "glb"
        return n
    return null

## Primitive parts (§2 "model" + optional rot/scale/pivot/colour keys); "team" colour = team-0 blue.
static func build_primitives(parts: Array) -> Node3D:
    var root := Node3D.new()
    for p in parts:
        var mi := MeshInstance3D.new()
        match str(p.get("shape", "box")):
            "capsule":
                var m := CapsuleMesh.new()
                m.radius = float(p.radius)
                m.height = maxf(float(p.height), float(p.radius) * 2.0)
                mi.mesh = m
            "sphere":
                var s := SphereMesh.new()
                s.radius = float(p.radius)
                s.height = float(p.radius) * 2.0
                mi.mesh = s
            _:
                var b := BoxMesh.new()
                var sz: Array = p.get("size", [0.3, 0.3, 0.3])
                b.size = Vector3(sz[0], sz[1], sz[2])
                mi.mesh = b
        var mat := StandardMaterial3D.new()
        var c := str(p.get("color", "#cccccc"))
        mat.albedo_color = TEAM_PREVIEW if c == "team" else Color(c)
        mat.roughness = float(p.get("roughness", 0.75))
        mat.metallic = float(p.get("metallic", 0.0))
        if p.has("emission"):
            mat.emission_enabled = true
            mat.emission = Color(str(p.emission))
        mi.material_override = mat
        var pos: Array = p.get("pos", [0, 0, 0])
        mi.position = Vector3(pos[0], pos[1], pos[2])
        if p.has("rot"):
            mi.rotation_degrees = Vector3(p.rot[0], p.rot[1], p.rot[2])
        if p.has("scale"):
            mi.scale = Vector3(p.scale[0], p.scale[1], p.scale[2])
        root.add_child(mi)
    root.rotation_degrees.y = 180.0   # face the camera
    return root

func _process(dt: float) -> void:
    if not is_visible_in_tree():
        return   # hidden: no spin; the viewport itself only renders when visible
    if not _dragging:
        pivot.rotation.y += SPIN * dt

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        _dragging = event.pressed
    elif event is InputEventScreenTouch:
        _dragging = event.pressed
    elif (event is InputEventMouseMotion and _dragging) or event is InputEventScreenDrag:
        drag(event.relative.x)

func drag(dx: float) -> void:
    pivot.rotation.y += dx * DRAG
