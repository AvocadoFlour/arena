class_name BotBrain
extends RefCounted
## Bot AI as an input source: poll(hero) -> InputFrame (INTERFACES.md section 5).
## States: wander (escorts allies) -> chase (enemy visible) -> cover (low health); support (heal beam on allies). Movement follows a navmesh
## path (BotNav) with direct steering as fallback. Inaccuracy: hero.extra_spread_deg (set by the
## spawner from spread_deg) plus difficulty-dependent aim jitter and reaction delay.

const DIFFICULTY := {
    "easy":   {"spread_deg": 14.0, "turn_rate": 2.2, "fire_cone": 0.30, "reaction_time": 0.75, "aim_jitter": 0.18, "fire_duty": 0.55, "ability_delay": 2.0, "focus_slack": 0.0, "low_hp_frac": 0.20, "cover_time": 2.0, "peek_time": 1.4, "hide_min": 1.6, "hide_max": 2.4, "peek_side_mode": "same"},
    "normal": {"fire_duty": 1.0, "spread_deg": 6.0,  "turn_rate": 4.0, "fire_cone": 0.15, "reaction_time": 0.35, "aim_jitter": 0.05, "ability_delay": 0.6, "focus_slack": 8.0, "low_hp_frac": 0.35, "cover_time": 3.0, "peek_time": 1.0, "hide_min": 1.0, "hide_max": 1.8, "peek_side_mode": "random"},
    "hard":   {"fire_duty": 1.0, "spread_deg": 3.0,  "turn_rate": 7.0, "fire_cone": 0.10, "reaction_time": 0.15, "aim_jitter": 0.015, "ability_delay": 0.2, "focus_slack": 12.0, "low_hp_frac": 0.30, "cover_time": 3.5, "peek_time": 0.7, "hide_min": 0.5, "hide_max": 1.3, "peek_side_mode": "mixed"},
}
const ULT_RANGE := 8.0        ## Nova radius is 10; stay inside with margin
const SLAM_RANGE := 4.5       ## grounded slam radius is 5
const DASH_MIN_DIST := 11.0
const LOS_GRACE := 1.0        ## s a ranged bot keeps its stand-off after losing sight before pathing in
const TARGET_MEMORY := 2.0    ## s a target that went out of sight is still remembered

var difficulty := "normal"
var spread_deg := 6.0         ## applied by the spawner to hero.extra_spread_deg
var turn_rate := 4.0          ## rad/s
var sight := 40.0
var fire_cone := 0.15         ## rad: fire when aim error below this
var bounds := 17.0            ## wander area half-size
var use_abilities := true     ## dash, slam, ultimate
var use_navmesh := true
var seek_cover := true
var reaction_time := 0.35     ## s before firing at a newly acquired target
var aim_jitter := 0.05        ## rad, random aim offset refreshed twice a second
var ability_delay := 0.6      ## mean s before an ability whose conditions hold is used
var low_hp_frac := 0.35
var cover_time := 3.0         ## s of the first hide after reaching cover
var cover_session := 8.0      ## anti-stuck: leave cover after this many s without a successful peek (or 2x in total); 8 s cooldown
var peek_time := 1.0          ## s exposed per peek once the threat is in sight
var hide_min := 1.0           ## s ducked between peeks (random in [hide_min, hide_max])
var hide_max := 1.8
var peek_side_mode := "random"   ## "same" (predictable), "random", "mixed" (alternate, sometimes repeat)
var opportunistic_cover := true  ## ranged bots under 70 % HP use cover within 6 m too
var escort_allies := true
var fire_duty := 1.0         ## fraction of each 1.6 s burst cycle the trigger may be held (easy: shoots in bursts, pauses visibly)
var _burst_t := 0.0
var focus_slack := 8.0       ## m: how much farther a shared focus target may be than the nearest (easy 0 = ignores calls)
var team_play := true         ## shared focus target, grouping, tank holds the control point
var _seen_now: Array = []
var support_radius := 35.0    ## heal-beam bots look this far for hurt allies (then walk into beam range)
var heal_below := 0.8         ## ally HP fraction under which a support bot heals it    ## idle bots roam near the nearest teammate
var state := "wander"
var heal_target = null
var target = null
var nav_used := false         ## true once a navmesh path has been followed (tests/debug)

