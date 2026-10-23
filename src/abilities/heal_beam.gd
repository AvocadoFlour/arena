extends Ability
## Channelled beam (Encore Beam). Shift replaces left click until it is cancelled or `duration` runs out:
## the gun does not fire (`exclusive` / Hero.channel_lock). Other abilities still cast. The beam follows the aim, including empty air.
## An ally the beam touches is healed at `hps`. Every enemy it touches takes `enemy_dps`. Nobody on it: gray
## (`color_empty`), no heal. Press again to cancel. The cooldown starts when the beam ends: while it runs,
## cooldown.remaining = cooldown + time left, so clients see it from the snapshot (`remaining` > cooldown).
## Colours: `color_heal`, `color_damage` when an enemy is on it, `color_empty` when it hits nobody.
var left := 0.0
var target = null
var hit_enemy := false              ## HOST: an enemy took beam damage this tick
var vis_end := Vector3.ZERO        ## ribbon end when it is not stuck to a hero

func _do() -> bool:
    left = float(def.get("duration", 3.0))
    return true

## Shift again while channelling = cancel. The cooldown is held at (cooldown + duration) until the beam ends.
func activate() -> bool:
    if left > 0.0:
        cancel()
        return true
    if not can_activate() or not _do():
        return false
    cooldown.remaining = cooldown.duration + left
    return true

func cancel() -> void:
    left = 0.0
    target = null
    hit_enemy = false
    cooldown.remaining = minf(cooldown.remaining, cooldown.duration)

func channeling() -> bool:
    return left > 0.0

## End of the aim, `range` metres out, stopped by the world. Heroes do not stop it, so it can pass through them.
func aim_end() -> Vector3:
    var rng := float(def.get("range", 15.0))
    if not hero.is_inside_tree():
        return Vector3(0, 1.6, 0) + hero.look_dir() * rng
    var a: Vector3 = hero.eye_position()
    var end: Vector3 = a + hero.look_dir() * rng
    var exclude: Array = [hero.get_rid()]
    for _i in 8:
        var q := PhysicsRayQueryParameters3D.create(a, end)
        q.exclude = exclude
        var hit: Dictionary = hero.get_world_3d().direct_space_state.intersect_ray(q)
        if hit.is_empty():
            return end
        var c = hit.collider
        if c is Node and c.is_in_group("heroes"):
            exclude.append(c.get_rid())
            continue
        return hit.position
    return end

## Living heroes (not self) whose body is within `width` / 2 of the segment from the eye to `end`.
func heroes_along(end: Vector3, enemies: bool) -> Array:
    var out: Array = []
    if not hero.is_inside_tree():
        return out
    var a: Vector3 = hero.eye_position()
    var r := float(def.get("width", 1.0)) * 0.5
    for h in hero.get_tree().get_nodes_in_group("heroes"):
        if h == hero or h.dead or not h.is_inside_tree() or h.get_world_3d() != hero.get_world_3d():
            continue
        var foe: bool = h.team != hero.team
        if foe != enemies:
            continue
        var col: Dictionary = h.def.get("collider", {})
        var cr := float(col.get("radius", 0.4))
        var ch := float(col.get("height", 1.8))
        var p0: Vector3 = h.global_position + Vector3(0, cr, 0)
        var p1: Vector3 = h.global_position + Vector3(0, maxf(ch - cr, cr), 0)
        var cp := Geometry3D.get_closest_points_between_segments(a, end, p0, p1)
        if cp[0].distance_to(cp[1]) <= r + cr:
            out.append(h)
    return out

## Nearest hero the beam is touching, or null when it is aimed at empty space. Never self.
func pick_target():
    var best = null
    var best_d := 1.0e9
    if not hero.is_inside_tree():
        return null
    var end := aim_end()
    var a: Vector3 = hero.eye_position()
    for h in heroes_along(end, false) + heroes_along(end, true):
        var d: float = a.distance_to(h.global_position)
        if d < best_d:
            best = h
            best_d = d
    return best

## Enemies the beam touches on the way to `t` (a hero) or to a world point.
func enemies_on_beam(t) -> Array:
    if t is Vector3:
        return heroes_along(t, true)
    if t == null or t == hero or not is_instance_valid(t):
        return []
    return heroes_along(t.global_position + Vector3(0, 1.0, 0), true)

## "damage" if `t` is an enemy, "heal" if an ally, "empty" if there is nobody (gray beam).
func mode_for(t) -> String:
    if t == null or t == hero or not is_instance_valid(t):
        return "empty"
    return "damage" if t.team != hero.team else "heal"

func mode_color(mode: String) -> Color:
    if mode == "damage":
        return Color(String(def.get("color_damage", "#ff3b3b")))
    if mode == "empty":
        return Color(String(def.get("color_empty", "#9aa3ad")))
    return Color(String(def.get("color_heal", def.get("beam_color", "#5cb8ff"))))

