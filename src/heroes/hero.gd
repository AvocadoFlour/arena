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
## On-hit speed bonus (hero JSON primary.on_hit_speed: {bonus, decay}, Niđo's Momentum): a primary swing/shot that
## hits at least one enemy hero sets momentum_left = decay (refresh, no stacking); move speed and acceleration are
## x (1 + bonus x momentum_left / decay), fading linearly to 1. Host-authoritative; clients read the replicated
## fraction from the MomentumLink net prop. Lost on death.
var on_hit_speed := {}
var momentum_left := 0.0
var momentum_refreshes := 0   ## count of refreshes (tests / stats)
var _momentum_prop: Node3D = null
var _trail_t := 0.0
var slow_left := 0.0
## Root (host/offline): while root_left > 0 the hero cannot walk, jump, be pushed horizontally or use the movement
## abilities in ROOT_BLOCKS; aiming, shooting and other abilities still work. Distinct from slow_mult.
var root_left := 0.0
const ROOT_BLOCKS := ["dash", "blink", "leap", "charge", "ride"]
const MountLink := preload("res://src/abilities/mount_link.gd")
const MomentumLink := preload("res://src/abilities/momentum_link.gd")
var ridden_by = null                 ## HOST: the hero riding on our head (ride ability), or null
var _ride = null                     ## the hero's ride ability (Übel's Shift), if any: host-side mount state machine
var charge_hits: Array = []          ## heroes already hit by the current charge
var buff_mult := 1.0                 ## outgoing damage multiplier from buffs (stacks with damage_scale)
var buff_left := 0.0
var knockback_immune := false        ## set while a buff grants it; knockback() is ignored
## Incoming damage reduction (host/offline): key -> [fraction 0..1, seconds left]. Applied in take_damage BEFORE
## overheal and HP, so it can stop a one-shot. Several keys stack multiplicatively; the same key refreshes.
var damage_reductions := {}
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
## Hit reaction (visual only): flinch pivot under _vis + white flash. Created with the visual.
var hit: HitReact
var _flinch: Node3D
var _was_dead := false
var fx: HeroFx                       ## client-side toon ability/weapon effects (visual only)
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
    var prim: Dictionary = def.get("primary", {})
    on_hit_speed = prim.get("on_hit_speed", {})
    # Built-in burst fire: "burst" > 1 -> BurstWeapon (fire_rate inside a burst, burst_delay between bursts)
    weapon = BurstWeapon.new(prim) if int(prim.get("burst", 1)) > 1 else Weapon.new(prim)
    ult = UltMeter.new(float(def.get("ultimate_cost", 500)))
    var abl: Dictionary = def.get("abilities", {})
    for slot in abl:
        abilities[slot] = AbilityRegistry.create(self, abl[slot])
        if abilities[slot].has_method("riding"):
            _ride = abilities[slot]
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
    _build_flinch()
    add_to_group("heroes")
    set_team(team)

## Model parts (INTERFACES §2 "model"), plus optional visual-only keys:
## "rot":[x,y,z] degrees, "scale":[x,y,z], "pivot":[x,y,z] (part rotates about this point),
## "anim": "tail" | "weapon" | "leg_l" | "leg_r" | "arm_l" | "arm_r" | "head".
## Mounted on another hero (ride ability): host/offline from the ride state, clients from the replicated
## MountLink prop. Returns the victim hero or null.
func mounted_on():
    if net_role == "auth" and _ride != null:
        return _ride.victim if _ride.busy() and is_instance_valid(_ride.victim) else null
    return MountLink.victim_of(self)

## Line of sight for close-range and area damage (melee swings + lunge, Clean Cut, leap landings, charges, slams,
## novas, shockwaves and the breakable cover they hit). A ray from `from` to `to` that hits everything hitscan hits
## (default mask: world geometry, shield walls / deployables, breakable cover) but no hero. Clear when nothing is
## in between, or when the first thing hit is `target` itself (a breakable cover block). Host/offline: walls are
## static and heroes are excluded, so it is the same under lag-compensation rewind.
const LOS_CHEST := 1.2   ## ray end points: feet + this (attacker and target hero)

