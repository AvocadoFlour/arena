extends Ability
## Channelled beam: for `duration` seconds the hero nearest the aim line within `range` and `cone_deg`
## is the target (ally or enemy). An ally, or the caster if nobody is there, is healed at `hps`.
## An enemy takes `enemy_dps` and the ribbon is drawn in `color_damage` (red) instead of `color_heal`.
var left := 0.0
var target = null

func _do() -> bool:
    left = float(def.get("duration", 3.0))
    return true

func channeling() -> bool:
    return left > 0.0

## Hero nearest to the look ray inside range/cone (either team); falls back to self.
func pick_target():
    var best = null
    var best_ang := deg_to_rad(float(def.get("cone_deg", 15.0)))
    var rng := float(def.get("range", 15.0))
    if hero.is_inside_tree():
        var eye: Vector3 = hero.eye_position()
        var look: Vector3 = hero.look_dir()
        for h in hero.get_tree().get_nodes_in_group("heroes"):
            if h == hero or h.dead or h.get_world_3d() != hero.get_world_3d():
                continue
            var to: Vector3 = h.global_position + Vector3(0, 1.0, 0) - eye
            if to.length() > rng:
                continue
            var a := look.angle_to(to)
            if a <= best_ang:
                best_ang = a
                best = h
    return best if best != null else hero

## "damage" when the beam is on an enemy, otherwise "heal". Same rule on host and clients.
func mode_for(t) -> String:
    if t != null and is_instance_valid(t) and t != hero and t.team != hero.team:
        return "damage"
    return "heal"

func mode_color(mode: String) -> Color:
    if mode == "damage":
        return Color(String(def.get("color_damage", "#ff3b3b")))
    return Color(String(def.get("color_heal", def.get("beam_color", "#5cb8ff"))))

func tick(dt: float) -> void:
    super.tick(dt)
    if left <= 0.0:
        return
    left -= dt
    if hero.dead:
        left = 0.0
        return
    target = pick_target()
    if target == hero or target.team == hero.team:
        target.heal(float(def.get("hps", 60.0)) * dt, hero, id)
    else:
        var dps := float(def.get("enemy_dps", 0.0))
        if dps > 0.0:
            target.take_damage(dps * dt * hero.damage_mult(), hero, target.global_position + Vector3(0, 1.2, 0), "ability", id)

# ---------------------------------------------------------------------------------------------
# Visual ribbon (client-side only, never replicated). Driven from REPLICATED state so remote
# players see it: channel active = ability cooldown was triggered < `duration` s ago
# (cooldown.remaining is in every snapshot); target = pick_target() evaluated locally from
# replicated positions / yaw / pitch / team / dead. Same path on host, own hero and puppets.
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

## True while the channel runs, derived only from replicated cooldown.remaining.
func channel_visible() -> bool:
    if hero.dead or cooldown.remaining <= 0.0:
        return false
    return cooldown.duration - cooldown.remaining < float(def.get("duration", 3.0))

func beam_start() -> Vector3:
    return hero.beam_origin() if hero.is_inside_tree() else hero.global_position + Vector3(0, 1.1, 0)

func beam_end() -> Vector3:
    return vis_target.global_position + Vector3(0, 1.0, 0)

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
        vis_target = pick_target()
        if Net.is_client():   # prefer the host's exact target (snapshot heal_target_id); -1 = self/none -> local pick
            var rt = Net.entities.get(int(hero.heal_target_id))
            if is_instance_valid(rt):
                vis_target = rt
        vis_mode = mode_for(vis_target)
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
    var show_ribbon: bool = vis_alpha > 0.0 and vis_target != null and vis_target != hero
    var show_aura: bool = vis_alpha > 0.0 and vis_target == hero
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