var _rng := RandomNumberGenerator.new()
var _wander := Vector3.ZERO
var _wander_left := 0.0
var _strafe := 1.0
var _strafe_left := 0.0
var _think := 0.0
var _react_left := 0.0
var _jitter := Vector2.ZERO
var _jitter_left := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _path_goal := Vector3.INF
var _repath := 0.0
var _cover = null             ## Vector3 or null
var _cover_cd := 0.0
var _cover_block = null       ## block dictionary in use
var _threat = null            ## enemy we are hiding from (kept while out of sight)
var _cphase := ""             ## travel / hide / peek
var _cphase_left := 0.0
var _session := 0.0
var _hid_once := false
var _since_peek := 0.0
var _peek_side := 1.0
var _peek_seen := 0.0         ## s the threat has been in sight during this peek
var _exposed := 0.0           ## s the threat has seen us while hiding (cover lost)
var peeks := 0                ## completed peeks (tests/debug)
var _map_root: Node3D = null
var _nav_ver := 0
var _lost := 0.0              ## s since the chase target was last in line of sight
var _repath_soon := 0.0

func _init(p: Dictionary = {}) -> void:
    _rng.randomize()
    set_difficulty(String(p.get("difficulty", "normal")))
    for k in p:
        if k != "difficulty":
            set(k, p[k])

## Preset name actually used for `d` (unknown -> "normal"); pure, no warning.
static func resolve_difficulty(d: String) -> String:
    return d if DIFFICULTY.has(d) else "normal"

func set_difficulty(d: String) -> void:
    if not DIFFICULTY.has(d):
        push_warning("BotBrain: unknown difficulty '%s', using normal" % d)
    d = resolve_difficulty(d)
    difficulty = d
    for k in DIFFICULTY[d]:
        set(k, DIFFICULTY[d][k])

func poll(h) -> InputFrame:
    var f := InputFrame.new()
    var dt := 1.0 / float(Engine.physics_ticks_per_second)
    if use_navmesh and _map_root == null:
        _map_root = BotNav.find_map_root(h)
        if _map_root:
            BotNav.ensure_region(_map_root)
    _think -= dt
    _cover_cd -= dt
    _react_left -= dt
    _jitter_left -= dt
    if _jitter_left <= 0.0:
        _jitter_left = 0.5
        _jitter = Vector2(_rng.randf_range(-aim_jitter, aim_jitter), _rng.randf_range(-aim_jitter, aim_jitter) * 0.5)
    if target and (not is_instance_valid(target) or target.dead):
        target = null
    if _think <= 0.0:
        _think = 0.2
        var t = _find_target(h)
        if t != target and t != null:
            _react_left = reaction_time
        if target != null and _lost > 0.0 and _lost < TARGET_MEMORY and \
                (t == null or h.global_position.distance_to(t.global_position) > h.global_position.distance_to(target.global_position)):
            t = target   # briefly out of sight: stick with it instead of wandering off or switching to a farther enemy
        if t != target:
            _lost = 0.0
        target = t
    var low: bool = h.health.hp < h.health.max_hp * low_hp_frac
    if target and seek_cover and _cover_cd <= 0.0 and state != "cover":
        var holding: bool = team_play and BotTeam.is_tank(h) and objective_zone(h) != null
        var hurt_ranged: bool = opportunistic_cover and not holding and melee_range(h) == 0.0 and h.health.hp < h.health.max_hp * 0.7
        if low or hurt_ranged:
            _enter_cover(h, target, 6.0 if holding or not low else INF)   # point-holding tank: only cover next to the point
    if _do_support(h, f, dt):
        pass
    elif state == "cover":
        _do_cover(h, f, dt)
    elif target:
        _do_chase(h, f, dt, low)
    else:
        _do_wander(h, f, dt)
    if h.is_on_floor() and f.move.length() > 0.1 and Vector2(h.velocity.x, h.velocity.z).length() < 1.0 and _rng.randf() < 0.1:
        f.jump = true
    if fire_duty < 1.0:
        _burst_t = fmod(_burst_t + dt, 1.6)
        if _burst_t > 1.6 * fire_duty:
            f.fire = false
    if h.weapon.ammo == 0:
        f.reload = true
    return f