static func los_clear(node: Node3D, from: Vector3, to: Vector3, target = null) -> bool:
    if node == null or not node.is_inside_tree():
        return true
    var q := PhysicsRayQueryParameters3D.create(from, to)
    var ex: Array[RID] = []
    for h in node.get_tree().get_nodes_in_group("heroes"):
        if h is CollisionObject3D:
            ex.append(h.get_rid())
    q.exclude = ex
    var hit := node.get_world_3d().direct_space_state.intersect_ray(q)
    if hit.is_empty():
        return true
    var c = hit.collider
    return target != null and c != null and (c == target or (target is Node and target.is_ancestor_of(c)))

func chest() -> Vector3:
    return global_position + Vector3(0, LOS_CHEST, 0)

## Can my close-range / area attack reach `target` (a hero or a breakable cover block)? The hero I ride is
## always reachable (Übel's ride: she sits on its head).
func can_hit(target, from = null) -> bool:
    if target == null:
        return false
    if target == mounted_on():
        return true
    var o: Vector3 = from if from is Vector3 else chest()
    var to: Vector3 = target.global_position + Vector3(0, LOS_CHEST, 0) if (target is Hero or target.is_in_group("heroes")) else target.global_position
    return Hero.los_clear(self, o, to, target)

## Ends a ride early (stuns and other hard crowd control should call this; knockback and root already do).
func cancel_ride(why := "cancel") -> void:
    if _ride:
        _ride.end_ride(why)

func _build_model(parts: Array) -> void:
    _vis = Node3D.new()
    _vis.name = "Visual"
    add_child(_vis)
    var mz = HeroModel.build_parts(_vis, parts, _team_mats, _anim_parts)
    if mz != null:
        _muzzle = Node3D.new()
        _muzzle.position = mz
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
## Inserts the additive flinch pivot between _vis (lean/bob) and the model parts.
func _build_flinch() -> void:
    _flinch = Node3D.new()
    _flinch.name = "Flinch"
    for c in _vis.get_children():
        c.reparent(_flinch, false)
    _vis.add_child(_flinch)
    hit = HitReact.new(self, _flinch)