func tick(dt: float) -> void:
    super.tick(dt)
    if left <= 0.0:
        return
    left -= dt
    if hero.dead:
        cancel()
        return
    var end := aim_end()
    target = pick_target()
    var hps := float(def.get("hps", 60.0))
    for a in heroes_along(end, false):
        a.heal(hps * dt, hero, id)
    var foes := heroes_along(end, true)
    hit_enemy = not foes.is_empty()
    var dps := float(def.get("enemy_dps", 0.0))
    if dps > 0.0:
        for e in foes:
            e.take_damage(dps * dt * hero.damage_mult(), hero, e.global_position + Vector3(0, 1.2, 0), "ability", id)
    if left <= 0.0:
        left = 0.0
        cooldown.remaining = minf(cooldown.remaining, cooldown.duration)

# ---------------------------------------------------------------------------------------------
# Visual ribbon. channel_visible() is cooldown.remaining > cooldown.duration. The ribbon follows the
# aim: a hero it touches, or the aim point when it hits nobody (gray). On a client, snapshot field 18
# (heal_target_id) is used when that entity resolves.
const FADE := 0.2
var vis_alpha := 0.0                ## 0..1 current ribbon opacity
var vis_target = null               ## hero the ribbon points at (self = aura)
var ribbon: Node3D                  ## top-level node in the world: outer ribbon + inner core
var aura: MeshInstance3D            ## self-heal glow
var beads: Array = []               ## flowing note beads along the beam; last one = glow on target
const BEADS := 6
const SEG := 14                     ## ribbon segments (a travelling sound wave)
const WAVE := 0.22                  ## wave amplitude (m): keeps the beam visible end-on
var _vis_t := 0.0
var vis_mode := "heal"
var _applied_mode := ""

## True while the channel runs. While channelling, remaining is cooldown + time left, so it is above the cooldown length.
func channel_visible() -> bool:
    if hero.dead:
        return false
    return cooldown.remaining > cooldown.duration + 0.001

func beam_start() -> Vector3:
    return hero.beam_origin() if hero.is_inside_tree() else hero.global_position + Vector3(0, 1.1, 0)

func beam_end() -> Vector3:
    if vis_target != null and is_instance_valid(vis_target) and vis_target != hero:
        return vis_target.global_position + Vector3(0, 1.0, 0)
    return vis_end

## Point on the beam at fraction f: a sine "sound wave" (vertical), pinned to 0 at both ends.
func wave_point(a: Vector3, b: Vector3, f: float) -> Vector3:
    var env := sin(f * PI)
    return a.lerp(b, f) + Vector3(0, sin(f * TAU * 2.0 - _vis_t * 10.0) * WAVE * env, 0)

func _mat(c: Color, emis: float) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.no_depth_test = true          # never hidden behind the healer's own model
    m.render_priority = 10
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    m.albedo_color = c
    m.emission_enabled = true
    m.emission = Color(c.r, c.g, c.b) * emis
    return m

func _build_vis(world: Node) -> void:
    _applied_mode = "heal"
    ribbon = Node3D.new()
    ribbon.name = "EncoreRibbon"
    ribbon.top_level = true
    for k in SEG * 2:
        var mi := MeshInstance3D.new()
        var bm := BoxMesh.new()
        var core := k % 2 == 1
        bm.size = Vector3(0.1, 0.1, 1.0) if core else Vector3(0.3, 0.07, 1.0)
        mi.mesh = bm
        var c := Color("#f4f8ff") if core else mode_color("heal")
        var ba := 1.0 if core else 0.85
        mi.material_override = _mat(Color(c.r, c.g, c.b, ba), 3.0 if core else 2.0)
        mi.set_meta("base_a", ba)
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        mi.top_level = true
        ribbon.add_child(mi)
    world.add_child(ribbon)
    # flowing "notes" travelling along the beam + a glow on the target: visible even when the
    # camera looks straight down the beam (over-the-shoulder view)
    beads = []
    for i in BEADS + 1:
        var b := MeshInstance3D.new()
        var bs := SphereMesh.new()
        bs.radius = 0.18 if i < BEADS else 0.6
        bs.height = bs.radius * 2.0
        bs.radial_segments = 10
        bs.rings = 5
        b.mesh = bs
        var c := Color("#f4f8ff") if i % 2 == 0 else mode_color("heal")
        if i == BEADS:
            c = mode_color("heal").darkened(0.15)
        var ba := 0.95 if i < BEADS else 0.6
        b.material_override = _mat(Color(c.r, c.g, c.b, ba), 2.5)
        b.set_meta("base_a", ba)
        b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        b.top_level = true
        world.add_child(b)
        beads.append(b)
    aura = MeshInstance3D.new()
    aura.name = "EncoreAura"
    var sm := SphereMesh.new()
    sm.radius = 0.75
    sm.height = 1.5
    aura.mesh = sm
    aura.material_override = _mat(Color(0.72, 0.89, 1.0, 0.25), 1.5)
    aura.set_meta("base_a", 0.25)
    aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    aura.top_level = true
    world.add_child(aura)