func _do_chase(h, f: InputFrame, dt: float, low: bool) -> void:
    state = "chase"
    var to: Vector3 = (target.global_position + Vector3(0, 1.1, 0)) - h.eye_position()
    var err := _aim(h, f, to, dt, true)
    var dist := to.length()
    _strafe_left -= dt
    if _strafe_left <= 0.0:
        _strafe = -1.0 if _rng.randf() < 0.5 else 1.0
        _strafe_left = _rng.randf_range(0.8, 2.0)
    var t2 := slot_type(h, "ability2")
    var slam_ready: bool = use_abilities and t2 == "ground_slam" and _ab_ready(h, "ability2")
    var mrange := melee_range(h)
    var flat := Vector2(to.x, to.z).length()
    var keep := standoff(mrange, slam_ready and not low)
    var los: bool = _visible(h, target)
    if mrange > 0.0:
        # melee: drive straight in to weapon range, light strafing only once in reach
        if flat > keep + 0.5 or not los:
            f.move = _follow(h, target.global_position)
        else:
            f.move = Vector2(_strafe * 0.3, 0.6 if flat > keep else 0.0)
        f.fire = los and flat <= mrange and err < maxf(fire_cone, 0.35) and _react_left <= 0.0
    else:
        if los:
            _lost = 0.0
        else:
            if _lost == 0.0:
                _strafe = -_strafe   # LOS just broke (strafed behind cover): orbit back the way we came
                _strafe_left = 1.5
            _lost += dt
        var hold = objective_zone(h) if team_play and BotTeam.is_tank(h) else null
        if hold != null and not in_zone(hold, h.global_position, 1.5):
            f.move = _follow(h, hold.pos)   # tank: fight from the point, never chase off it
        elif hold != null:
            var dir := standoff_dir(h.global_position, target.global_position, keep, _strafe)
            if not in_zone(hold, h.global_position + dir * 1.5, 1.5):
                dir = Vector3(-dir.x, 0, -dir.z) * 0.3 if in_zone(hold, h.global_position - dir * 1.5, 1.5) else Vector3.ZERO
            f.move = world_to_move(h.global_transform.basis, dir)
        elif flat > keep + 2.0 or _lost > LOS_GRACE:
            f.move = _follow(h, target.global_position)
        else:
            var sd := standoff_dir(h.global_position, target.global_position, keep, _strafe)
            if team_play:   # cohesion: drift back toward the group while trading shots
                sd = cohesion(sd, h.global_position, rally_point(h))
            f.move = world_to_move(h.global_transform.basis, sd)
        f.fire = los and err < fire_cone and _react_left <= 0.0
    if use_abilities:
        var ctx := _ctx(h, low, false)
        ctx.merge({"dist": dist, "flat_dist": Vector2(to.x, to.z).length(),
            "height_above": h.global_position.y - target.global_position.y, "los": los,
            "aim_ok": err < 0.25, "moving": f.move.length() > 0.5}, true)
        _apply_abilities(f, decide_abilities(ctx), dt)

## Primary melee reach (0 for ranged heroes), from the hero def (INTERFACES §2.1).
static func melee_range(h) -> float:
    var p: Dictionary = h.def.get("primary", {})
    if String(p.get("type", "hitscan")) != "melee":
        return 0.0
    return float(p.get("range", 3.0))

## Distance a bot tries to hold from its target (pure; unit-tested).
static func standoff(mrange: float, slam_ready: bool) -> float:
    if mrange > 0.0:
        return mrange * 0.6
    return 3.0 if slam_ready else 10.0   # close in to use the slam

## World-space move for holding `keep` m (flat) from `target` while strafing (pure; unit-tested).
## Radial term is proportional to the range error (pushes back in when far, out when close);
## the strafe term is the true tangent around the target, computed in world space, so it does
## not depend on where the (turn-rate-limited, jittered) aim currently points.
static func standoff_dir(pos: Vector3, target_pos: Vector3, keep: float, strafe: float) -> Vector3:
    var to := Vector3(target_pos.x - pos.x, 0, target_pos.z - pos.z)
    var d := to.length()
    if d < 0.01:
        return Vector3.ZERO
    var radial := to / d
    var tangent := Vector3(-radial.z, 0, radial.x) * strafe
    var err := clampf((d - keep) / 2.0, -1.0, 1.0)   # >0: too far -> close in; <0: back off
    var tw := 0.7 * (1.0 - absf(err) * 0.6)
    # orbiting along a straight tangent drifts outward by keep*(sec-1); the err term cancels it
    return (radial * err + tangent * tw).limit_length(1.0)

