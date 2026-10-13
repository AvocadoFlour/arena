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

var _killed := false

func _init(amount: float = 0.0, kind := "primary", killed := false) -> void:
    _killed = killed
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

## Hits at or above this amount (or killing blows) are emphasised. No crit flag exists in
## damage_dealt yet (docs/requests/ui.md); "big hit" stands in for it.
const BIG_HIT := 50.0
var big := false

## Animation parameters: {size: base scale mult, punch: peak scale, rise: m, life: s}.
static func pop_params(amount: float, killed: bool) -> Dictionary:
    if killed:
        return {"size": 1.5, "punch": 1.9, "rise": 1.4, "life": 1.1}
    if amount >= BIG_HIT:
        return {"size": 1.3, "punch": 1.7, "rise": 1.2, "life": 0.95}
    return {"size": 1.0, "punch": 1.35, "rise": 0.9, "life": 0.7}

## Pop animation: scale punch (overshoot then settle), rise with ease-out, fade, free.
## Call after adding to the tree. Returns the tween.
func pop(amount := -1.0, killed := false) -> Tween:
    if amount < 0.0:
        amount = float(text.to_int())
        killed = _killed
    var p := pop_params(amount, killed)
    big = p.size > 1.0
    if big:
        outline_size = 22
        text = text + "!" if killed else text
    scale = Vector3.ONE * p.size * 0.4
    var tw := create_tween()
    tw.set_parallel(true)
    tw.tween_property(self, "scale", Vector3.ONE * p.size * p.punch, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.tween_property(self, "scale", Vector3.ONE * p.size, 0.16).set_delay(0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
    tw.tween_property(self, "position:y", position.y + p.rise, p.life).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tw.tween_property(self, "modulate:a", 0.0, p.life * 0.45).set_delay(p.life * 0.55)
    tw.chain().tween_callback(queue_free)
    return tw
