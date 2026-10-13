class_name HeroPreview
extends SubViewportContainer
## Slowly rotating 3D preview of a hero in its own SubViewport/World3D (no gameplay nodes: nothing joins
## the "heroes" group, no physics). Model source, in order:
##   HeroModel.create_display_def (INTERFACES §2 "Display-only model"): the GLB HeroModel (same toon look as in
##   game) when def.model_scene loads, else the def's primitive "model" parts built by the same code as hero.gd.
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
var source := ""           ## "scene" | "primitive" | "none" (tests/debug)
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
    var has_parts: bool = def.get("model", []).size() > 0
    if (ms is Dictionary and ResourceLoader.exists(str(ms.get("path", "")))) or has_parts:
        model = HeroModel.create_display_def(def, TEAM_PREVIEW)
        if model is HeroModel:
            source = "scene"
        elif model:
            model.rotation_degrees.y = 180.0   # primitives face -Z; turn them to the camera
            source = "primitive"
    if model:
        pivot.add_child(model)
    pivot.rotation.y = 0.0

## Primitive parts (§2 "model") as a display node; "team" colour = team-0 blue. Thin wrapper over HeroModel.
static func build_primitives(parts: Array) -> Node3D:
    var root := HeroModel.create_display_def({"model": parts}, TEAM_PREVIEW)
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
