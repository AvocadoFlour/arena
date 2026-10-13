class_name Hero
extends CharacterBody3D
## Generic hero body. Data comes from a hero definition JSON (INTERFACES.md section 2).
## Driven ONLY by an input source: any object with poll(hero) -> InputFrame.

const TEAM_COLORS := [Color("#2f7dff"), Color("#ff4040")]
const RESPAWN_TIME := 3.0

var def: Dictionary
var team := 0
var display_name := "Hero"
var health: Health
var weapon: Weapon
var ult: UltMeter
var abilities: Dictionary = {}       ## slot -> Ability
var input_source = null
var aim_camera: Camera3D = null      ## if set, shots are traced from the camera centre (crosshair)
var extra_spread_deg := 0.0
var damage_scale := 1.0
var yaw := 0.0
var pitch := 0.0
var dead := false
var respawn_left := 0.0
var spawn_point := Vector3.ZERO
var dash_time := 0.0
var dash_vel := Vector3.ZERO
var slam_pending := false
var last_wish := Vector3.ZERO
var move_cfg: Dictionary = {}
var slow_mult := 1.0                 ## movement speed multiplier from slows (1 = none)
var slow_left := 0.0
var charge_hits: Array = []          ## heroes already hit by the current charge
var buff_mult := 1.0                 ## outgoing damage multiplier from buffs (stacks with damage_scale)
var buff_left := 0.0
var knockback_immune := false        ## set while a buff grants it; knockback() is ignored
var overheal := 0.0                  ## temporary HP above max, absorbed before health, decays
var overheal_decay := 0.0            ## overheal lost per second
var combo_step := 0                  ## melee primary: index in the combo
var combo_left := 0.0                ## melee primary: time left to continue the combo
var _rng := RandomNumberGenerator.new()
var net_id := -1                   ## network id (Net registry), -1 = unregistered
## Core hook (heroes request): when true, _die() keeps the body visible (collision still off) so the
## Visual node can play a death animation on the live model; hero code hides it when done (visible = false).
var keep_body_when_dead := false
var heal_target_id := -1          ## CLIENT: replicated heal-beam target (net id; -1 = none/self), visual only
var net_role := "auth"             ## "auth" simulates fully; "predicted" (client's own hero) moves only; "puppet" is driven by snapshots
var _muzzle: Node3D
## Skinned GLB model (hero JSON "model_scene"); null = primitive model. `--primitive_models` forces primitives.
static var use_primitive_models := OS.get_cmdline_user_args().has("--primitive_models")
var model: HeroModel
var _was_dead := false
var _anim_casts := 0                 ## cumulative ability casts seen (from replicated cooldown jumps)
var _vis: Node3D                     ## visual root (animated); never affects collision/gameplay
var _anim_parts: Array = []          ## [node, kind, base_rotation, phase]
var _anim_t := 0.0
## Attack-visual state, derived ONLY from replicated fields (weapon.ammo, weapon.reloading(), ability
## cooldown.remaining) so puppets on clients animate exactly like the host's sim. Client-side only.
var _anim_ammo := -1                 ## last seen ammo; a drop = shot/swing fired
var _anim_atk := 0.0                 ## 1 right after a shot/swing -> 0
var _anim_shots := 0                 ## shots seen (parity alternates the sword swing side)
var _anim_cds: Dictionary = {}       ## slot -> last seen cooldown.remaining
var _anim_cast := 0.0                ## 1 right after an ability/ult was used -> 0
var _anim_cast_slot := ""            ## slot of the latest cast seen (replicated cooldown jump)
var _anim_finisher := false          ## current swing is the combo finisher (from replicated combo_step)
var _anim_dash := 0.0                ## 0..1 dash visual weight (from replicated dash_time)
var _streak: MeshInstance3D          ## dash streak (client-side visual)
var _team_mats: Array = []

static func from_def(path: String) -> Hero:
    var h := Hero.new()
    h.def = JSON.parse_string(FileAccess.get_file_as_string(path))
    h._build()
    return h

