class_name DamageNumber
extends Label3D
## Floating damage number: thick outline, billboard, and size compensated for camera distance
## so it stays readable far away (grows with distance, clamped) without being huge up close.
## Styling inputs come from Events.damage_dealt (INTERFACES §3): kind, killed, ability_id, crit.
## Three independent emphasis axes: colour = source (primary / ability / ultimate / crit),
## size = magnitude (big hit >= BIG_HIT, killing blow), crit = extra punch + shake + "CRIT" tag.
const BASE_PIXEL := 0.006
const REF_DIST := 8.0     ## at/below this distance: base size
const MAX_SCALE := 4.0    ## cap so far numbers don't fill the screen
const BIG_HIT := 50.0     ## size emphasis threshold (separate from crit)
const COL_PRIMARY := Color(1, 1, 0.6)
const COL_ABILITY := Color(1, 0.75, 0.2)
const COL_ULT := Color(0.8, 0.45, 1.0)
const COL_CRIT := Color(1, 0.25, 0.55)
const COL_KILL := Color(1, 0.3, 0.2)
var _cam: Camera3D
var amount := 0.0
var killed := false
var crit := false
var ultimate := false
var big := false

static func scale_for_distance(d: float) -> float:
    return clampf(d / REF_DIST, 1.0, MAX_SCALE)

## Damage from an ultimate: ability_id is the source hero's ultimate slot (preferred), or the
## legacy/aoe kind "ultimate".
static func is_ultimate(source, ability_id: String, kind: String) -> bool:
    if ability_id != "":
        return KillFeed.slot_of(KillFeed.def_of(source), ability_id) == "ultimate" or (kind == "ultimate")
    return kind == "ultimate"

## Colour priority: kill > crit > ultimate > ability > primary.
static func color_for(kind: String, is_killed: bool, ability_id := "", is_crit := false, is_ult := false) -> Color:
    if is_killed:
        return COL_KILL
    if is_crit:
        return COL_CRIT
    if is_ult or kind == "ultimate":
        return COL_ULT
    var from_ability := ability_id != "" or (kind != "primary" and kind != "")
    return COL_ABILITY if from_ability else COL_PRIMARY

## Size/motion: magnitude axis (big hit, kill) and crit axis combine independently.
static func pop_params(dmg: float, is_killed: bool, is_crit := false, is_ult := false) -> Dictionary:
    var p := {"size": 1.0, "punch": 1.35, "rise": 0.9, "life": 0.7, "shake": 0.0}
    if dmg >= BIG_HIT:
        p.size = 1.3; p.punch = 1.7; p.rise = 1.2; p.life = 0.95
    if is_killed:
        p.size = 1.5; p.punch = 1.9; p.rise = 1.4; p.life = 1.1
    if is_ult:
        p.size *= 1.1; p.life += 0.15
    if is_crit:
        p.size *= 1.15; p.punch += 0.4; p.shake = 0.12; p.life += 0.1
    return p

func _init(dmg: float = 0.0, kind := "primary", is_killed := false, ability_id := "", is_crit := false, is_ult := false) -> void:
    amount = dmg
    killed = is_killed
    crit = is_crit
    ultimate = is_ult or kind == "ultimate"
    text = str(int(round(dmg)))
    if crit:
        text = "CRIT " + text
    billboard = BaseMaterial3D.BILLBOARD_ENABLED
    no_depth_test = true
    font_size = 64
    outline_size = 18
    outline_modulate = Color(0, 0, 0, 0.95)
    pixel_size = BASE_PIXEL
    modulate = color_for(kind, killed, ability_id, crit, ultimate)
    render_priority = 10
    outline_render_priority = 9

## Builds a number straight from a damage_dealt payload; tolerates older events without
## ability_id / crit.
static func from_event(ev: Dictionary) -> DamageNumber:
    var aid := str(ev.get("ability_id", ""))
    var kind := str(ev.get("kind", "primary"))
    return DamageNumber.new(float(ev.get("amount", 0.0)), kind, bool(ev.get("killed", false)), aid,
        bool(ev.get("crit", false)), is_ultimate(ev.get("source"), aid, kind))

func _process(_dt: float) -> void:
    if not is_instance_valid(_cam):
        _cam = get_viewport().get_camera_3d() if is_inside_tree() else null
    if _cam:
        pixel_size = BASE_PIXEL * scale_for_distance(_cam.global_position.distance_to(global_position))

## Pop animation: scale punch (overshoot then settle), eased rise, fade, free; crits shake sideways.
## Call after adding to the tree. Returns the tween.
func pop() -> Tween:
    var p := pop_params(amount, killed, crit, ultimate)
    big = amount >= BIG_HIT or killed
    if big:
        outline_size = 22
    if killed and not text.ends_with("!"):
        text += "!"
    scale = Vector3.ONE * p.size * 0.4
    var tw := create_tween()
    tw.set_parallel(true)
    tw.tween_property(self, "scale", Vector3.ONE * p.size * p.punch, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.tween_property(self, "scale", Vector3.ONE * p.size, 0.16).set_delay(0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
    tw.tween_property(self, "position:y", position.y + p.rise, p.life).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    if p.shake > 0.0:
        var x := position.x
        for i in 4:
            tw.tween_property(self, "position:x", x + (p.shake if i % 2 == 0 else -p.shake), 0.04).set_delay(0.04 * i)
        tw.tween_property(self, "position:x", x, 0.04).set_delay(0.16)
    tw.tween_property(self, "modulate:a", 0.0, p.life * 0.45).set_delay(p.life * 0.55)
    tw.chain().tween_callback(queue_free)
    return tw