## Ability context shared by chase/cover. Slot types come from the hero def (type-aware policy).
func _ctx(h, low: bool, fleeing: bool) -> Dictionary:
    var types := {}
    var ready := {}
    var ult_r := ULT_RANGE
    for slot in ["ability1", "ability2", "ultimate"]:
        types[slot] = slot_type(h, slot)
        ready[slot] = _ab_ready(h, slot)
    if h.abilities.has("ultimate"):
        ult_r = float(h.abilities["ultimate"].def.get("radius", 10.0)) * 0.8
    var leap_r := 0.0
    for slot in types:
        if types[slot] == "leap":
            var d: Dictionary = h.abilities[slot].def
            leap_r = float(d.get("forward_speed", 14.0)) * float(d.get("air_time", 0.7)) + float(d.get("radius", 3.5)) * 0.5
    return {"types": types, "ready": ready, "dist": 99.0, "flat_dist": 99.0, "on_floor": h.is_on_floor(),
        "height_above": 0.0, "los": false, "low_hp": low, "hurt": h.health.hp < h.health.max_hp * 0.7,
        "ult_range": ult_r, "ult_targets": _enemies_within(h, ult_r), "allies_hurt": _allies_hurt_within(h, ult_r),
        "aim_ok": false, "moving": false, "fleeing": fleeing, "melee": melee_range(h) > 0.0,
        "leap_range": leap_r, "engage_range": maxf(melee_range(h) * 2.0, 6.0)}

static func slot_type(h, slot: String) -> String:
    if not h.abilities.has(slot):
        return ""
    return String(h.abilities[slot].def.get("type", ""))

func _enter_cover(h, threat, max_dist: float) -> bool:
    var blk = BotNav.best_cover_block(BotNav.cover_blocks(_map_root), h.global_position, threat.global_position, 1.4, max_dist)
    if blk == null:
        return false
    if state != "cover":   # new session (re-picks inside a session keep the 8 s anti-stuck clock)
        _session = 0.0
        _since_peek = 0.0
        _hid_once = false
    _cover_block = blk
    _threat = threat
    _cover = BotNav.cover_point(blk, threat.global_position)
    state = "cover"
    _cphase = "travel"
    _cphase_left = 4.0     # travel budget
    _exposed = 0.0
    _peek_side = 1.0 if _rng.randf() < 0.5 else -1.0
    return true

func _leave_cover(cooldown: float) -> void:
    state = "chase" if target else "wander"
    _cover = null
    _cover_block = null
    _cphase = ""
    _cover_cd = cooldown

## Next peek side for the difficulty's style (pure given the random draw; unit-tested).
static func next_peek_side(mode: String, last: float, r: float) -> float:
    match mode:
        "same":
            return last
        "mixed":
            return -last if r < 0.75 else last
    return 1.0 if r < 0.5 else -1.0

