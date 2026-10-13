class_name HeroFx
extends RefCounted
## Client-side toon effects for one hero's primary weapon and abilities. Driven ONLY by replicated state the
## hero already tracks for its animations (ammo drop = shot, cooldown jump = cast + slot, dash_time, yaw/pitch,
## position, dead) and by replicated Events (damage_dealt / healed with ability_id). Never touches gameplay.
## Effects are keyed by the ability ids in the hero JSON; unknown ids simply get no extra effect.
const ICE := Color("#9ecff5")
const ICE_DK := Color("#6ba8e6")
const WHITE := Color("#f7faff")
const SILVER := Color("#c7cfdb")
const RED := Color("#cc1a1f")
const BLACK := Color("#18181c")
const STEEL := Color("#dbe0eb")
const STONE := Color("#b8babd")
const STONE_DK := Color("#76777c")
const DUST := Color("#d9d2c3")
const AMBER := Color("#f59a33")
const AMBER_LT := Color("#ffc75c")
const MOSS := Color("#809e5c")

var hero
var _shots := -1
var _casts := -1
var _dash_prev := 0.0
var _timers: Array = []       ## [{"kind", "t", "end", ...}] running ability effects
var _heal_cd := {}            ## target -> next allowed heal pop time
var _clock := 0.0
var spawned := 0              ## total pieces spawned (tests / debug)

func _init(h) -> void:
    hero = h
    if Engine.get_main_loop() and Events:
        Events.damage_dealt.connect(_on_damage)
        Events.healed.connect(_on_healed)

func disconnect_events() -> void:
    if Events.damage_dealt.is_connected(_on_damage):
        Events.damage_dealt.disconnect(_on_damage)
    if Events.healed.is_connected(_on_healed):
        Events.healed.disconnect(_on_healed)

func world() -> Node:
    return hero.get_parent() if is_instance_valid(hero) and hero.is_inside_tree() else null

func _count(v) -> void:
    if v is Array:
        spawned += v.size()
    elif v != null:
        spawned += 1

func _fwd() -> Vector3:
    var f: Vector3 = hero.look_dir()
    var flat := Vector3(f.x, 0, f.z)
    return flat.normalized() if flat.length() > 0.01 else Vector3(0, 0, -1)

func _ability_by_id(aid: String):
    for slot in hero.abilities:
        if hero.abilities[slot].id == aid:
            return hero.abilities[slot]
    return null

## Called every rendered frame from Hero._process (after _track_attack_state).
func process(dt: float) -> void:
    _clock += dt
    var w := world()
    if _shots >= 0 and hero._anim_shots != _shots and w and not hero.dead:
        _on_shot(w)
    _shots = hero._anim_shots
    if _casts >= 0 and hero._anim_casts != _casts and w and not hero.dead:
        var ab = hero.abilities.get(hero._anim_cast_slot)
        if ab:
            _on_cast(w, ab)
    _casts = hero._anim_casts
    if w:
        _tick_timers(w, dt)
    _dash_prev = hero.dash_time