func _build() -> void:
    _rng.randomize()
    display_name = def.get("name", "Hero")
    move_cfg = def.get("movement", {})
    health = Health.new(float(def.get("max_hp", 200)))
    weapon = Weapon.new(def.get("primary", {}))
    ult = UltMeter.new(float(def.get("ultimate_cost", 500)))
    var abl: Dictionary = def.get("abilities", {})
    for slot in abl:
        abilities[slot] = AbilityRegistry.create(self, abl[slot])
    var col: Dictionary = def.get("collider", {})
    var cs := CollisionShape3D.new()
    var cap := CapsuleShape3D.new()
    cap.radius = float(col.get("radius", 0.4))
    cap.height = float(col.get("height", 1.8))
    cs.shape = cap
    cs.position.y = cap.height * 0.5
    add_child(cs)
    floor_snap_length = 0.25
    floor_max_angle = deg_to_rad(50)
    _build_model(def.get("model", []))
    _build_scene_model()
    add_to_group("heroes")
    set_team(team)

## Model parts (INTERFACES §2 "model"), plus optional visual-only keys:
## "rot":[x,y,z] degrees, "scale":[x,y,z], "pivot":[x,y,z] (part rotates about this point),
## "anim": "tail" | "weapon" | "leg_l" | "leg_r" | "arm_l" | "arm_r" | "head".
func _build_model(parts: Array) -> void:
    _vis = Node3D.new()
    _vis.name = "Visual"
    add_child(_vis)
    for p in parts:
        var mi := MeshInstance3D.new()
        match String(p.shape):
            "capsule":
                var m := CapsuleMesh.new()
                m.radius = p.radius
                m.height = maxf(p.height, p.radius * 2.0)
                m.radial_segments = 12
                m.rings = 4
                mi.mesh = m
            "sphere":
                var m2 := SphereMesh.new()
                m2.radius = p.radius
                m2.height = p.radius * 2.0
                m2.radial_segments = 12
                m2.rings = 6
                mi.mesh = m2
            _:
                var m3 := BoxMesh.new()
                m3.size = Vector3(p.size[0], p.size[1], p.size[2])
                mi.mesh = m3
        var mat := StandardMaterial3D.new()
        mat.roughness = float(p.get("roughness", 0.75))
        mat.metallic = float(p.get("metallic", 0.0))
        if p.color == "team":
            _team_mats.append(mat)
        else:
            mat.albedo_color = Color(p.color)
        if p.has("emission"):
            mat.emission_enabled = true
            mat.emission = Color(p.emission)
        mi.material_override = mat
        var pos := Vector3(p.pos[0], p.pos[1], p.pos[2])
        if p.has("rot"):
            mi.rotation_degrees = Vector3(p.rot[0], p.rot[1], p.rot[2])
        if p.has("scale"):
            mi.scale = Vector3(p.scale[0], p.scale[1], p.scale[2])
        if p.has("pivot"):
            var pv := Node3D.new()
            pv.position = Vector3(p.pivot[0], p.pivot[1], p.pivot[2])
            _vis.add_child(pv)
            pv.add_child(mi)
            mi.position = pos - pv.position
            if p.has("anim"):
                _anim_parts.append([pv, String(p.anim), pv.rotation, pos.x * 3.1])
        else:
            mi.position = pos
            _vis.add_child(mi)
            if p.has("anim"):
                _anim_parts.append([mi, String(p.anim), mi.rotation, pos.x * 3.1])
        if p.get("muzzle", false):
            _muzzle = Node3D.new()
            _muzzle.position = pos + Vector3(0, 0, -0.4)
            add_child(_muzzle)   # not under _vis: shot origin is never animated

## Replaces the primitive parts with the skinned GLB model when the def has "model_scene" (and
## primitives are not forced). The muzzle node from the primitive def is kept (gameplay-neutral anchor).
func _build_scene_model() -> void:
    if use_primitive_models or not def.has("model_scene"):
        return
    var m := HeroModel.create(def.model_scene)
    if m == null:
        push_warning("model_scene failed to load, using primitive model: %s" % def.model_scene)
        return
    for c in _vis.get_children():
        _vis.remove_child(c)
        c.free()
    _anim_parts.clear()
    _streak = null
    model = m
    _vis.add_child(model)
    keep_body_when_dead = true   # core hook (INTERFACES §3): body stays visible, collision off, while "death" plays