## Cover cycle: travel -> hide (reload, duck) -> peek (step out past the edge, shoot) -> hide ...
## Leaves after `cover_session` s (anti-stuck, 8 s cooldown), when the threat is gone, or when the
## cover is lost (block gone, or the threat sees us while hiding -> re-pick, else fight).
func _do_cover(h, f: InputFrame, dt: float) -> void:
    if _threat == null or not is_instance_valid(_threat) or _threat.dead:
        _threat = target
        if _threat == null:
            _leave_cover(2.0)
            return
    if target != null and target != _threat and h.global_position.distance_to(target.global_position) < h.global_position.distance_to(_threat.global_position):
        _threat = target   # a closer enemy showed up
        if not _enter_cover(h, _threat, 12.0):
            _leave_cover(4.0)
            return
    var tpos: Vector3 = _threat.global_position
    var to: Vector3 = (tpos + Vector3(0, 1.1, 0)) - h.eye_position()
    var err := _aim(h, f, to, dt, true)
    var seen: bool = _visible(h, _threat)
    _cphase_left -= dt
    if _cphase != "travel":
        _session += dt
        _since_peek += dt
        # anti-stuck: leave after `cover_session` s without a successful peek, or 2x that in total
        if _since_peek >= cover_session or _session >= cover_session * 2.0:
            _leave_cover(8.0)
            return
    # cover destroyed (e.g. a removed block) -> re-pick or fight
    if _cover_block != null and _cover_block.has("node") and not is_instance_valid(_cover_block.node):
        if not _enter_cover(h, _threat, 12.0):
            _leave_cover(4.0)
        return
    var cp: Vector3 = BotNav.cover_point(_cover_block, tpos)   # follows the threat as it moves
    _cover = cp
    match _cphase:
        "travel":
            var flat := Vector2(cp.x - h.global_position.x, cp.z - h.global_position.z).length()
            f.move = _follow(h, cp)
            f.fire = seen and err < fire_cone and _react_left <= 0.0
            if use_abilities and flat > 5.0:
                var ctx := _ctx(h, true, true)
                ctx.moving = f.move.length() > 0.5
                _apply_abilities(f, decide_abilities(ctx), dt)
            if flat < 0.8:
                _cphase = "hide"
                _cphase_left = cover_time if not _hid_once else _rng.randf_range(hide_min, hide_max)
                _hid_once = true
            elif _cphase_left <= 0.0:
                _leave_cover(8.0)   # could not reach it
        "hide":
            var flat := Vector2(cp.x - h.global_position.x, cp.z - h.global_position.z).length()
            f.move = _follow(h, cp) if flat > 0.4 else Vector2.ZERO
            if h.weapon.ammo < h.weapon.mag_size:
                f.reload = true
            _exposed = _exposed + dt if seen and flat <= 0.6 else 0.0   # only counts once back at the cover point
            if _exposed > 0.4:    # flanked / cover no longer blocks: find another, else fight
                if not _enter_cover(h, _threat, 10.0):
                    _leave_cover(4.0)
                return
            if _cphase_left <= 0.0 and h.weapon.ammo > 0 and not h.weapon.reloading():
                _cphase = "peek"
                _cphase_left = 1.6   # time to get line of sight
                _peek_seen = 0.0
        "peek":
            var pp := BotNav.peek_point(_cover_block, tpos, _peek_side)
            f.move = _follow(h, pp) if not seen else Vector2.ZERO
            f.fire = seen and err < fire_cone and _react_left <= 0.0
            if seen:
                _peek_seen += dt
            if _peek_seen >= peek_time or _cphase_left <= 0.0 or h.weapon.ammo == 0:
                if _peek_seen == 0.0:
                    _peek_side = -_peek_side   # no sight from this side: try the other next time
                else:
                    peeks += 1
                    _since_peek = 0.0
                    _peek_side = next_peek_side(peek_side_mode, _peek_side, _rng.randf())
                _cphase = "hide"
                _cphase_left = _rng.randf_range(hide_min, hide_max)

## Support: a hero with a heal beam aims at the most hurt visible ally in range and channels.
## Returns true when it took over this tick (movement keeps following the ally).
func _do_support(h, f: InputFrame, dt: float) -> bool:
    var slot := ""
    for s in ["ability1", "ability2", "ultimate"]:
        if slot_type(h, s) == "heal_beam":
            slot = s
    if slot == "" or not use_abilities:
        return false
    var ab = h.abilities[slot]
    var rng := float(ab.def.get("range", 15.0))
    var chan: bool = ab.channeling()
    if not chan and not ab.can_activate():
        heal_target = null
        return false
    if not chan and target != null and h.health.hp < h.health.max_hp * low_hp_frac:
        heal_target = null   # self in danger: cover / self-heal policy first
        return false
    if heal_target == null or not is_instance_valid(heal_target) or heal_target.dead or (not chan and _think > 0.19):
        heal_target = pick_heal_target(h, maxf(rng * 2.5, support_radius))
    if heal_target == null:
        return false
    state = "support"
    var to: Vector3 = (heal_target.global_position + Vector3(0, 1.0, 0)) - h.eye_position()
    var err := _aim(h, f, to, dt, false)
    var los: bool = _visible(h, heal_target)
    var d := to.length()
    # walk (navmesh) to the ally until in beam range with line of sight, then hold
    f.move = _follow(h, heal_target.global_position) if d > rng * 0.6 or not los else Vector2.ZERO
    if not chan and los and d < rng * 0.9 and err < deg_to_rad(float(ab.def.get("cone_deg", 15.0))) * 0.7:
        f.set(slot, true)
    return true

## Most hurt living ally (not self) under `heal_below` HP, within `radius` (path-reachable; line of
## sight is not required to pick, the bot walks over). Score = HP fraction + distance / 100.
func pick_heal_target(h, radius: float):
    var best = null
    var best_s := INF
    for o in h.get_tree().get_nodes_in_group("heroes"):
        if o == h or o.dead or o.team != h.team or o.get_world_3d() != h.get_world_3d():
            continue
        var dist: float = h.global_position.distance_to(o.global_position)
        if dist > radius:
            continue
        var frac: float = o.health.hp / o.health.max_hp
        if frac >= heal_below:
            continue
        var sc := frac + dist / 100.0
        if sc < best_s:
            best_s = sc
            best = o
    return best

