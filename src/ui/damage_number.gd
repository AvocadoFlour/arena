class_name DamageNumber
extends Label3D
## Floating damage number: thick outline, billboard, and size compensated for camera distance
## so it stays readable far away (grows with distance, clamped) without being huge up close.
const BASE_PIXEL := 0.006
const REF_DIST := 8.0     ## at/below this distance: base size
const MAX_SCALE := 4.0    ## cap so far numbers don't fill the screen
var _cam: Camera3D

static func scale_for_distance(d: float) -> float:
    return clampf(d / REF_DIST, 1.0, MAX_SCALE)

static func color_for(kind: String, killed: bool) -> Color:
    if killed:
        return Color(1, 0.3, 0.2)
    return Color(1, 0.75, 0.2) if kind != "primary" else Color(1, 1, 0.6)

func _init(amount: float = 0.0, kind := "primary", killed := false) -> void:
    text = str(int(round(amount)))
    billboard = BaseMaterial3D.BILLBOARD_ENABLED
    no_depth_test = true
    font_size = 64
    outline_size = 18
    outline_modulate = Color(0, 0, 0, 0.95)
    pixel_size = BASE_PIXEL
    modulate = color_for(kind, killed)
    render_priority = 10
    outline_render_priority = 9

func _process(_dt: float) -> void:
    if not is_instance_valid(_cam):
        _cam = get_viewport().get_camera_3d() if is_inside_tree() else null
    if _cam:
        pixel_size = BASE_PIXEL * scale_for_distance(_cam.global_position.distance_to(global_position))