# ------------------------------------------------------------------ primary weapons
func _on_shot(w: Node) -> void:
    var f: Vector3 = hero.look_dir()
    match String(hero.def.get("id", "")):
        "twin_tails":   # sound-wave shot: rings pulse out of the wand along the aim
            var o: Vector3 = hero.beam_origin()
            for i in 3:
                var r := ToonFx.ring(w, o + f * (0.5 + i * 0.9), 0.32 + i * 0.14, ICE if i % 2 == 0 else WHITE, 0.2 + i * 0.05, 0.22, f)
                if r:
                    r.drift = f * 6.0
                _count(r)
        "the_best":     # sword arc trail; the finisher is a vertical arc + ground burst
            var y: float = hero.rotation.y
            var base := Transform3D(Basis(Vector3.UP, y), hero.global_position + Vector3(0, 1.15, 0))
            if hero._anim_finisher:
                var v := base * Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
                _count(ToonFx.arc(w, v, WHITE, 200, 340, 0.9, 2.1, 0.3))
                var hit_at: Vector3 = hero.global_position + _fwd() * 1.9 + Vector3(0, 0.1, 0)
                _timers.append({"kind": "finisher_hit", "t": 0.0, "end": 0.14, "pos": hit_at})
            else:
                var tilt := 0.35 if hero._anim_shots % 2 == 1 else -0.35
                var xf := base * Transform3D(Basis(Vector3.FORWARD, tilt), Vector3.ZERO)
                _count(ToonFx.arc(w, xf, WHITE, 200, 340, 1.0, 2.0, 0.2))
                _count(ToonFx.arc(w, xf.translated_local(Vector3(0, 0.05, 0)), RED, 215, 325, 1.75, 2.05, 0.2))
        "cob":          # amber crystal shard flies from the shooter crystal
            var o: Vector3 = hero.beam_origin()
            var c := ToonFx.crystal(w, o, AMBER_LT if hero._anim_shots % 2 == 0 else AMBER, 0.32, 0.12, 0.22)
            if c:
                c.orient = Basis(Quaternion(Vector3.UP, f))
                c.scale_from = Vector3(0.12, 0.32, 0.12)
                c.grow = 0.01
                c.shrink = 0.2
                c.drift = f * 45.0
            _count(c)

# ------------------------------------------------------------------ abilities (cast edge)
func _on_cast(w: Node, ab) -> void:
    var pos: Vector3 = hero.global_position
    var d: Dictionary = ab.def
    match String(ab.id):
        "encore_beam":
            for i in 3:
                _count(ToonFx.note(w, hero.beam_origin(), ICE if i != 1 else WHITE, 0.8, Vector3(randf_range(-1, 1), 1.6, randf_range(-1, 1)), 0.7))
        "staccato_note":
            var o: Vector3 = hero.beam_origin()
            _count(ToonFx.ring(w, o, 0.45, WHITE, 0.2, 0.15, hero.look_dir()))
            _count(ToonFx.burst(w, o, ICE, 6, 0.45, 0.2, hero.look_dir(), 0.16))
        "grand_finale":
            var r := float(d.get("radius", 12.0))
            _count(ToonFx.ring(w, pos + Vector3(0, 0.12, 0), r, ICE, 0.8, 0.12))
            _count(ToonFx.ring(w, pos + Vector3(0, 0.15, 0), r * 0.7, WHITE, 0.65, 0.1))
            _count(ToonFx.burst(w, pos + Vector3(0, 1.2, 0), WHITE, 10, 1.1, 0.35, Vector3.BACK, 0.28))
            _timers.append({"kind": "finale_notes", "t": 0.0, "end": 1.2, "next": 0.0, "i": 0})
        "fearless_leap":
            _count(ToonFx.ring(w, pos + Vector3(0, 0.08, 0), 1.4, WHITE, 0.35, 0.1))
            for i in 6:
                var a := TAU * i / 6
                _count(ToonFx.puff(w, pos + Vector3(cos(a), 0.15, sin(a)) * 0.6, DUST, 0.5, 0.45, Vector3(cos(a), 0.4, sin(a)) * 2.0))
            _timers.append({"kind": "leap", "t": 0.0, "end": float(d.get("air_time", 0.75)) + 0.6, "r": float(d.get("radius", 3.5)), "seen_dash": false})
        "swagger_step":
            _count(ToonFx.puff(w, pos + Vector3(0, 0.3, 0), DUST, 0.7, 0.35))
            _timers.append({"kind": "swagger", "t": 0.0, "end": float(d.get("duration", 0.16)) + 0.25, "next": 0.0})
        "no_limits":
            var r := float(d.get("radius", 9.0))
            _count(ToonFx.burst(w, pos + Vector3(0, 1.1, 0), RED, 12, 1.5, 0.4, Vector3.UP, 0.32))
            _count(ToonFx.burst(w, pos + Vector3(0, 1.15, 0), WHITE, 12, 0.9, 0.35, Vector3.UP, 0.22))
            _count(ToonFx.ring(w, pos + Vector3(0, 0.12, 0), r, RED, 0.6, 0.14))
            _timers.append({"kind": "no_limits", "t": 0.0, "end": float(d.get("duration", 7.0)), "next": 0.0})
        "boulder_roll":
            _count(ToonFx.chunks(w, pos + Vector3(0, 0.2, 0), STONE, 6, 0.28, 3.0, 3.0, 0.6))
            _timers.append({"kind": "roll", "t": 0.0, "end": float(d.get("duration", 0.8)), "next": 0.0})
        "geode_wall":
            var f := _fwd()
            var c: Vector3 = pos + f * float(d.get("distance", 1.8))
            # the crystals themselves are the wall's prop visual (prop_visuals.gd); here only the burst
            _count(ToonFx.chunks(w, c, STONE, 8, 0.22, 3.5, 4.0, 0.6))
        "quarry_quake":
            _timers.append({"kind": "quake", "t": 0.0, "end": 2.0, "y0": pos.y, "low": pos.y, "r": float(d.get("radius", 9.0))})