## Nearest living ally (not self), for escorting while idle.
func nearest_ally(h):
    var best = null
    var best_d := INF
    for o in h.get_tree().get_nodes_in_group("heroes"):
        if o.get_world_3d() != h.get_world_3d():
            continue   # other worlds (test SubViewports) share the 'heroes' group
        if o == h or o.dead or o.team != h.team:
            continue
        var d: float = h.global_position.distance_to(o.global_position)
        if d < best_d:
            best_d = d
            best = o
    return best

## Control zone the team should hold (first zone not owned by us, else the first), or null.
func objective_zone(h):
    if _map_root == null:
        _map_root = BotNav.find_map_root(h)
    if _map_root == null:
        return null
    var zones: Array = _map_root.get_meta("zones", [])
    if zones.is_empty():
        return null
    for z in zones:
        if BotTeam.zone_owner(String(z.get("id", ""))) != h.team:
            return z
    return zones[0]

## Where an idle bot regroups: tank -> zone centre; others -> the tank (or zone, or team centre).
func rally_point(h):
    var z = objective_zone(h)
    var mates := BotTeam.mates(h)
    if BotTeam.is_tank(h) and z != null:
        return z.pos
    for m in mates:
        if BotTeam.is_tank(m) and (z != null or escort_allies):
            return m.global_position
    if z != null:
        return z.pos
    if mates.is_empty() or not escort_allies:
        return null
    var c := Vector3.ZERO
    for m in mates:
        c += m.global_position
    return c / mates.size()

## Adds a pull toward `rally` when farther than COHESION_R (pure; unit-tested). Keeps |dir| <= 1.
const COHESION_R := 4.5   ## m from the rally point before the group pull starts
static func cohesion(dir: Vector3, pos: Vector3, rally) -> Vector3:
    if rally == null:
        return dir
    var to := Vector3(rally.x - pos.x, 0, rally.z - pos.z)
    var d := to.length()
    if d <= COHESION_R:
        return dir
    var w := clampf((d - COHESION_R) / 4.0, 0.0, 0.9)
    return (dir * (1.0 - w * 0.5) + to / d * w).limit_length(1.0)

## True when `p` is inside zone `z`'s footprint shrunk by `margin` (XZ only).
static func in_zone(z, p: Vector3, margin: float = 0.0) -> bool:
    var half: Vector3 = z.size * 0.5 - Vector3(margin, 0, margin)
    return absf(p.x - z.pos.x) <= half.x and absf(p.z - z.pos.z) <= half.z

func _do_wander(h, f: InputFrame, dt: float) -> void:
    if team_play and BotTeam.is_tank(h):
        var z = objective_zone(h)
        if z != null:   # tank: go to / hold the point even with no enemy around
            state = "wander"
            f.move = _follow(h, z.pos) if not in_zone(z, h.global_position, 2.0) else Vector2.ZERO
            var d := _move_world(h, f.move)
            d.y = -h.pitch * 3.0
            _aim(h, f, d, dt, false)
            return
    state = "wander"
    _wander_left -= dt
    var flat := Vector3(_wander.x - h.global_position.x, 0, _wander.z - h.global_position.z)
    if _wander_left <= 0.0 or flat.length() < 1.5:
        _wander = Vector3(_rng.randf_range(-bounds, bounds), 0, _rng.randf_range(-bounds, bounds))
        var ally = nearest_ally(h) if escort_allies else null
        var rally = rally_point(h) if team_play else null
        if rally != null:   # team play: group at the rally point (zone / tank / team centre)
            _wander = rally + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
        elif ally:   # roam near a teammate instead of alone
            var off := Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4))
            _wander = ally.global_position + off
        _wander_left = _rng.randf_range(3.0, 6.0)
    f.move = _follow(h, _wander)
    var dir := _move_world(h, f.move)
    dir.y = -h.pitch * 3.0
    _aim(h, f, dir, dt, false)