func _process(dt: float) -> void:
    if hit:
        hit.process(dt)
    for ab in abilities.values():
        if ab.has_method("visual_process"):
            ab.visual_process(dt)   # ability visuals (e.g. heal ribbon fade-out also runs while dead)
    if model and dead != _was_dead:   # replicated `dead` edges: death anim on the live body (core keeps it visible)
        if dead:
            model.play_death()
        else:
            model.revive()
    _was_dead = dead
    _momentum_trail(dt)
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
    if fx == null and is_inside_tree():
        fx = HeroFx.new(self)
    if fx:
        fx.process(dt)
    _update_streak()
    if model:
        var healing := false
        for ab in abilities.values():
            if ab.has_method("channel_visible") and ab.channel_visible():
                healing = true
        model.drive({"run": run, "fwd": fwd, "side": side, "air": air, "shots": _anim_shots,
            "finisher": _anim_finisher, "casts": _anim_casts, "cast_slot": _anim_cast_slot, "healing": healing,
            "riding": mounted_on() != null}, dt)
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

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if fx:
            fx.disconnect_events()
        if hit:
            hit.disconnect_events()

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
    _flush_heals(dt)
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
    _tick_momentum(dt)
    if slow_left > 0.0:
        slow_left -= dt
        if slow_left <= 0.0:
            slow_mult = 1.0
    var jump := f.jump
    if _ride and _ride.busy():
        _ride.physics(dt, jump)   # leaping onto / riding a head: position comes from the victim
    if _ride and _ride.busy():
        dash_time = 0.0
        root_left = maxf(0.0, root_left - dt)
        if weapon is BurstWeapon:
            BurstWeapon.continue_burst(self)
        if f.fire:
            _try_fire()   # mounted: attacks (and casts above) still work
        return
    if root_left > 0.0:
        root_left = maxf(0.0, root_left - dt)
        wish = Vector3.ZERO
        jump = false
        dash_time = 0.0   # a root cancels a running dash / leap
    velocity = Motion.step_velocity(velocity, wish, is_on_floor(), jump, effective_move_cfg(), dt)
    if rooted():
        velocity.x = 0.0
        velocity.z = 0.0
        velocity.y = minf(velocity.y, 0.0)   # no upward launch (jump, knockback lift); gravity still applies
    if dash_time > 0.0:
        dash_time -= dt
        velocity.x = dash_vel.x
        velocity.z = dash_vel.z
        velocity.y = maxf(velocity.y, 0.0)
    move_and_slide()
    if ridden_by != null and is_instance_valid(ridden_by) and ridden_by._ride:
        ridden_by._ride.reseat()   # someone rides on our head (ride ability)
    if is_on_floor():
        if slam_pending:
            slam_pending = false
            for ab in abilities.values():
                ab.on_landed()
    if weapon is BurstWeapon:
        BurstWeapon.continue_burst(self)   # a started burst completes even if the trigger was released
    if _fire_buffered:
        _fire_buffer_age += dt
        if _fire_buffer_age > FIRE_BUFFER_MAX:
            _fire_buffered = false   # stale (e.g. a very long fall): drop it
        elif not movement_active() and is_on_floor():
            _fire_buffered = false   # landed: the landing impact (on_landed above) already ran, now the swing
            _try_fire()
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
    var under = mounted_on()
    if under != null:   # riding (replicated MountLink): follow the victim's displayed head, no own movement
        var seat: Vector3 = under.global_position + _ride.seat_offset(under) if _ride else under.global_position + Vector3(0, 1.8, 0)
        global_position = global_position.lerp(seat, minf(1.0, dt * 18.0))
        velocity = Vector3.ZERO
        if input_source.has_method("record_pos"):
            input_source.record_pos(global_position)
        return
    velocity = Net.predict_pad(global_position, velocity)   # jump pads, same rule as the host (maps §6)
    velocity = Motion.step_velocity(velocity, wish, is_on_floor(), f.jump, effective_move_cfg(), dt)
    move_and_slide()
    if input_source.has_method("record_pos"):
        input_source.record_pos(global_position)

func _use(slot: String) -> void:
    if rooted() and abilities.has(slot) and String(abilities[slot].def.get("type", "")) in ROOT_BLOCKS:
        return   # movement abilities are locked while rooted
    if abilities.has(slot) and abilities[slot].activate():
        Events.ability_used.emit(self, slot, abilities[slot].id)

## A movement ability is moving us: a leap in the air, a charge, or any dash push (dash, lunge, hop-off).
func movement_active() -> bool:
    if dash_time > 0.0:
        return true
    for ab in abilities.values():
        if (ab.has_method("leaping") and ab.leaping()) or (ab.has_method("charging") and ab.charging()):
            return true
    return false

## Melee swings pressed during a leap / charge / dash are buffered (one swing) and run when it is over and we are
## on the floor - after the landing impact - so the click is not lost and cannot change the trajectory.
const FIRE_BUFFER_MAX := 2.0
var _fire_buffered := false
var _fire_buffer_age := 0.0

func _melee() -> bool:
    return String(def.get("primary", {}).get("type", "hitscan")) == "melee"