## Where beams/tracers leave the hero: the animated mic-wand tip on the 3D model, else the muzzle.
func beam_origin() -> Vector3:
    if model and model.wand_tip and model.wand_tip.is_inside_tree():
        return model.wand_tip.global_position
    if _muzzle and _muzzle.is_inside_tree():
        return _muzzle.global_position
    return eye_position()

## Procedural animation, render-rate, read-only on existing state (velocity, on-floor, weapon
## cooldown, dash/leap timers). Changes only _vis transforms, so it is safe for networking.
func _process(dt: float) -> void:
    for ab in abilities.values():
        if ab.has_method("visual_process"):
            ab.visual_process(dt)   # ability visuals (e.g. heal ribbon fade-out also runs while dead)
    if model and dead != _was_dead:   # replicated `dead` edges: death anim on the live body (core keeps it visible)
        if dead:
            model.play_death()
        else:
            model.revive()
    _was_dead = dead
    if _vis == null or dead:
        return
    _anim_t += dt
    var local_v := Basis(Vector3.UP, rotation.y).inverse() * velocity   # yaw-only, works outside the tree too
    var spd := float(move_cfg.get("speed", 7.0))
    var run := clampf(Vector2(local_v.x, local_v.z).length() / maxf(spd, 0.1), 0.0, 1.5)
    var grounded := is_on_floor()
    var fwd := clampf(-local_v.z / maxf(spd, 0.1), -1.5, 1.5)
    var side := clampf(local_v.x / maxf(spd, 0.1), -1.5, 1.5)
    var air := 0.0 if grounded else clampf(velocity.y / 10.0, -1.0, 1.0)
    var stride := _anim_t * (6.0 + 6.0 * run)
    # body: idle breathing bob, run bounce, lean into motion, tilt when dashing
    var bob := sin(_anim_t * 2.2) * 0.025 + (absf(sin(stride)) * 0.06 * run if grounded else 0.0)
    if model:
        bob = 0.0   # the skeletal idle/run animations carry the body motion
    _vis.position.y = lerpf(_vis.position.y, bob, minf(1.0, dt * 20.0))
    _track_attack_state(dt)
    _update_streak()
    if model:
        var healing := false
        for ab in abilities.values():
            if ab.has_method("channel_visible") and ab.channel_visible():
                healing = true
        model.drive({"run": run, "fwd": fwd, "side": side, "air": air, "shots": _anim_shots,
            "finisher": _anim_finisher, "casts": _anim_casts, "cast_slot": _anim_cast_slot, "healing": healing}, dt)
    var lean_x := -fwd * 0.16 - 0.3 * _anim_dash - (0.2 * sin(_anim_atk * PI) if _anim_finisher else 0.0)
    var lean_z := side * 0.12
    _vis.rotation.x = lerpf(_vis.rotation.x, lean_x, minf(1.0, dt * 10.0))
    _vis.rotation.z = lerpf(_vis.rotation.z, lean_z, minf(1.0, dt * 10.0))
    # attack: 1 right after a shot/swing -> 0 when the next is allowed
    var atk := _anim_atk
    var melee := String(def.get("primary", {}).get("type", "hitscan")) == "melee"
    var combo_side := 1.0 if _anim_shots % 2 == 1 else -1.0
    var reload_droop := 0.35 if weapon and weapon.reloading() and not melee else 0.0
    for a in _anim_parts:
        var n: Node3D = a[0]
        var base: Vector3 = a[2]
        var ph: float = a[3]
        var r := base
        match String(a[1]):
            "tail":
                # trail behind with speed, lift when airborne, gentle sway always
                r.x = base.x - fwd * 0.55 - air * 0.4 + sin(_anim_t * 2.4 + ph) * 0.08 + sin(stride) * 0.06 * run
                r.z = base.z + side * 0.35 + sin(_anim_t * 1.7 + ph) * 0.1
            "weapon":
                if melee:
                    var sw := sin(atk * PI)   # 0 -> 1 -> 0 over the swing
                    if _anim_finisher:   # overhead two-handed slam, no side sweep
                        r.x = base.x - sw * 2.3
                        r.z = base.z + sw * 0.25
                    else:
                        r.x = base.x - sw * 1.4 + (atk - 0.5) * 0.4 * sw
                        r.y = base.y + sw * 0.9 * combo_side
                else:
                    r.x = base.x + atk * 0.18 + reload_droop   # recoil kick; dips while reloading
            "leg_l":
                r.x = base.x + sin(stride) * 0.6 * minf(run, 1.0) + air * 0.4
            "leg_r":
                r.x = base.x - sin(stride) * 0.6 * minf(run, 1.0) + air * 0.4
            "arm_l":
                r.x = base.x - sin(stride) * 0.4 * minf(run, 1.0) + sin(_anim_t * 2.2) * 0.04
            "arm_r":
                r.x = base.x + sin(stride) * 0.4 * minf(run, 1.0) + sin(_anim_t * 2.2 + 1.0) * 0.04 - sin(_anim_cast * PI) * 1.2
            "head":
                r.x = base.x + sin(_anim_t * 2.2 + 0.5) * 0.04 + fwd * 0.08
                r.y = base.y + sin(_anim_t * 0.7) * 0.06
        n.rotation = r