## Pure, type-aware ability policy (unit-tested). Returns {ability1, ability2, ultimate} wishes.
## ctx: types {slot: ability type}, ready {slot: bool} (legacy keys dash_ready/slam_ready/ult_ready
## are accepted for the Kestrel kit), dist, flat_dist, on_floor, height_above, los, low_hp, hurt,
## ult_range, ult_targets, allies_hurt, aim_ok, moving, fleeing.
static func decide_abilities(c: Dictionary) -> Dictionary:
    var types: Dictionary = c.get("types", {"ability1": "dash", "ability2": "ground_slam", "ultimate": "nova"})
    var ready: Dictionary = c.get("ready", {"ability1": c.get("dash_ready", false), "ability2": c.get("slam_ready", false), "ultimate": c.get("ult_ready", false)})
    var out := {}
    for slot in ["ability1", "ability2", "ultimate"]:
        out[slot] = bool(ready.get(slot, false)) and want_ability(String(types.get(slot, "")), c)
    return out

static func want_ability(t: String, c: Dictionary) -> bool:
    var dist := float(c.get("dist", 99.0))
    var los: bool = c.get("los", false)
    var fleeing: bool = c.get("fleeing", false)
    match t:
        "nova":      # only with an enemy well inside the burst radius
            return int(c.get("ult_targets", 0)) >= 1 and dist < float(c.get("ult_range", ULT_RANGE))
        "rally":     # team heal: self hurt, a hurt ally in radius, or a close-range fight starting
            return c.get("low_hp", false) or c.get("hurt", false) or int(c.get("allies_hurt", 0)) >= 1 \
                or (los and int(c.get("ult_targets", 0)) >= 1)
        "ground_slam":
            if fleeing:
                return false
            if c.get("on_floor", true):
                return dist < SLAM_RANGE
            return float(c.get("height_above", 0.0)) > 1.0 and float(c.get("flat_dist", 99.0)) < 5.0
        "dash":      # escape to cover, or close a gap on a visible enemy (never while hurt)
            if not c.get("moving", false):
                return false
            if fleeing:
                return true
            if not los or c.get("low_hp", false):
                return false
            if c.get("melee", false):   # melee: dash into reach from mid range
                return dist > 5.0 and dist < 12.0
            return dist > DASH_MIN_DIST
        "leap":      # jump onto an aimed, visible enemy beyond melee reach but inside the leap arc
            return not fleeing and los and c.get("aim_ok", false) and c.get("on_floor", true) \
                and dist > 4.5 and dist < float(c.get("leap_range", 10.0))
        "team_buff": # power up when engaged at close range (or hurt in a fight): damage + overheal
            return not fleeing and los and (dist < float(c.get("engage_range", 6.0)) \
                or (c.get("hurt", false) and dist < 15.0))
        "charge":    # rush goes along the aim: only when aimed at a visible enemy in reach
            return not fleeing and los and c.get("aim_ok", false) and dist > 2.5 and dist < 9.0
        "shield_wall":   # block incoming fire when hurt and engaged
            return not fleeing and los and dist < 25.0 and c.get("hurt", false)
        "projectile":
            return not fleeing and los and c.get("aim_ok", false) and dist < 30.0
        "heal_beam":     # ally healing is handled by the support behaviour; self-heal when hurt
            return (c.get("low_hp", false) or c.get("hurt", false)) and not fleeing
    return false

func _apply_abilities(f: InputFrame, want: Dictionary, dt: float) -> void:
    # Each wish fires with a per-tick chance -> mean delay `ability_delay` (difficulty).
    var p := 1.0 if ability_delay <= 0.0 else clampf(dt / ability_delay, 0.0, 1.0)
    for k in want:
        if want[k] and _rng.randf() < p:
            f.set(k, true)

func _ab_ready(h, slot: String) -> bool:
    return h.abilities.has(slot) and h.abilities[slot].can_activate()

func _ult_ready(h) -> bool:
    return h.abilities.has("ultimate") and h.abilities["ultimate"].can_activate()

func _allies_hurt_within(h, r: float) -> int:
    var n := 0
    for o in h.get_tree().get_nodes_in_group("heroes"):
        if o.get_world_3d() != h.get_world_3d():
            continue   # other worlds (test SubViewports) share the 'heroes' group
        if o != h and not o.dead and o.team == h.team and o.health.hp < o.health.max_hp * 0.6 and h.global_position.distance_to(o.global_position) < r:
            n += 1
    return n

func _enemies_within(h, r: float) -> int:
    var n := 0
    for o in h.get_tree().get_nodes_in_group("heroes"):
        if o.get_world_3d() != h.get_world_3d():
            continue   # other worlds (test SubViewports) share the 'heroes' group
        if o != h and not o.dead and o.team != h.team and h.global_position.distance_to(o.global_position) < r:
            n += 1
    return n