# ------------------------------------------------------------------ running effects
func _tick_timers(w: Node, dt: float) -> void:
    var keep: Array = []
    for e in _timers:
        e.t += dt
        var done: bool = e.t >= e.end or hero.dead
        var pos: Vector3 = hero.global_position
        match String(e.kind):
            "finisher_hit":
                if e.t >= e.end:
                    _count(ToonFx.burst(w, e.pos, WHITE, 8, 1.1, 0.3, Vector3.UP, 0.3))
                    _count(ToonFx.ring(w, e.pos, 1.6, RED, 0.3, 0.1))
                    _count(ToonFx.chunks(w, e.pos, DUST, 5, 0.2, 2.0, 3.5, 0.5))
            "finale_notes":
                if e.t >= e.next and not done:
                    e.next += 0.1
                    var a: float = e.i * 0.9
                    e.i += 1
                    _count(ToonFx.note(w, pos + Vector3(cos(a), 0.4, sin(a)) * 1.0, ICE if e.i % 2 else WHITE, 0.9, Vector3(cos(a) * 1.2, 3.0, sin(a) * 1.2), 0.9))
            "leap":
                if hero.dash_time > 0.0:
                    e.seen_dash = true
                    if fmod(e.t, 0.05) < dt:
                        _count(ToonFx.puff(w, pos + Vector3(0, 0.8, 0), RED, 0.35, 0.3, Vector3.ZERO))
                var landed: bool = e.seen_dash and hero.dash_time <= 0.0 and _dash_prev > 0.0
                if landed or (e.t >= e.end and not hero.dead):
                    _leap_impact(w, pos, e.r)
                    done = true
            "swagger":
                if hero.dash_time > 0.0 or e.t < 0.1:
                    var f := _fwd()
                    var side := f.cross(Vector3.UP).normalized()
                    for k in 3:
                        var o: Vector3 = pos + Vector3(0, 0.5 + k * 0.45, 0) + side * (k - 1) * 0.25
                        _count(ToonFx.streak(w, o - f * 0.2, o - f * 1.6, RED if k == 1 else WHITE, 0.1, 0.18))
            "no_limits":
                if e.t >= e.next and not done:
                    e.next += 0.12
                    var a := randf() * TAU
                    var fl := ToonFx.crystal(w, pos + Vector3(cos(a) * 0.55, 0.05, sin(a) * 0.55), RED if randf() < 0.7 else WHITE, randf_range(0.5, 0.8), 0.22, 0.45)
                    if fl:
                        fl.drift = Vector3(0, 1.2, 0)
                    _count(fl)
            "roll":
                if e.t >= e.next and not done:
                    e.next += 0.06
                    var back: Vector3 = -hero.velocity.normalized() if hero.velocity.length() > 0.5 else -_fwd()
                    _count(ToonFx.puff(w, pos + Vector3(0, 0.25, 0) + back * 0.6, DUST, 0.65, 0.45, back * 1.5 + Vector3(0, 0.8, 0)))
                    if randf() < 0.5:
                        _count(ToonFx.chunks(w, pos + Vector3(0, 0.2, 0), STONE_DK, 1, 0.16, 2.0, 3.0, 0.45))
            "quake":
                # airborne dive: wait for the replicated position to stop falling; grounded: immediate
                e.low = minf(e.low, pos.y)
                var falling: bool = pos.y < e.y0 - 0.05
                var settled: bool = (e.t > 0.12 and not falling and absf(pos.y - e.y0) < 0.05) or (falling and pos.y > e.low - 0.001 and hero.velocity.y > -1.0 and e.t > 0.1)
                if settled or e.t >= e.end:
                    _quake_impact(w, pos, e.r)
                    done = true
        if not done:
            keep.append(e)
    _timers = keep