## Detects shots and ability casts from replicated state changes (works for auth, predicted and puppet).
func _track_attack_state(dt: float) -> void:
    if weapon:
        var a := weapon.ammo
        if _anim_ammo >= 0 and a < _anim_ammo:
            _anim_shots += _anim_ammo - a
            _anim_atk = 1.0
            _anim_finisher = is_finisher_step(combo_step)
        _anim_ammo = a
        var dur := maxf(minf(weapon.fire_interval, 0.5), 0.1)
        _anim_atk = maxf(0.0, _anim_atk - dt / dur)
    for slot in abilities:
        var rem: float = abilities[slot].cooldown.remaining
        if _anim_cds.has(slot) and rem > float(_anim_cds[slot]) + 0.05:
            _anim_cast = 1.0
            _anim_casts += 1
            _anim_cast_slot = String(slot)
        _anim_cds[slot] = rem
    _anim_cast = maxf(0.0, _anim_cast - dt / 0.35)
    var target := 1.0 if dash_time > 0.0 else 0.0
    _anim_dash = move_toward(_anim_dash, target, dt / (0.05 if target > 0.0 else 0.2))

## True if the swing that left `step` (post-increment combo_step, as replicated) was the melee finisher.
func is_finisher_step(step: int) -> bool:
    var p: Dictionary = def.get("primary", {})
    if String(p.get("type", "")) != "melee":
        return false
    var n: int = p.get("combo", [1.0]).size()
    return n > 1 and step > 0 and step % n == 0

func _update_streak() -> void:
    if _anim_dash <= 0.01:
        if _streak:
            _streak.visible = false
        return
    if _streak == null:
        _streak = MeshInstance3D.new()
        _streak.name = "DashStreak"
        var bm := BoxMesh.new()
        bm.size = Vector3(0.7, 1.3, 1.0)
        _streak.mesh = bm
        var m := StandardMaterial3D.new()
        m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        m.albedo_color = Color(1, 1, 1, 0.3)
        _streak.material_override = m
        _streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        _vis.add_child(_streak)
    _streak.visible = true
    var len := 0.4 + 1.6 * _anim_dash
    _streak.scale = Vector3(1, 1, len)
    _streak.position = Vector3(0, 0.95, 0.35 + len * 0.5)   # trails behind the hero (+z is back)
    var c: Color = TEAM_COLORS[team % TEAM_COLORS.size()]
    (_streak.material_override as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, 0.35 * _anim_dash)

func _exit_tree() -> void:
    for ab in abilities.values():
        if ab.has_method("free_visuals"):
            ab.free_visuals()

