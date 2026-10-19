extends "res://src/abilities/dash.gd"
## Hotfix (Tomo): a very short dash ("blink") in the move direction (else facing) that leaves a fading afterimage
## at the start point; the next burst deals bonus damage. Params: distance, duration (dash.gd), bonus_mult,
## bonus_shots, bonus_window, color.
## Burst fire itself is built into hero.gd (primary.burst -> BurstWeapon).
const AFTERIMAGE_LIFE := 0.45
var _blinking := false   ## our dash is running; when it ends, momentum is capped to run speed (a blink, not a launch)


func _do() -> bool:
    var from: Vector3 = hero.global_position
    if not super._do():
        return false
    _blinking = true
    if hero.weapon is BurstWeapon:
        hero.weapon.grant_bonus(float(def.get("bonus_mult", 1.5)), int(def.get("bonus_shots", 3)), float(def.get("bonus_window", 4.0)))
    var parent: Node = hero.get_parent()
    if parent and hero.is_inside_tree():
        var c := Color(String(def.get("color", "#ff4a4a")))
        Fx.ring(parent, from + Vector3(0, 1.0, 0), 0.6, c, AFTERIMAGE_LIFE)   # replayed on clients (INTERFACES §10)
        var g := Afterimage.new()
        g.setup(c, float(hero.def.get("collider", {}).get("height", 1.8)))
        parent.add_child(g)
        g.global_position = from + Vector3(0, g.half_height, 0)
        g.rotation.y = hero.rotation.y
    return true

func tick(dt: float) -> void:
    super.tick(dt)
    if _blinking and hero.dash_time <= 0.0:
        _blinking = false
        var hv := Vector3(hero.velocity.x, 0, hero.velocity.z)
        var cap := float(hero.move_cfg.get("speed", 7.0))
        if hv.length() > cap:
            hv = hv.normalized() * cap
            hero.velocity = Vector3(hv.x, hero.velocity.y, hv.z)

## Bonus rounds still pending (HUD/tests).
func bonus_pending() -> int:
    return hero.weapon.bonus_shots if hero.weapon is BurstWeapon else 0

## Translucent capsule silhouette left where the blink started; fades out and frees itself. Visual only
## (no collision, not networked; clients see the replayed Fx.ring).
class Afterimage extends MeshInstance3D:
    const LIFE := 0.45
    var left := LIFE
    var half_height := 0.9
    var _mat: StandardMaterial3D
    var _col := Color.WHITE

    func setup(c: Color, height: float) -> void:
        name = "HotfixAfterimage"
        var m := CapsuleMesh.new()
        m.radius = 0.3
        m.height = height
        m.radial_segments = 10
        m.rings = 3
        mesh = m
        half_height = height * 0.5
        _col = c
        _mat = StandardMaterial3D.new()
        _mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        _mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        _mat.albedo_color = Color(c.r, c.g, c.b, 0.45)
        material_override = _mat
        cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    func _process(dt: float) -> void:
        left -= dt
        _mat.albedo_color = Color(_col.r, _col.g, _col.b, 0.45 * maxf(left, 0.0) / LIFE)
        if left <= 0.0:
            queue_free()