func _try_fire() -> void:
    if _melee() and movement_active() and mounted_on() == null:
        if not _fire_buffered:
            _fire_buffered = true
            _fire_buffer_age = 0.0
        return
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
        elif c.is_in_group("destructible"):
            c.take_damage(weapon.damage * damage_mult(), self, end, "primary")   # breakable cover (maps §6)
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
    var under = mounted_on()   # riding: the head below is always in reach (also under lag-compensation rewind)
    # no lunge while mounted, airborne, or while a leap / charge / dash is moving us (it would overwrite dash_vel
    # and replace the leap's arc with a flat hover burst)
    var lunge := 0.0 if (under != null or movement_active() or not is_on_floor()) else float(p.get("lunge", 0.0))
    if lunge > 0.0:
        var best_d := INF
        for h in get_tree().get_nodes_in_group("heroes"):
            if h == self or h.dead or h.team == team:
                continue
            if MeleeMath.in_arc(global_position, fwd, h.global_position, rng + lunge, deg_to_rad(30.0)) and can_hit(h):
                best_d = minf(best_d, Vector2(h.global_position.x - global_position.x, h.global_position.z - global_position.z).length())
        if best_d < INF and best_d > rng * 0.8:
            var gap := best_d - rng * 0.6
            dash_time = 0.15
            dash_vel = fwd * gap / dash_time
            rng = best_d + 0.5
    for h in get_tree().get_nodes_in_group("heroes"):
        if h == self or h.dead or h.team == team:
            continue
        if h == under or (MeleeMath.in_arc(global_position, fwd, h.global_position, rng, arc) and can_hit(h)):
            h.take_damage(weapon.damage * mult * damage_mult(), self, h.global_position + Vector3(0, 1.2, 0), "primary")
            if final_hit and h.has_method("knockback"):
                h.knockback(fwd * float(p.get("finisher_knockback", 6.0)) + Vector3(0, 3, 0))
            n += 1
    for c in get_tree().get_nodes_in_group("destructible"):   # breakable cover in the swing arc
        if c.is_inside_tree() and MeleeMath.in_arc(global_position, fwd, c.global_position, rng + 0.5, arc) and can_hit(c):
            c.take_damage(weapon.damage * mult * damage_mult(), self, c.global_position, "primary")
    if n > 0:
        refresh_momentum()   # one refresh per swing, however many enemies it hit
    var col := Color(1, 0.85, 0.4) if final_hit else Color(0.9, 0.9, 1.0)
    Fx.ring(get_parent(), global_position + Vector3(0, 1.1, 0) + fwd * rng * 0.5, rng * 0.5, col, 0.15)
    return n

## External push (charges, finishers). Ignored while knockback_immune.
func knockback(v: Vector3) -> void:
    if knockback_immune or dead:
        return
    if _ride and _ride.busy():
        _ride.end_ride("knockback")   # a push knocks a rider off (then applies normally)
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

## Take `frac` (0..1) less damage for `dur` s. `key` identifies the source (same key refreshes: max of fraction
## and time; different keys stack multiplicatively). Host/offline gameplay state; HP is what replicates.
func apply_damage_reduction(frac: float, dur: float, key := "default") -> void:
    if dead or dur <= 0.0 or frac <= 0.0:
        return
    var e: Array = damage_reductions.get(key, [0.0, 0.0])
    damage_reductions[key] = [clampf(maxf(e[0], frac), 0.0, 1.0), maxf(e[1], dur)]

## Multiplier applied to incoming damage (1 = none, 0 = immune).
func damage_taken_mult() -> float:
    var m := 1.0
    for k in damage_reductions:
        m *= 1.0 - float(damage_reductions[k][0])
    return clampf(m, 0.0, 1.0)

## Seconds left on a damage reduction (0 if none).
func damage_reduction_left(key := "default") -> float:
    return float(damage_reductions.get(key, [0.0, 0.0])[1])

func _tick_buffs(dt: float) -> void:
    if not damage_reductions.is_empty():
        for k in damage_reductions.keys():
            damage_reductions[k][1] -= dt
            if damage_reductions[k][1] <= 0.0:
                damage_reductions.erase(k)
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
    damage_reductions.clear()
    buff_mult = 1.0
    buff_left = 0.0
    knockback_immune = false
    overheal = 0.0
    combo_step = 0
    combo_left = 0.0

## Movement config with active slows applied.
func effective_move_cfg() -> Dictionary:
    if net_role != "auth" and mounted_on() != null:   # client replays while riding must not move her
        var m := move_cfg.duplicate()
        m["speed"] = 0.0
        m["jump_velocity"] = 0.0
        m["gravity"] = 0.0
        return m
    var bonus := momentum_mult()
    if slow_mult >= 1.0 and bonus <= 1.0:
        return move_cfg
    var c := move_cfg.duplicate()
    c["speed"] = float(move_cfg.get("speed", 7.0)) * slow_mult * bonus   # slows multiply on top of the bonus
    if bonus > 1.0:
        c["accel_ground"] = float(move_cfg.get("accel_ground", 70.0)) * bonus
        c["accel_air"] = float(move_cfg.get("accel_air", 18.0)) * bonus
    return c