func set_team(t: int) -> void:
    team = t
    for m in _team_mats:
        m.albedo_color = TEAM_COLORS[t % TEAM_COLORS.size()]

func eye_position() -> Vector3:
    return global_position + Vector3(0, 1.6, 0)

func look_dir() -> Vector3:
    return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))

func _physics_process(dt: float) -> void:
    if net_role == "puppet":
        return
    if net_role == "predicted":
        _predict_step(dt)
        return
    if dead:
        respawn_left -= dt
        if respawn_left <= 0.0:
            respawn()
        return
    var f: InputFrame = input_source.poll(self) if input_source else InputFrame.new()
    yaw = wrapf(yaw + f.look.x, -PI, PI)
    pitch = clampf(pitch + f.look.y, -1.3, 1.3)
    rotation.y = yaw
    weapon.tick(dt)
    for slot in abilities:
        var ab = abilities[slot]
        var was_cooling: bool = ab.cooldown.remaining > 0.0
        ab.tick(dt)
        if was_cooling and ab.cooldown.remaining <= 0.0:
            Events.ability_ready.emit(self, slot)   # only a cooldown running out; direct resets don't fire
    var wish := global_transform.basis * Vector3(f.move.x, 0, -f.move.y)
    wish.y = 0.0
    last_wish = wish
    if f.reload:
        weapon.start_reload()
    if f.ability1:
        _use("ability1")
    if f.ability2:
        _use("ability2")
    if f.ultimate:
        _use("ultimate")
    var was_air := not is_on_floor()
    _tick_buffs(dt)
    if slow_left > 0.0:
        slow_left -= dt
        if slow_left <= 0.0:
            slow_mult = 1.0
    velocity = Motion.step_velocity(velocity, wish, is_on_floor(), f.jump, effective_move_cfg(), dt)
    if dash_time > 0.0:
        dash_time -= dt
        velocity.x = dash_vel.x
        velocity.z = dash_vel.z
        velocity.y = maxf(velocity.y, 0.0)
    move_and_slide()
    if is_on_floor():
        if slam_pending:
            slam_pending = false
            for ab in abilities.values():
                ab.on_landed()
    if f.fire:
        _try_fire()
    if global_position.y < -25.0:
        _die(null, "fall")
    var _unused = was_air

## Client-side prediction of our own hero: look + movement only; the host owns everything else.
func _predict_step(dt: float) -> void:
    if dead or input_source == null:
        return
    var f: InputFrame = input_source.poll(self)
    yaw = wrapf(yaw + f.look.x, -PI, PI)
    pitch = clampf(pitch + f.look.y, -1.3, 1.3)
    rotation.y = yaw
    var wish := global_transform.basis * Vector3(f.move.x, 0, -f.move.y)
    wish.y = 0.0
    last_wish = wish
    velocity = Motion.step_velocity(velocity, wish, is_on_floor(), f.jump, effective_move_cfg(), dt)
    move_and_slide()
    if input_source.has_method("record_pos"):
        input_source.record_pos(global_position)

func _use(slot: String) -> void:
    if abilities.has(slot) and abilities[slot].activate():
        Events.ability_used.emit(self, slot, abilities[slot].id)

func _try_fire() -> void:
    if not weapon.try_fire():
        return
    var rewound := Net.rewind_for(self)   # lag compensation for remote shooters (host only)
    _fire_shot()
    Net.restore(rewound)

func _fire_shot() -> void:
    if Net.is_online():
        _rng.seed = hash([net_id, Net.tick, weapon.ammo])   # deterministic per-tick spread
    if String(def.get("primary", {}).get("type", "hitscan")) == "melee":
        melee_swing()
        return
    var origin: Vector3
    var dir: Vector3
    if aim_camera:
        origin = aim_camera.global_position
        dir = -aim_camera.global_basis.z
    else:
        origin = eye_position()
        dir = look_dir()
    dir = HitMath.spread_dir(dir, weapon.spread_deg + extra_spread_deg, _rng)
    var end := origin + dir * weapon.max_range
    var q := PhysicsRayQueryParameters3D.create(origin, end)
    q.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(q)
    if not hit.is_empty():
        end = hit.position
        var c = hit.collider
        if c is Hero and c.team != team and not c.dead:
            c.take_damage(weapon.damage * damage_mult(), self, end, "primary")
    var from := beam_origin()
    Fx.tracer(get_parent(), from, end, Color(1, 0.9, 0.4) if team == 0 else Color(1, 0.4, 0.3))

