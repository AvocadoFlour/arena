extends Ability
## Ride (Übel's Shift): leap onto an enemy's head and ride them. HOST-AUTHORITATIVE state machine:
##   idle -> leaping (short arc onto the target's head, leap_time s) -> riding (ride_time s) -> idle.
## While riding the rider is pinned on top of the victim (victim keeps full control and moves her along),
## her own movement is off, she can still aim, fire the primary and cast (melee arcs / line cuts always reach
## the victim below: MeleeMath counts a target within 0.3 m horizontal as in the arc).
## Ends on: jump or Shift again (hop off, or hop onto another head within hop_range if there is one - the
## remaining ride time carries over), knockback or root on the rider, any Hero.cancel_ride() (stuns), the
## timer, the rider's death, the victim's death. The cooldown starts at the leap.
## Params: range, cone_deg (aim cone for the target), leap_time, ride_time, hop_range, hop_off_speed, cooldown.
## Replication (no core change): while leaping/riding the host keeps a net prop (group net_props) with
## net_kind "mount:<rider net id>:<victim net id>" and net_visual MountLink, so every client builds a MountLink
## that registers rider -> victim (MountLink.victim_of); Hero.mounted_on() reads it on clients.
const MountLink := preload("res://src/abilities/mount_link.gd")
const STATE_IDLE := 0
const STATE_LEAP := 1
const STATE_RIDE := 2
var state := STATE_IDLE
var victim = null
var ride_left := 0.0
var leap_t := 0.0
var _leap_from := Vector3.ZERO
var _link = null
var last_end := ""            ## why the last ride ended (tests / debugging): jump, shift, hop, knockback, root, cancel, timer, death, victim_death, invalid

func busy() -> bool:
    return state != STATE_IDLE

func riding() -> bool:
    return state == STATE_RIDE

## Seat height on top of a victim: its collider height (hero JSON "collider").
static func seat_offset(v) -> Vector3:
    return Vector3(0, float(v.def.get("collider", {}).get("height", 1.8)), 0)

func can_activate() -> bool:
    if busy():
        return state == STATE_RIDE   # Shift while riding: hop to another head or hop off
    return super.can_activate() and find_target(hero.global_position, float(def.get("range", 10.0)), null, true) != null

func activate() -> bool:
    if state == STATE_RIDE:
        var next = find_target(hero.global_position, float(def.get("hop_range", 8.0)), victim, false)
        if next != null:
            _begin_leap(next, "hop")
        else:
            end_ride("shift")
        return true
    if busy():
        return false
    return super.activate()

func _do() -> bool:
    var t = find_target(hero.global_position, float(def.get("range", 10.0)), null, true)
    if t == null:
        return false
    ride_left = float(def.get("ride_time", 4.0))
    _begin_leap(t, "")
    return true

## Best enemy for a leap: alive, enemy, within `rng` (3D distance to its head), not `exclude`, line of sight
## from the eye to its head; `use_cone`: inside the aim cone, ranked by angle to the crosshair, else by distance.
func find_target(from: Vector3, rng: float, exclude, use_cone: bool):
    if not hero.is_inside_tree():
        return null
    var best = null
    var best_score := INF
    var eye: Vector3 = hero.eye_position()
    var half := deg_to_rad(float(def.get("cone_deg", 30.0))) * 0.5
    for h in hero.get_tree().get_nodes_in_group("heroes"):
        if h == hero or h == exclude or h.dead or h.team == hero.team or h.get_world_3d() != hero.get_world_3d():
            continue
        if _rides(h):
            continue   # no stacking on another rider
        var head: Vector3 = h.global_position + seat_offset(h)
        if head.distance_to(from + Vector3(0, 1.0, 0)) > rng:
            continue
        var to: Vector3 = (h.global_position + Vector3(0, 1.2, 0)) - eye
        var score := to.length()
        if use_cone:
            var ang: float = hero.look_dir().angle_to(to)
            if ang > half:
                continue
            score = ang
        if not _clear(eye, h.global_position + Vector3(0, 1.2, 0), h):
            continue
        if score < best_score:
            best_score = score
            best = h
    return best

static func _rides(h) -> bool:
    for ab in h.abilities.values():
        if ab.has_method("riding") and ab.busy():
            return true
    return false