func _set_alpha(mi: MeshInstance3D, a: float) -> void:
    var m := mi.material_override as StandardMaterial3D
    m.albedo_color.a = float(mi.get_meta("base_a")) * a

## Called every rendered frame by Hero._process (all net roles).
func visual_process(dt: float) -> void:
    _vis_t += dt
    var on := channel_visible()
    if on:
        var far: Vector3 = aim_end()
        vis_end = far
        vis_target = pick_target()
        if Net.is_client():
            var rt = Net.entities.get(int(hero.heal_target_id))
            if is_instance_valid(rt) and rt != hero:
                vis_target = rt
        var foes: Array = heroes_along(far, true)
        var allies: Array = heroes_along(far, false)
        if not foes.is_empty():
            vis_mode = "damage"
        elif not allies.is_empty():
            vis_mode = "heal"
        else:
            vis_mode = "empty"
            vis_target = null
        vis_alpha = minf(1.0, vis_alpha + dt / 0.05)
    else:
        vis_alpha = maxf(0.0, vis_alpha - dt / FADE)
    if vis_target != null and not is_instance_valid(vis_target):
        vis_target = null
    if not hero.is_inside_tree() or hero.get_parent() == null:
        return
    if ribbon == null or not is_instance_valid(ribbon):
        if vis_alpha <= 0.0:
            return
        _build_vis(hero.get_parent())
    var show_ribbon: bool = vis_alpha > 0.0 and (vis_target == null or vis_target != hero)
    var show_aura: bool = false
    ribbon.visible = show_ribbon
    aura.visible = show_aura
    for bd in beads:
        bd.visible = show_ribbon
    if show_ribbon and vis_mode != _applied_mode:
        _apply_mode_colors()
    if show_ribbon:
        var a := beam_start()
        var b := beam_end()
        ribbon.global_position = (a + b) * 0.5
        var pulse := 1.0 + 0.15 * sin(_vis_t * 18.0)
        var pts: Array = []
        for k in SEG + 1:
            pts.append(wave_point(a, b, float(k) / SEG))
        var kids := ribbon.get_children()
        for k in SEG:
            var p0: Vector3 = pts[k]
            var p1: Vector3 = pts[k + 1]
            var seg_len := maxf(p0.distance_to(p1), 0.01)
            var up := Vector3.UP if absf((p1 - p0).normalized().y) < 0.99 else Vector3.RIGHT
            for c in 2:
                var mi: MeshInstance3D = kids[k * 2 + c]
                mi.global_position = (p0 + p1) * 0.5
                mi.look_at(p1, up)
                mi.scale = Vector3(pulse, pulse, seg_len * 1.08)
                _set_alpha(mi, vis_alpha)
        for k in beads.size():
            var bd: MeshInstance3D = beads[k]
            if k < BEADS:
                var f := fposmod(_vis_t * 1.6 + float(k) / BEADS, 1.0)
                bd.global_position = wave_point(a, b, f)
            else:
                bd.global_position = b
                bd.scale = Vector3.ONE * (1.0 + 0.12 * sin(_vis_t * 12.0))
            _set_alpha(bd, vis_alpha)
    if show_aura:
        aura.global_position = hero.global_position + Vector3(0, 1.0, 0)
        aura.scale = Vector3.ONE * (1.0 + 0.08 * sin(_vis_t * 10.0))
        _set_alpha(aura, vis_alpha)

## Recolours the outer ribbon, the coloured beads and the target glow. The white core stays white.
func _apply_mode_colors() -> void:
    _applied_mode = vis_mode
    var c := mode_color(vis_mode)
    var kids := ribbon.get_children()
    for k in kids.size():
        if k % 2 == 0:
            _tint(kids[k], c, 2.0)
    for i in beads.size():
        if i == BEADS:
            _tint(beads[i], c.darkened(0.15), 2.5)
        elif i % 2 == 1:
            _tint(beads[i], c, 2.5)

func _tint(mi: MeshInstance3D, c: Color, emis: float) -> void:
    var m := mi.material_override as StandardMaterial3D
    m.albedo_color = Color(c.r, c.g, c.b, m.albedo_color.a)
    m.emission = Color(c.r, c.g, c.b) * emis

func free_visuals() -> void:
    for n in [ribbon, aura] + beads:
        if n != null and is_instance_valid(n):
            n.queue_free()
    ribbon = null
    aura = null
    beads = []
    _applied_mode = ""