## Outgoing damage multiplier: bot/difficulty scale x active buffs.
func damage_mult() -> float:
    return damage_scale * buff_mult

## Melee primary (hero JSON "primary": {"type":"melee", "damage", "fire_rate", "range", "arc_deg",
## "combo": [mult, ...], "combo_window", "lunge"}). Hits every enemy in the frontal arc.
## Returns number of heroes hit. Successive swings within combo_window step through `combo`.
func melee_swing() -> int:
    var p: Dictionary = def.get("primary", {})
    var combo: Array = p.get("combo", [1.0])
    if combo_left <= 0.0:
        combo_step = 0
    var mult := float(combo[combo_step % combo.size()])
    var final_hit := combo_step % combo.size() == combo.size() - 1
    combo_step += 1
    combo_left = float(p.get("combo_window", 0.8))
    var rng := float(p.get("range", 3.0))
    var arc := deg_to_rad(float(p.get("arc_deg", 100.0))) * 0.5
    var fwd := look_dir()
    fwd = Vector3(fwd.x, 0, fwd.z).normalized()
    var n := 0
    if not is_inside_tree():
        return 0
    # Lunge: if the nearest enemy in the arc is beyond sword range but within `lunge`, dash to it
    # and extend the reach for this swing.
    var lunge := float(p.get("lunge", 0.0))
    if lunge > 0.0:
        var best_d := INF
        for h in get_tree().get_nodes_in_group("heroes"):
            if h == self or h.dead or h.team == team:
                continue
            if MeleeMath.in_arc(global_position, fwd, h.global_position, rng + lunge, deg_to_rad(30.0)):
                best_d = minf(best_d, Vector2(h.global_position.x - global_position.x, h.global_position.z - global_position.z).length())
        if best_d < INF and best_d > rng * 0.8:
            var gap := best_d - rng * 0.6
            dash_time = 0.15
            dash_vel = fwd * gap / dash_time
            rng = best_d + 0.5
    for h in get_tree().get_nodes_in_group("heroes"):
        if h == self or h.dead or h.team == team:
            continue
        if MeleeMath.in_arc(global_position, fwd, h.global_position, rng, arc):
            h.take_damage(weapon.damage * mult * damage_mult(), self, h.global_position + Vector3(0, 1.2, 0), "primary")
            if final_hit and h.has_method("knockback"):
                h.knockback(fwd * float(p.get("finisher_knockback", 6.0)) + Vector3(0, 3, 0))
            n += 1
    var col := Color(1, 0.85, 0.4) if final_hit else Color(0.9, 0.9, 1.0)
    Fx.ring(get_parent(), global_position + Vector3(0, 1.1, 0) + fwd * rng * 0.5, rng * 0.5, col, 0.15)
    return n

## External push (charges, finishers). Ignored while knockback_immune.
func knockback(v: Vector3) -> void:
    if knockback_immune or dead:
        return
    velocity += v

## Temporary buff: outgoing damage x mult, optional knockback immunity, for dur seconds.
func apply_buff(mult: float, dur: float, kb_immune: bool) -> void:
    if dead:
        return
    buff_mult = maxf(buff_mult, mult)
    buff_left = maxf(buff_left, dur)
    if kb_immune:
        knockback_immune = true

## Temporary HP above max (absorbed first), decaying to 0 over `dur` seconds.
func add_overheal(amount: float, dur: float) -> void:
    if dead or amount <= 0.0:
        return
    overheal = maxf(overheal, amount)
    overheal_decay = overheal / maxf(dur, 0.01)