func _clear(a: Vector3, b: Vector3, target) -> bool:
    var q := PhysicsRayQueryParameters3D.create(a, b)
    q.exclude = [hero.get_rid(), target.get_rid()]
    return hero.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _begin_leap(t, why: String) -> void:
    if victim != null and is_instance_valid(victim):
        _unpin(victim)
    if why == "hop":
        last_end = "hop"
    victim = t
    state = STATE_LEAP
    leap_t = 0.0
    _leap_from = hero.global_position
    hero.dash_time = 0.0
    hero.slam_pending = false
    _pin(t)
    _spawn_link()

func _pin(v) -> void:
    hero.add_collision_exception_with(v)
    v.add_collision_exception_with(hero)
    v.ridden_by = hero   # the victim re-seats us after its own move (no one-tick lag)

func _unpin(v) -> void:
    if is_instance_valid(v):
        if v.ridden_by == hero:
            v.ridden_by = null
        hero.remove_collision_exception_with(v)
        v.remove_collision_exception_with(hero)

## HOST: called by Hero._physics_process instead of normal movement while busy(). jump = this tick's jump input.
func physics(dt: float, jump: bool) -> void:
    if hero.dead:
        end_ride("death")
        return
    if victim == null or not is_instance_valid(victim) or not victim.is_inside_tree():
        end_ride("invalid")
        return
    if victim.dead:
        end_ride("victim_death")
        return
    var seat: Vector3 = victim.global_position + seat_offset(victim)
    if state == STATE_LEAP:
        var lt := maxf(float(def.get("leap_time", 0.3)), 0.01)
        leap_t = minf(leap_t + dt, lt)
        var u := leap_t / lt
        var p := _leap_from.lerp(seat, u)
        p.y += sin(u * PI) * 1.5   # arc
        hero.global_position = p
        hero.velocity = Vector3.ZERO
        if leap_t >= lt:
            state = STATE_RIDE
        return
    ride_left -= dt
    if ride_left <= 0.0:
        end_ride("timer")
        return
    if jump:
        end_ride("jump")
        return
    hero.global_position = seat
    hero.velocity = victim.velocity

## Called by the victim right after its move_and_slide: keep the rider exactly on the head.
func reseat() -> void:
    if state == STATE_RIDE and victim != null and is_instance_valid(victim):
        hero.global_position = victim.global_position + seat_offset(victim)
        hero.velocity = victim.velocity
        if _link and is_instance_valid(_link):
            _link.global_position = hero.global_position

## Ends the ride (any reason); the rider hops off upward + slightly backward. Safe to call when idle.
func end_ride(why: String) -> void:
    if state == STATE_IDLE:
        return
    var v = victim
    state = STATE_IDLE
    victim = null
    ride_left = 0.0
    last_end = why
    _free_link()
    if v != null and is_instance_valid(v):
        _unpin(v)
        if not hero.dead and why in ["jump", "shift", "timer", "victim_death", "invalid"]:
            var back: Vector3 = -hero.look_dir()
            back.y = 0.0
            hero.velocity = back.normalized() * 6.0 + Vector3(0, float(def.get("hop_off_speed", 7.0)), 0)
            hero.dash_time = 0.25   # short guaranteed push clear of the head (air control would eat it)
            hero.dash_vel = back.normalized() * 6.0 + Vector3(v.velocity.x, 0, v.velocity.z)

func tick(dt: float) -> void:
    super.tick(dt)
    if _link and is_instance_valid(_link) and is_instance_valid(hero) and hero.is_inside_tree():
        _link.global_position = hero.global_position

func _spawn_link() -> void:
    _free_link()
    if not hero.is_inside_tree():
        return
    _link = MountLink.build_prop(MountLink.kind_for(hero, victim), Vector3.ONE * 0.1, Color.WHITE)
    _link.set_meta("net_kind", MountLink.kind_for(hero, victim))
    _link.set_meta("net_size", Vector3.ONE * 0.1)
    _link.set_meta("net_color", Color.WHITE)
    _link.set_meta("net_visual", MountLink.PATH)
    _link.add_to_group("net_props")
    _link.local_rider = hero
    _link.local_victim = victim
    hero.get_parent().add_child(_link)
    _link.global_position = hero.global_position

func _free_link() -> void:
    if _link and is_instance_valid(_link):
        _link.queue_free()
        if _link.is_inside_tree():
            _link.get_parent().remove_child(_link)   # unregister now (exit_tree), not at frame end
    _link = null

func free_visuals() -> void:
    _free_link()
