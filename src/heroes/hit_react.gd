class_name HitReact
extends RefCounted
## Client-side hit reaction (visual only): a short additive flinch on the hero's visual pivot plus a brief
## white flash in the toon materials. Driven by replicated health (hp drop; heals/respawn ignored) and by
## replayed damage_dealt events (direction from `pos`/`source`; also covers hits fully absorbed by overheal).
## Same path on host, local and remote heroes. Never touches gameplay state.
const FLASH_TIME := 0.13
const FLINCH_TIME := 0.32
const MERGE_WINDOW := 0.12     ## hp drop + damage event of the same hit -> one reaction
const MIN_STRENGTH := 0.35
const MAX_STRENGTH := 1.0
const TILT := 0.16             ## rad at full strength
const PUSH := 0.07             ## m at full strength

var hero: Node3D
var pivot: Node3D              ## additive flinch node (between hero._vis and the model parts)
var t := 99.0                  ## time since the current reaction started
var strength := 0.0
var dir_local := Vector3(0, 0, 1)   ## horizontal hit direction in hero space (from source towards hero)
var count := 0                 ## reactions started (tests)
var flash := 0.0               ## current flash amount 0..1
var _last_hp := -1.0
var _dir_t := 99.0             ## age of the last event direction
var _prims: Array = []         ## [StandardMaterial3D, emission_enabled, emission, energy]
var _geo: Array = []           ## toon GeometryInstance3D (instance uniform `hit_flash`)

func _init(h: Node3D, p: Node3D) -> void:
    hero = h
    pivot = p
    _last_hp = h.health.hp
    collect()
    if not Events.damage_dealt.is_connected(_on_damage):
        Events.damage_dealt.connect(_on_damage)

func disconnect_events() -> void:
    if Events.damage_dealt.is_connected(_on_damage):
        Events.damage_dealt.disconnect(_on_damage)

## Finds the flashable surfaces under the pivot. Toon meshes are shared between heroes (ToonKit cache), so
## the flash is a per-instance shader parameter, never a material change. Primitive parts own their material.
func collect() -> void:
    _prims.clear()
    _geo.clear()
    for mi in pivot.find_children("*", "MeshInstance3D", true, false):
        if mi.material_override is StandardMaterial3D:
            var m: StandardMaterial3D = mi.material_override
            _prims.append([m, m.emission_enabled, m.emission, m.emission_energy_multiplier])
        elif mi.mesh and mi.mesh.get_surface_count() > 0 and mi.mesh.surface_get_material(0) is ShaderMaterial:
            _geo.append(mi)

func _strength(amount: float) -> float:
    var mx := maxf(1.0, hero.health.max_hp)
    return clampf(MIN_STRENGTH + amount / mx * 3.0, MIN_STRENGTH, MAX_STRENGTH)

func trigger(amount: float) -> void:
    if hero.dead:
        return
    var s := _strength(amount)
    if t < MERGE_WINDOW:
        strength = maxf(strength, s)   # same hit seen twice (hp + event): keep one reaction
        return
    strength = s
    t = 0.0
    count += 1
    if _dir_t > MERGE_WINDOW:
        dir_local = Vector3(0, 0, 1)   # generic: knocked back (hero faces -Z)

func _on_damage(e: Dictionary) -> void:
    if e.get("target") != hero or not is_instance_valid(hero):
        return
    var from := Vector3.INF
    var src = e.get("source")
    if e.get("src_pos") is Vector3 and src != hero:
        from = e.src_pos   # host-truth attacker position (core R10), also on clients
    elif src is Node3D and is_instance_valid(src) and src != hero:
        from = src.global_position
    elif e.get("pos") is Vector3:
        from = e.pos   # hit point: push away from it
    if from != Vector3.INF and hero.is_inside_tree():
        var d: Vector3 = hero.global_transform.basis.inverse() * (hero.global_position - from)
        d.y = 0.0
        if d.length() > 0.05:
            dir_local = d.normalized()
            _dir_t = 0.0
    trigger(float(e.get("amount", 0.0)))

func process(dt: float) -> void:
    var hp: float = hero.health.hp
    if hero.dead:
        _reset()
    elif _last_hp >= 0.0 and hp < _last_hp - 0.01:
        trigger(_last_hp - hp)
    _last_hp = hp   # increases (heals, respawn) only re-baseline
    _dir_t += dt
    t += dt
    # flinch: fast kick (60 ms), then ease back
    var k := 0.0
    if t < FLINCH_TIME:
        k = sin(t / 0.06 * PI * 0.5) if t < 0.06 else pow(1.0 - (t - 0.06) / (FLINCH_TIME - 0.06), 2.0)
        k *= strength
    pivot.position = dir_local * PUSH * k
    pivot.rotation = Vector3(dir_local.z * TILT * k, 0.0, -dir_local.x * TILT * k)
    var f := 0.0
    if t < FLASH_TIME:
        f = (1.0 - t / FLASH_TIME) * (0.55 + 0.45 * strength)
    _set_flash(f)

func _reset() -> void:
    t = 99.0
    strength = 0.0

func _set_flash(f: float) -> void:
    if is_equal_approx(f, flash):
        return
    flash = f
    for mi in _geo:
        if is_instance_valid(mi):
            mi.set_instance_shader_parameter("hit_flash", f)
    for p in _prims:
        var m: StandardMaterial3D = p[0]
        if f > 0.0:
            m.emission_enabled = true
            m.emission = (p[2] as Color).lerp(Color.WHITE, f) if p[1] else Color.WHITE * f
            m.emission_energy_multiplier = maxf(p[3], 1.0) if p[1] else 1.0
        else:
            m.emission_enabled = p[1]
            m.emission = p[2]
            m.emission_energy_multiplier = p[3]