func _tick_buffs(dt: float) -> void:
    if combo_left > 0.0:
        combo_left -= dt
    if buff_left > 0.0:
        buff_left -= dt
        if buff_left <= 0.0:
            buff_mult = 1.0
            knockback_immune = false
    if overheal > 0.0:
        overheal = maxf(0.0, overheal - overheal_decay * dt)

func clear_buffs() -> void:
    buff_mult = 1.0
    buff_left = 0.0
    knockback_immune = false
    overheal = 0.0
    combo_step = 0
    combo_left = 0.0

## Movement config with active slows applied.
func effective_move_cfg() -> Dictionary:
    if slow_mult >= 1.0:
        return move_cfg
    var c := move_cfg.duplicate()
    c["speed"] = float(move_cfg.get("speed", 7.0)) * slow_mult
    return c

## Slow movement to mult x speed for dur seconds. Stronger/longer slow wins.
func apply_slow(mult: float, dur: float) -> void:
    if dead:
        return
    if slow_left <= 0.0 or mult < slow_mult:
        slow_mult = clampf(mult, 0.0, 1.0)
    slow_left = maxf(slow_left, dur)

## Restore health. Returns amount actually healed.
## Heals up to max HP; returns the HP actually restored. Emits Events.healed (host/offline only) when > 0.
func heal(amount: float, source = null, ability_id := "") -> float:
    if dead or amount <= 0.0 or not Net.is_authority():
        return 0.0
    var before := health.hp
    health.heal(amount)
    var got := health.hp - before
    if got > 0.0:
        Events.healed.emit({"source": source, "target": self, "amount": got, "ability_id": ability_id})
    return got

## Area damage to enemies (used by abilities). Returns number of heroes hit.
func aoe(center: Vector3, radius: float, dmg: float, kind: String, ability_id := "") -> int:
    var n := 0
    for h in get_tree().get_nodes_in_group("heroes"):
        if h == self or h.dead or h.team == team:
            continue
        var amt := HitMath.aoe_damage(center, radius, dmg, h.global_position + Vector3(0, 0.9, 0))
        if amt > 0.0:
            h.take_damage(amt * damage_mult(), self, h.global_position + Vector3(0, 1.2, 0), kind, ability_id)
            n += 1
    return n

## Damage contract (INTERFACES.md section 3). Returns damage actually applied.
## ability_id: the source ability's id ("" = primary weapon). Carried in damage_dealt / killed (INTERFACES §4).
func take_damage(amount: float, source, pos: Vector3, kind: String, ability_id := "") -> float:
    if dead or not Net.is_authority():   # THE authority check: only the host/offline sim applies damage
        return 0.0
    var absorbed := 0.0
    if overheal > 0.0 and amount > 0.0:
        absorbed = minf(overheal, amount)
        overheal -= absorbed
        amount -= absorbed
    var d := health.apply(amount) + absorbed
    if d <= 0.0:
        return 0.0
    var killed := health.is_dead()
    Events.damage_dealt.emit({"source": source, "target": self, "amount": d, "pos": pos, "kind": kind, "killed": killed, "ability_id": ability_id, "crit": false})
    if source and source.has_method("on_damage_dealt"):
        source.on_damage_dealt(d)
    if killed:
        _die(source, kind, ability_id)
    return d

func on_damage_dealt(d: float) -> void:
    ult.add(d)

func _die(killer, kind: String, ability_id := "") -> void:
    if dead:
        return
    dead = true
    health.hp = 0.0
    visible = keep_body_when_dead
    collision_layer = 0
    velocity = Vector3.ZERO
    respawn_left = RESPAWN_TIME
    slow_mult = 1.0
    slow_left = 0.0
    clear_buffs()
    Events.killed.emit({"killer": killer, "victim": self, "kind": kind, "ability_id": ability_id})

func respawn() -> void:
    dead = false
    health.reset()
    weapon.ammo = weapon.mag_size
    global_position = spawn_point
    velocity = Vector3.ZERO
    visible = true
    collision_layer = 1
    Events.respawned.emit(self)
