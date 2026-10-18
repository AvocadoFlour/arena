class_name BurstWeapon
extends Weapon
## Burst-fire primary (Tomo's Packet Burst). Hero JSON: "primary": {"type": "hitscan", ..., "burst": 3,
## "burst_delay": s}. `fire_rate` is the rate inside a burst; after the last round of a burst the next shot waits
## `burst_delay` s. A started burst always completes (BurstWeapon.continue_burst, called every host tick) unless the
## magazine runs dry. Optional one-shot bonus: `grant_bonus(mult, shots, window)` multiplies the damage of the next
## `shots` rounds (Hotfix). Pure logic like Weapon; hero.gd reads `damage` right after try_fire() returns true.
## Installed per hero by BurstWeapon.install(hero) (from the blink ability) until hero.gd supports primary.burst
## natively (docs/requests/tomo.md).
var burst_size := 3
var burst_delay := 0.4
var burst_left := 0          ## rounds still to fire in the current burst (0 = idle)
var base_damage := 10.0
var bonus_mult := 1.0
var bonus_shots := 0         ## rounds that still get bonus_mult
var bonus_left := 0.0        ## s until an unused bonus expires

func _init(def: Dictionary = {}) -> void:
    super(def)
    burst_size = maxi(1, int(def.get("burst", 3)))
    burst_delay = float(def.get("burst_delay", 0.4))
    base_damage = damage

## Replaces hero.weapon with a BurstWeapon when the def's primary has "burst" (keeps ammo state). Idempotent.
static func install(hero) -> BurstWeapon:
    if hero == null or hero.weapon is BurstWeapon:
        return hero.weapon if hero else null
    var p: Dictionary = hero.def.get("primary", {})
    if not p.has("burst"):
        return null
    var w := BurstWeapon.new(p)
    hero.weapon = w
    return w

## Host/offline: fires the next round of a started burst even if the trigger was released (one call per tick,
## before the hero's own fire input, which then finds the shot cooldown running).
static func continue_burst(hero) -> void:
    if hero == null or hero.dead or not (hero.weapon is BurstWeapon) or hero.net_role != "auth":
        return
    var w: BurstWeapon = hero.weapon
    if w.burst_left > 0 and w._shot_cd <= 0.0 and not w.reloading() and hero.is_inside_tree():
        hero._try_fire()

func bursting() -> bool:
    return burst_left > 0

func tick(dt: float) -> void:
    super.tick(dt)
    if bonus_left > 0.0:
        bonus_left -= dt
        if bonus_left <= 0.0:
            bonus_shots = 0
            bonus_mult = 1.0

func try_fire() -> bool:
    if not super.try_fire():
        return false
    if burst_left <= 0:
        burst_left = burst_size
    burst_left -= 1
    if burst_left == 0:
        _shot_cd = burst_delay   # pause between bursts
    if reloading():
        burst_left = 0   # magazine ran dry mid-burst
    damage = base_damage
    if bonus_shots > 0:
        damage = base_damage * bonus_mult
        bonus_shots -= 1
        if bonus_shots == 0:
            bonus_left = 0.0
    return true

func start_reload() -> bool:
    if super.start_reload():
        burst_left = 0
        return true
    return false

## The next `shots` rounds deal mult x damage; an unused bonus expires after `window` s.
func grant_bonus(mult: float, shots: int, window: float) -> void:
    bonus_mult = maxf(1.0, mult)
    bonus_shots = maxi(0, shots)
    bonus_left = window

## Peak damage per second of full bursts (no reload): burst damage / burst cycle. For tests and balance notes.
func burst_dps() -> float:
    var cycle := fire_interval * float(burst_size - 1) + burst_delay
    return base_damage * float(burst_size) / maxf(cycle, 0.001)
