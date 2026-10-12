extends Ability
## Channelled beam: for `duration` seconds heals the ally (or self if none) nearest the aim
## line within `range` and `cone_deg`, at `hps` health per second.
var left := 0.0
var target = null

func _do() -> bool:
    left = float(def.get("duration", 3.0))
    return true

func channeling() -> bool:
    return left > 0.0

## Ally nearest to the look ray inside range/cone; falls back to self.
func pick_target():
    var best = null
    var best_ang := deg_to_rad(float(def.get("cone_deg", 15.0)))
    var rng := float(def.get("range", 15.0))
    if hero.is_inside_tree():
        var eye: Vector3 = hero.eye_position()
        var look: Vector3 = hero.look_dir()
        for h in hero.get_tree().get_nodes_in_group("heroes"):
            if h == hero or h.dead or h.team != hero.team:
                continue
            var to: Vector3 = h.global_position + Vector3(0, 1.0, 0) - eye
            if to.length() > rng:
                continue
            var a := look.angle_to(to)
            if a <= best_ang:
                best_ang = a
                best = h
    return best if best != null else hero

func tick(dt: float) -> void:
    super.tick(dt)
    if left <= 0.0:
        return
    left -= dt
    if hero.dead:
        left = 0.0
        return
    target = pick_target()
    target.heal(float(def.get("hps", 60.0)) * dt)
    if target != hero and hero.is_inside_tree():
        Fx.tracer(hero.get_parent(), hero.eye_position(), target.global_position + Vector3(0, 1.0, 0), Color(0.3, 1.0, 0.5))