## Subtle speed trail while the on-hit bonus runs (all peers, from momentum_frac(): replicated state on clients).
func _momentum_trail(dt: float) -> void:
    var fr := momentum_frac()
    if fr <= 0.05 or not is_inside_tree() or get_parent() == null:
        return
    _trail_t -= dt
    if _trail_t > 0.0:
        return
    _trail_t = 0.06
    var v := Vector3(velocity.x, 0, velocity.z)
    if v.length() < 1.5:
        return
    var back := -v.normalized()
    var c := Color(String(def.get("color", "#40e070"))).lerp(Color.WHITE, 0.4)
    c.a = 0.35 + 0.4 * fr
    ToonFx.streak(get_parent(), global_position + Vector3(0, 0.25, 0), global_position + Vector3(0, 0.25, 0) + back * (0.5 + 0.9 * fr), c, 0.05 + 0.05 * fr, 0.22)

## Fraction (0..1) of the on-hit speed bonus left: host/offline from momentum_left, clients from the net prop.
func momentum_frac() -> float:
    if on_hit_speed.is_empty() or dead:
        return 0.0
    if net_role == "auth":
        return clampf(momentum_left / maxf(float(on_hit_speed.get("decay", 1.0)), 0.001), 0.0, 1.0)
    return MomentumLink.frac_of(net_id)

## Current move speed / acceleration multiplier from the on-hit bonus (1 = none).
func momentum_mult() -> float:
    return 1.0 + float(on_hit_speed.get("bonus", 0.0)) * momentum_frac()

## Host/offline: a primary attack hit >= 1 enemy hero -> full bonus again (one refresh per swing).
func refresh_momentum() -> void:
    if on_hit_speed.is_empty() or dead or not Net.is_authority():
        return
    momentum_left = float(on_hit_speed.get("decay", 1.0))
    momentum_refreshes += 1
    _sync_momentum_prop()

func _tick_momentum(dt: float) -> void:
    if momentum_left > 0.0:
        momentum_left = maxf(0.0, momentum_left - dt)
    _sync_momentum_prop()

func _sync_momentum_prop() -> void:
    if momentum_left > 0.0 and not dead and is_inside_tree() and get_parent() != null:
        if not is_instance_valid(_momentum_prop):
            _momentum_prop = MomentumLink.build_prop(MomentumLink.kind_for(self), Vector3.ONE * 0.1, Color.WHITE)
            _momentum_prop.hero_id = -1   # the host reads momentum_left directly
            _momentum_prop.add_to_group("net_props")
            _momentum_prop.set_meta("net_kind", MomentumLink.kind_for(self))
            _momentum_prop.set_meta("net_visual", MomentumLink.PATH)
            get_parent().add_child(_momentum_prop)
        _momentum_prop.global_position = global_position
        _momentum_prop.rotation.y = MomentumLink.encode(momentum_frac())
    elif is_instance_valid(_momentum_prop):
        _momentum_prop.queue_free()
        _momentum_prop = null

## Root for dur seconds (longer root wins). See root_left.
func apply_root(dur: float) -> void:
    if dead or dur <= 0.0:
        return
    root_left = maxf(root_left, dur)
    dash_time = 0.0
    if _ride and _ride.busy():
        _ride.end_ride("root")

func rooted() -> bool:
    return root_left > 0.0 and not dead

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
    if got > 0.0:   # aggregated per (source, ability): Events.healed fires about every HEAL_EVENT_INTERVAL s
        var key := "%d/%s" % [source.get_instance_id() if is_instance_valid(source) else 0, ability_id]
        var e: Dictionary = _heal_acc.get(key, {"source": source, "amount": 0.0, "ability_id": ability_id, "age": 0.0})
        e.amount += got
        _heal_acc[key] = e
    return got

const HEAL_EVENT_INTERVAL := 0.25
var _heal_acc := {}   ## "source_iid/ability_id" -> {source, amount, ability_id, age}