## Move input toward `goal` along the navmesh path (direct line if no path).
func _follow(h, goal: Vector3) -> Vector2:
    var pos: Vector3 = h.global_position
    _repath -= 1.0 / float(Engine.physics_ticks_per_second)
    if use_navmesh:
        if _map_root == null:
            _map_root = BotNav.find_map_root(h)
        if _map_root:
            var ver := BotNav.sync_dynamic(_map_root)   # shield walls etc. -> rebake
            if ver != _nav_ver:
                _nav_ver = ver
                _repath = 0.0
                _repath_soon = 0.1   # nav map syncs a frame or two after a rebake: query again
            if _repath_soon > 0.0:
                _repath_soon -= 1.0 / float(Engine.physics_ticks_per_second)
                if _repath_soon <= 0.0:
                    _repath = 0.0
    if use_navmesh and (_repath <= 0.0 or goal.distance_to(_path_goal) > 1.5):
        _repath = 0.4
        _path_goal = goal
        _path = BotNav.path(h, goal)
        _path_i = 0
        if _path.is_empty():
            _repath = 0.1   # nav map not synced yet / off-mesh: retry soon
    var wp := goal
    if use_navmesh and _path.size() > 0:
        while _path_i < _path.size() - 1 and Vector2(_path[_path_i].x - pos.x, _path[_path_i].z - pos.z).length() < 0.6:
            _path_i += 1
        wp = _path[_path_i]
        nav_used = true
    return world_to_move(h.global_transform.basis, Vector3(wp.x - pos.x, 0, wp.z - pos.z))

## World-space direction -> InputFrame.move for a hero with basis `b` (pure; unit-tested).
static func world_to_move(b: Basis, dir: Vector3) -> Vector2:
    dir.y = 0.0
    if dir.length() < 0.05:
        return Vector2.ZERO
    var l := b.inverse() * dir.normalized()
    return Vector2(l.x, -l.z).limit_length(1.0)

func _move_world(h, mv: Vector2) -> Vector3:
    if mv.length() < 0.01:
        return h.look_dir() * Vector3(1, 0, 1)
    return h.global_transform.basis * Vector3(mv.x, 0, -mv.y)

## Turns toward `to` (rate-limited, plus aim jitter when `jitter`). Returns remaining aim error (rad).
func _aim(h, f: InputFrame, to: Vector3, dt: float, jitter: bool) -> float:
    var want_yaw := atan2(-to.x, -to.z)
    var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
    if jitter:
        want_yaw += _jitter.x
        want_pitch += _jitter.y
    var dy := wrapf(want_yaw - h.yaw, -PI, PI)
    var dp: float = want_pitch - h.pitch
    var lim := turn_rate * dt
    f.look = Vector2(clampf(dy, -lim, lim), clampf(dp, -lim, lim))
    return Vector2(dy - f.look.x, dp - f.look.y).length()

func _visible(h, o) -> bool:
    var q := PhysicsRayQueryParameters3D.create(h.eye_position(), o.global_position + Vector3(0, 1.1, 0))
    q.exclude = [h.get_rid()]
    var hit: Dictionary = h.get_world_3d().direct_space_state.intersect_ray(q)
    return hit.is_empty() or hit.collider == o

func _find_target(h):
    var best = null
    var best_d := sight
    _seen_now = []
    for o in h.get_tree().get_nodes_in_group("heroes"):
        if o.get_world_3d() != h.get_world_3d():
            continue   # other worlds (test SubViewports) share the 'heroes' group
        if o == h or o.dead or o.team == h.team:
            continue
        var d: float = h.global_position.distance_to(o.global_position)
        if d < sight and _visible(h, o):
            _seen_now.append(o)
            if d < best_d:
                best = o
                best_d = d
    if team_play:
        BotTeam.report(h, _seen_now)
        var fo = BotTeam.focus(h)
        # focus fire: the team's lowest-HP enemy, if we see it too and it is not much farther than
        # our own nearest target (melee: must be nearly as close; never leave an enemy in reach)
        var slack := minf(3.0, focus_slack) if melee_range(h) > 0.0 else focus_slack
        if fo != null and fo in _seen_now and h.global_position.distance_to(fo.global_position) <= best_d + slack:
            best = fo
    return best
