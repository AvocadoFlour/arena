extends Node3D
## A single projectile. Moves each physics tick, sweeps a ray along its path (walls, shields,
## heroes), applies damage / slow on hit, then frees itself. Always flies through the owner's team.
## "ally_heal" (> 0): every ally (not the owner) the shot flies past within its hit radius, and every ally inside
## the splash at impact, is healed that much — once per ally per shot, never slowed or rooted.
var owner_hero
var def: Dictionary
var vel := Vector3.ZERO
var life := 0.0
var exploded := false
var healed := {}           ## allies already healed by this shot (instance id -> true)
var glyph: Node3D = null   ## toon visual for named projectiles (spins; no gameplay effect)

func _init(h, d: Dictionary) -> void:
    owner_hero = h
    def = d
    life = float(d.get("lifetime", 3.0))
    var vis_path := String(d.get("visual", ""))
    if vis_path != "" and ResourceLoader.exists(vis_path):   # same toon prop visual as remote clients (visual only)
        glyph = load(vis_path).build_prop("shot", Vector3.ONE * float(d.get("size", 0.15)), Color(String(d.get("color", "#d8ecff"))))
        add_child(glyph)
        return
    var mi := MeshInstance3D.new()
    var sm := SphereMesh.new()
    var r := float(d.get("size", 0.15))
    sm.radius = r
    sm.height = r * 2.0
    mi.mesh = sm
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = Color(String(d.get("color", "#ffd040")))
    mi.material_override = m
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mi)

func launch(pos: Vector3, dir: Vector3) -> void:
    global_position = pos
    vel = dir.normalized() * float(def.get("speed", 30.0))

## Pure kinematics (unit-tested): returns [new_pos, new_vel].
static func step(pos: Vector3, v: Vector3, gravity: float, dt: float) -> Array:
    var nv := v + Vector3(0, -gravity, 0) * dt
    return [pos + nv * dt, nv]

func _physics_process(dt: float) -> void:
    if exploded:
        return
    life -= dt
    var r := step(global_position, vel, float(def.get("gravity", 0.0)), dt)
    var to: Vector3 = r[0]
    vel = r[1]
    var from := global_position
    var hit_pos := to
    var target = null
    var hit_something := false
    var space := get_world_3d().direct_space_state
    var q := PhysicsRayQueryParameters3D.create(from, to)
    if is_instance_valid(owner_hero):
        var ex: Array[RID] = []
        for h in get_tree().get_nodes_in_group("heroes"):
            if h.team == owner_hero.team:
                ex.append(h.get_rid())   # passes through self and allies
        q.exclude = ex
    var hit := space.intersect_ray(q)
    if not hit.is_empty():
        hit_something = true
        hit_pos = hit.position
        if hit.collider is Hero:
            target = hit.collider
        elif hit.collider.is_in_group("destructible"):
            _cover_hit = hit.collider
    # Generous hit radius: also catch enemies passing near the segment.
    if target == null:
        var hr := float(def.get("hit_radius", 0.3))
        var best := INF
        for h in get_tree().get_nodes_in_group("heroes"):
            if h == owner_hero or h.dead or not is_instance_valid(owner_hero) or h.team == owner_hero.team:
                continue
            var c: Vector3 = h.global_position + Vector3(0, 0.9, 0)
            var p := Geometry3D.get_closest_point_to_segment(c, from, hit_pos)
            var d := p.distance_to(c)
            if d <= hr + 0.5 and from.distance_to(p) < best:
                best = from.distance_to(p)
                target = h
                hit_pos = p
                hit_something = true
    _heal_allies_along(from, hit_pos)
    global_position = hit_pos
    if hit_something:
        _impact(hit_pos, target)
    elif life <= 0.0:
        queue_free()

var _cover_hit = null   ## breakable cover hit directly (maps §6)

func _heal_ally(h) -> void:
    var amt := float(def.get("ally_heal", 0.0))
    var src = owner_hero if is_instance_valid(owner_hero) else null
    if amt <= 0.0 or src == null or h == src or h.dead or h.team != src.team or healed.has(h.get_instance_id()):
        return
    healed[h.get_instance_id()] = true
    h.heal(amt, src, String(def.get("id", def.get("type", ""))))

## Pass-through heal: allies near the segment flown this tick (same reach as the enemy hit test).
func _heal_allies_along(a: Vector3, b: Vector3) -> void:
    if float(def.get("ally_heal", 0.0)) <= 0.0 or not is_instance_valid(owner_hero):
        return
    var hr := float(def.get("hit_radius", 0.3))
    for h in get_tree().get_nodes_in_group("heroes"):
        if h == owner_hero or h.dead or h.team != owner_hero.team:
            continue
        var c: Vector3 = h.global_position + Vector3(0, 0.9, 0)
        if Geometry3D.get_closest_point_to_segment(c, a, b).distance_to(c) <= hr + 0.5:
            _heal_ally(h)

func _impact(pos: Vector3, target) -> void:
    exploded = true
    var src = owner_hero if is_instance_valid(owner_hero) else null
    var kind := String(def.get("kind", "projectile"))
    var dmg := float(def.get("damage", 0.0))
    var scale := float(src.damage_mult()) if src else 1.0
    var splash := float(def.get("splash_radius", 0.0))
    var victims: Array = []
    if target != null and src and target.team != src.team and not target.dead:
        victims.append(target)
        if dmg > 0.0:
            target.take_damage(dmg * scale, src, pos, kind, String(def.get("id", def.get("type", ""))))
    if is_instance_valid(_cover_hit) and dmg > 0.0:
        _cover_hit.take_damage(dmg * scale, src, pos, kind, String(def.get("id", def.get("type", ""))))
    if splash > 0.0 and src:
        Hero.damage_destructibles(get_tree(), pos, splash, dmg * scale, src, kind, String(def.get("id", def.get("type", ""))), _cover_hit)
        for h in get_tree().get_nodes_in_group("heroes"):
            if h == src or h.dead or h.team == src.team or victims.has(h):
                continue
            var amt := HitMath.aoe_damage(pos, splash, dmg, h.global_position + Vector3(0, 0.9, 0))
            if amt > 0.0:
                victims.append(h)
                h.take_damage(amt * scale, src, h.global_position + Vector3(0, 1.2, 0), kind, String(def.get("id", def.get("type", ""))))
        for h in get_tree().get_nodes_in_group("heroes"):   # splash heal: allies in radius, once per shot
            if h != src and h.team == src.team and (h.global_position + Vector3(0, 0.9, 0)).distance_to(pos) <= splash:
                _heal_ally(h)
        Fx.ring(get_parent(), pos, splash, Color(String(def.get("color", "#ffd040"))), 0.3)
    if glyph:   # toon pop: flat ring + white star burst (visual only)
        ToonFx.ring(get_parent(), pos, maxf(splash, 1.0), Color(String(def.get("color", "#d8ecff"))), 0.35, 0.12)
        ToonFx.burst(get_parent(), pos, Color("#9ecff5"), 8, 0.8, 0.3, Vector3.UP, 0.22)
    var root_t := float(def.get("root", 0.0))
    if root_t > 0.0:
        for v in victims:
            if is_instance_valid(v) and v.has_method("apply_root"):
                v.apply_root(root_t)
    var slow: Dictionary = def.get("slow", {})
    if not slow.is_empty():
        for v in victims:
            if is_instance_valid(v) and v.has_method("apply_slow"):
                v.apply_slow(float(slow.get("mult", 0.6)), float(slow.get("duration", 2.0)))
    queue_free()