func _flush_heals(dt: float, force := false) -> void:
    if _heal_acc.is_empty():
        return
    for key in _heal_acc.keys():
        var e: Dictionary = _heal_acc[key]
        e.age += dt
        if force or e.age >= HEAL_EVENT_INTERVAL:
            _heal_acc.erase(key)
            Events.healed.emit({"source": e.source if is_instance_valid(e.source) else null, "target": self,
                "amount": e.amount, "ability_id": e.ability_id})

## Splash damage to breakable cover (maps §6, group "destructible"), HitMath falloff on distance to the block.
## Host/offline only (cover.take_damage no-ops on clients). Does not charge ult.
## `los_from` (optional): only blocks with a clear line from that point are hit (Hero.los_clear).
static func damage_destructibles(tree: SceneTree, center: Vector3, radius: float, dmg: float, source, kind: String, ability_id := "", exclude = null, los_from = null) -> void:
    for c in tree.get_nodes_in_group("destructible"):
        if not c.is_inside_tree() or c == exclude:
            continue
        if los_from is Vector3 and source is Node3D and not Hero.los_clear(source, los_from, c.global_position, c):
            continue
        var amt := HitMath.aoe_damage(center, radius, dmg, c.global_position)
        if amt > 0.0:
            c.take_damage(amt, source, c.global_position, kind, ability_id)

## Area damage to enemies (used by abilities: slams, novas). Returns number of heroes hit. Walls block it: a
## target needs a clear line from my chest (can_hit; the abilities using this are centred on me).
func aoe(center: Vector3, radius: float, dmg: float, kind: String, ability_id := "") -> int:
    var n := 0
    for h in get_tree().get_nodes_in_group("heroes"):
        if h == self or h.dead or h.team == team:
            continue
        var amt := HitMath.aoe_damage(center, radius, dmg, h.global_position + Vector3(0, 0.9, 0))
        if amt > 0.0 and can_hit(h):
            h.take_damage(amt * damage_mult(), self, h.global_position + Vector3(0, 1.2, 0), kind, ability_id)
            n += 1
    Hero.damage_destructibles(get_tree(), center, radius, dmg * damage_mult(), self, kind, ability_id, null, chest())
    return n

## Damage contract (INTERFACES.md section 3). Returns damage actually applied.
## ability_id: the source ability's id ("" = primary weapon). Carried in damage_dealt / killed (INTERFACES §4).
func take_damage(amount: float, source, pos: Vector3, kind: String, ability_id := "") -> float:
    if dead or not Net.is_authority():   # THE authority check: only the host/offline sim applies damage
        return 0.0
    if amount > 0.0:
        amount *= damage_taken_mult()   # pre-damage reduction: before overheal and HP
    var absorbed := 0.0
    if overheal > 0.0 and amount > 0.0:
        absorbed = minf(overheal, amount)
        overheal -= absorbed
        amount -= absorbed
    var d := health.apply(amount) + absorbed
    if d <= 0.0:
        return 0.0
    var killed := health.is_dead()
    # src_pos: host-truth attacker position at hit time (R10), so clients get hit direction without the
    # interpolation delay of the replicated source (and even when the source has no net id).
    var src_pos = source.global_position if source is Node3D and is_instance_valid(source) and source.is_inside_tree() else null
    Events.damage_dealt.emit({"source": source, "target": self, "amount": d, "pos": pos, "src_pos": src_pos, "kind": kind, "killed": killed, "ability_id": ability_id, "crit": false})
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
    _flush_heals(0.0, true)   # report healing received before the death
    dead = true
    health.hp = 0.0
    visible = keep_body_when_dead
    collision_layer = 0
    velocity = Vector3.ZERO
    respawn_left = RESPAWN_TIME
    slow_mult = 1.0
    slow_left = 0.0
    root_left = 0.0
    momentum_left = 0.0
    _sync_momentum_prop()
    if _ride:
        _ride.end_ride("death")
    clear_buffs()
    Events.killed.emit({"killer": killer, "victim": self, "kind": kind, "ability_id": ability_id})

func respawn() -> void:
    _fire_buffered = false
    dead = false
    health.reset()
    weapon.ammo = weapon.mag_size
    global_position = spawn_point
    velocity = Vector3.ZERO
    visible = true
    collision_layer = 1
    Events.respawned.emit(self)