func _leap_impact(w: Node, pos: Vector3, r: float) -> void:
    var g := pos + Vector3(0, 0.1, 0)
    _count(ToonFx.ring(w, g, r, RED, 0.45, 0.12))
    _count(ToonFx.burst(w, g, WHITE, 9, 1.4, 0.35, Vector3.UP, 0.34))
    _count(ToonFx.chunks(w, g, STONE, 7, 0.25, 4.0, 5.0, 0.7))

func _quake_impact(w: Node, pos: Vector3, r: float) -> void:
    var g := pos + Vector3(0, 0.1, 0)
    _count(ToonFx.ring(w, g, r, AMBER, 0.7, 0.16))
    _count(ToonFx.ring(w, g, r * 0.6, STONE_DK, 0.55, 0.12))
    _count(ToonFx.burst(w, g, BLACK, 10, r * 0.45, 0.6, Vector3.UP, 0.25))   # ground cracks
    _count(ToonFx.chunks(w, g, STONE, 10, 0.4, 6.0, 7.0, 0.9))
    _count(ToonFx.chunks(w, g, AMBER_LT, 5, 0.3, 5.0, 8.0, 0.9, 14.0, "crystal"))

# ------------------------------------------------------------------ replicated events
func _on_damage(ev: Dictionary) -> void:
    if ev.get("source") != hero:
        return
    var w := world()
    var tgt = ev.get("target")
    if w == null or not is_instance_valid(tgt):
        return
    var p: Vector3 = ev.get("pos", tgt.global_position + Vector3(0, 1.1, 0))
    match String(ev.get("ability_id", "")):
        "staccato_note":
            _count(ToonFx.burst(w, p, ICE, 7, 0.6, 0.25, Vector3.BACK, 0.2))
        "fearless_leap", "boulder_roll":
            _count(ToonFx.burst(w, p, WHITE, 6, 0.7, 0.25, Vector3.BACK, 0.24))
        "":
            if String(hero.def.get("primary", {}).get("type", "")) == "melee":
                _count(ToonFx.burst(w, p, WHITE, 5, 0.55, 0.18, Vector3.BACK, 0.2))

func _on_healed(ev: Dictionary) -> void:
    if ev.get("source") != hero:
        return
    var aid := String(ev.get("ability_id", ""))
    if aid != "encore_beam" and aid != "grand_finale":
        return
    var w := world()
    var tgt = ev.get("target")
    if w == null or not is_instance_valid(tgt):
        return
    var key: int = tgt.get_instance_id()
    if _clock < float(_heal_cd.get(key, -1.0)):
        return
    _heal_cd[key] = _clock + (0.35 if aid == "encore_beam" else 0.0)
    _count(ToonFx.plus(w, tgt.global_position + Vector3(randf_range(-0.3, 0.3), 1.6, randf_range(-0.3, 0.3)), ICE if aid == "encore_beam" else WHITE, 0.45, 0.6))
