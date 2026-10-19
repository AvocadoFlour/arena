class_name HeroSfx
extends Node
## Hero ability sounds + team cues from LibreQuake (src/ui/audio/LICENSES.md), played on the "SFX" bus.
## EVERY hero's fire / Shift / E / Q sounds play, not only the local player's:
##   local player's own sounds + team cues: non-positional AudioStreamPlayer at full level, a reserved set of voices
##     that grows on demand and is NEVER stolen;
##   other heroes (bots, remote players): AudioStreamPlayer3D at the hero (follows it while playing), gentle
##     inverse-distance attenuation with no cutoff (max_distance 0) and the distance low-pass switched off, so
##     a fight across the map is quieter but still audible. Pool of `pool_size` voices (default 32); when full,
##     the voice that is quietest at the listener (farthest / lowest level) is stolen, never an ultimate.
##   Ultimates (local and remote) are the most prominent: +ULT_DB per-play volume_db, the widest attenuation
##     (ULT_UNIT_SIZE), top priority (steal any non-ult voice, else an extra ult-only voice), never stolen, and
##     several at once layer (each hero instance has its own rate limit).
## No bus effects or any other processing (no EQ / reverb / compressor, no extra bus): levels are per play only.
## Rate limits are per hero INSTANCE, so two bots on the same hero both play.
## Files are used exactly as shipped by LibreQuake (no pitch/volume processing of the WAVs). Playback level is
## set per hero/slot on the player only (VOLUME_GAIN, applied when the sound plays; anything not listed: 0 dB).
## Keyed by hero id, so a hero's sounds activate as soon as its JSON is on the branch (Niđo: "nidjo").
## Slot keys are the Actions action names, i.e. the real bindings: fire (Left mouse), ability1 (Shift),
## ability2 (E), ultimate (Q); plus "ult_ready" when the ultimate meter becomes full.
## Sources (UI-side only, no gameplay changes; identical on online clients):
##   ability1/2/ultimate: Events.ability_used(hero, slot, ability_id) for any hero (replicated to clients,
##              INTERFACES §10 Events)
##   fire:      any hero's weapon.ammo dropping (one shot/swing; no shot event exists; same signal hero.gd
##              animates from; ammo is in every snapshot, so clients see remote shots too).
##              Rate-limited per hero instance (Tomo: one sound per 3-round burst)
##   ult_ready: local player's ult.is_full() false -> true (the meter the HUD shows); never on the first sample
##              or while dead
##   cues:      Events.damage_dealt / Events.killed with team checks (see on_damage / on_kill)
## The procedural UiSfx "hit" (my hit marker) and "kill" (my kill) stay: they are the *I did it* perspective.
## These cues cover the other perspectives only, so nothing plays twice for one event.
const BASE := "res://src/ui/audio/lq/"
const HERO := {
    "the_best": {"fire": "knight/sword1.wav", "ability1": "demon/djump.wav", "ability2": "weapons/ax1.wav",
        "ultimate": "items/damage.wav", "ult_ready": "items/damage3.wav"},
    "tomo": {"fire": "enforcer/enfire.wav", "ability1": "misc/r_tele1.wav", "ability2": "weapons/lock4.wav",
        "ultimate": "weapons/grenade.wav", "ult_ready": "weapons/guncock.wav"},
    "nidjo": {"fire": "player/axhit1.wav", "ability1": "items/protect.wav", "ability2": "misc/talk.wav",
        "ultimate": "items/health1.wav", "ult_ready": "misc/basekey.wav"},
    "cob": {"fire": "weapons/ric1.wav", "ability1": "weapons/bounce.wav", "ability2": "doors/basesec1.wav",
        "ultimate": "demon/dland2.wav", "ult_ready": "demon/sight2.wav"},
    "twin_tails": {"fire": "misc/menu2.wav", "ability1": "weapons/lstart.wav", "ability2": "misc/menu3.wav",
        "ultimate": "misc/secret.wav", "ult_ready": "items/inv1.wav"},
}
## Playback level per hero/slot as a linear amplitude gain, converted when the sound plays
## (AudioStreamPlayer.volume_db = linear_to_db(gain)); missing entries and cues play at 1.0 (0 dB).
## The left-click sounds below were too loud next to the rest (user request): Cob and The Best at 60% amplitude
## (about -4.44 dB), Niđo at 50% (about -6.02 dB).
const VOLUME_GAIN := {
    "cob": {"fire": 0.6},        # weapons/ric1
    "nidjo": {"fire": 0.5},      # player/axhit1
    "the_best": {"fire": 0.6},   # knight/sword1
}
const CUES := {"hit_me": "player/pain1.wav", "hit_teammate": "player/pain5.wav",
    "team_kill": "player/death3.wav", "teammate_killed": "player/death1.wav"}
const SLOTS := ["fire", "ability1", "ability2", "ultimate", "ult_ready"]
const BUS := "SFX"
const DEFAULT_POOL := 32     ## positional voices for other heroes
const LOCAL_POOL := 6        ## non-positional voices created up front (local player + team cues)
const LOCAL_MAX := 24        ## the local set grows up to this instead of stealing
const ULT_EXTRA := 16        ## extra positional voices, ultimates only, when the pool is full of ultimates
const ULT_DB := 6.0          ## ultimates: per-play volume_db boost (on top of VOLUME_GAIN), local and remote
## Positional attenuation (AudioStreamPlayer3D, inverse distance: level = unit_size / distance, no cutoff).
## Arena maps are ~35-60 m across: normal sounds -6 dB at 30 m, -12 dB at 60 m; ultimates -6 dB at 80 m.
const ATTENUATION := AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
const UNIT_SIZE := 15.0
const ULT_UNIT_SIZE := 40.0
const MAX_DISTANCE := 0.0          ## 0 = no hard cutoff
const MAX_DB := 0.0                ## closest a normal remote sound gets: never louder than the local player's own
const NO_FILTER_HZ := 20500.0      ## distance low-pass off (no processing)
## Shortest gap between two plays of the same key (seconds).
const MIN_GAP := {"fire": 0.09, "ability1": 0.1, "ability2": 0.1, "ability3": 0.1, "ultimate": 0.1, "ult_ready": 1.0,
    "hit_me": 0.35, "hit_teammate": 0.6, "team_kill": 0.25, "teammate_killed": 0.25}
const FIRE_GAP := {"tomo": 0.3}   ## per-hero override: Packet Burst = one sound per burst
var pool_size := DEFAULT_POOL      ## set before adding to the tree
var player = null                  ## local hero (HUD keeps it current across hero swaps)
var players: Array = []            ## every voice (local + positional)
var local_voices: Array = []       ## AudioStreamPlayer: local player's own sounds + team cues (never stolen)
var voices3d: Array = []           ## AudioStreamPlayer3D: other heroes
var listener_override = null       ## tests: listener position (else the active camera, else the local hero)
var streams := {}
var last_play := {}                ## rate-limit key (hero instance id / slot, or cue) -> time
var play_count := {}               ## hero id/slot or cue -> plays (tests)
var steals := 0                    ## positional voices taken over (tests / tuning)
var dropped := 0                   ## sounds not played because nothing could be stolen
var peak_voices := 0               ## most voices playing at once (tests)
var peak_ults := 0
var last_key := ""
var last_file := ""
var last_player: Node = null       ## voice used by the last play (tests)
var _state := {}                   ## hero instance id -> {ammo, ult_full}

## A voice is busy until its sound ends (start + stream length). Bookkept here rather than read from `playing`,
## which stays false under the headless Dummy audio driver; stop()/steal clears it.
func _now() -> float:
    return Time.get_ticks_msec() / 1000.0

func busy(v: Node) -> bool:
    return _now() < float(v.get_meta("until", 0.0))

static func path_for(hero_id: String, slot: String) -> String:
    var m: Dictionary = HERO.get(hero_id, {})
    return BASE + String(m[slot]) if m.has(slot) else ""

static func volume_db_for(hero_id: String, slot: String) -> float:
    var g := float(VOLUME_GAIN.get(hero_id, {}).get(slot, 1.0))
    return 0.0 if g == 1.0 else linear_to_db(g)

## Per-play level: VOLUME_GAIN table, plus ULT_DB for ultimates.
static func play_db(hero_id: String, slot: String) -> float:
    return volume_db_for(hero_id, slot) + (ULT_DB if slot == "ultimate" else 0.0)

static func cue_path(cue: String) -> String:
    return BASE + String(CUES[cue]) if CUES.has(cue) else ""

## Level of a positional sound at `dist` m before bus volume (what AudioStreamPlayer3D applies).
static func level_at(volume_db: float, dist: float, ult: bool) -> float:
    var unit := ULT_UNIT_SIZE if ult else UNIT_SIZE
    return volume_db + minf(linear_to_db(unit / maxf(dist, 0.001)), ULT_DB if ult else MAX_DB)

func _bus() -> String:
    return BUS if AudioServer.get_bus_index(BUS) >= 0 else "Master"

func _ready() -> void:
    name = "HeroSfx"
    process_mode = Node.PROCESS_MODE_PAUSABLE
    for i in LOCAL_POOL:
        _new_local()
    for i in pool_size:
        _new_3d()

func _new_local() -> AudioStreamPlayer:
    var p := AudioStreamPlayer.new()
    p.bus = _bus()
    p.set_meta("kind", "local")
    add_child(p)
    players.append(p)
    local_voices.append(p)
    return p

func _new_3d() -> AudioStreamPlayer3D:
    var p := AudioStreamPlayer3D.new()
    p.bus = _bus()
    p.attenuation_model = ATTENUATION
    p.unit_size = UNIT_SIZE
    p.max_distance = MAX_DISTANCE
    p.max_db = MAX_DB
    p.attenuation_filter_cutoff_hz = NO_FILTER_HZ
    p.attenuation_filter_db = 0.0
    p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
    p.set_meta("kind", "remote")
    add_child(p)
    players.append(p)
    voices3d.append(p)
    return p

func bind(bus: Object) -> void:
    if bus.has_signal("ability_used"):
        bus.connect("ability_used", on_ability_used)
    if bus.has_signal("damage_dealt"):
        bus.connect("damage_dealt", on_damage)
    if bus.has_signal("killed"):
        bus.connect("killed", on_kill)

func _valid(h) -> bool:
    return h != null and is_instance_valid(h)

func _team(h) -> int:
    return int(h.team) if _valid(h) and "team" in h else -999

func _hero_id(h) -> String:
    return String(h.def.get("id", "")) if _valid(h) and "def" in h and h.def is Dictionary else ""

func _stream(path: String) -> AudioStream:
    if not streams.has(path):
        streams[path] = load(path) if ResourceLoader.exists(path) else null
    return streams[path]

## Rate-limit key: per hero instance (two bots on the same hero never throttle each other).
static func rate_key(h, slot: String) -> String:
    return "%d/%s" % [h.get_instance_id(), slot]

func listener_pos() -> Vector3:
    if listener_override is Vector3:
        return listener_override
    var vp: Viewport = get_viewport() if is_inside_tree() else null
    var cam: Camera3D = vp.get_camera_3d() if vp != null else null
    if cam != null:
        return cam.global_position
    if _valid(player) and player is Node3D and player.is_inside_tree():
        return player.global_position
    return Vector3.ZERO

func _pos_of(h) -> Vector3:
    return h.global_position if _valid(h) and h is Node3D and h.is_inside_tree() else listener_pos()

## Estimated level of a playing positional voice at the listener (stealing order: lowest first).
func _voice_level(v: AudioStreamPlayer3D) -> float:
    return level_at(v.volume_db, v.global_position.distance_to(listener_pos()), bool(v.get_meta("ult", false)))

func _local_voice() -> AudioStreamPlayer:
    for v in local_voices:
        if not busy(v):
            return v
    return _new_local() if local_voices.size() < LOCAL_MAX else null

## A positional voice for a sound of level `lvl`: a free one; else steal the quietest non-ult (an ult always
## may, a normal sound only if it is at least as loud there); else (ults only) an extra ult voice.
func _remote_voice(lvl: float, ult: bool) -> AudioStreamPlayer3D:
    for v in voices3d:
        if not busy(v):
            return v
    var best: AudioStreamPlayer3D = null
    var best_lvl := INF
    for v in voices3d:
        if bool(v.get_meta("ult", false)):
            continue
        var l := _voice_level(v)
        if l < best_lvl:
            best_lvl = l
            best = v
    if best != null and (ult or lvl >= best_lvl):
        best.stop()
        best.set_meta("until", 0.0)
        steals += 1
        return best
    if ult and voices3d.size() < pool_size + ULT_EXTRA:
        return _new_3d()
    return null

## Play `path` under rate-limit key `key`; `hero` null or the local player = non-positional. True if it started.
func _play(key: String, path: String, gap: float, volume_db := 0.0, hero = null, ult := false, count_key := "") -> bool:
    if path == "":
        return false
    var s := _stream(path)
    if s == null:
        return false
    var now := Time.get_ticks_msec() / 1000.0
    if now - float(last_play.get(key, -100.0)) < gap:
        return false
    var positional: bool = _valid(hero) and hero != player
    var p: Node = null
    if positional:
        var at := _pos_of(hero)
        p = _remote_voice(level_at(volume_db, at.distance_to(listener_pos()), ult), ult)
        if p != null:
            p.unit_size = ULT_UNIT_SIZE if ult else UNIT_SIZE
            p.max_db = ULT_DB if ult else MAX_DB
            p.global_position = at
            p.set_meta("hero", weakref(hero))
    else:
        p = _local_voice()
    if p == null:
        dropped += 1
        return false
    last_play[key] = now
    var ck := count_key if count_key != "" else key
    p.set_meta("ult", ult)
    p.stream = s
    p.volume_db = volume_db   # set on every play: pooled voices are shared by all keys
    p.play()
    p.set_meta("until", now + maxf(s.get_length(), 0.05))
    p.set_meta("key", ck if count_key != "" else key)
    last_player = p
    play_count[ck] = int(play_count.get(ck, 0)) + 1
    last_key = ck
    last_file = path
    _count_peaks()
    return true

## Hero sound `slot` for `hero` (default: the local player).
func play_hero(slot: String, hero = null) -> bool:
    var h = hero if hero != null else player
    if not _valid(h):
        return false
    var id := _hero_id(h)
    var gap: float = FIRE_GAP.get(id, MIN_GAP.fire) if slot == "fire" else float(MIN_GAP.get(slot, 0.1))
    return _play(rate_key(h, slot), path_for(id, slot), gap, play_db(id, slot), h, slot == "ultimate", id + "/" + slot)

func play_cue(cue: String) -> bool:
    return _play(cue, cue_path(cue), float(MIN_GAP.get(cue, 0.3)))

func on_ability_used(hero, slot: String, _ability_id := "") -> void:
    if _valid(hero) and slot in ["ability1", "ability2", "ability3", "ultimate"]:   # ability3: silent until mapped
        play_hero(slot, hero)

## hit_me: an enemy damaged me. hit_teammate: an enemy damaged a living teammate (not me). Kills are left to on_kill.
func on_damage(ev: Dictionary) -> void:
    if not _valid(player) or float(ev.get("amount", 0.0)) <= 0.0 or bool(ev.get("killed", false)):
        return
    var src = ev.get("source")
    var tgt = ev.get("target")
    if not _valid(src) or not _valid(tgt) or _team(src) == _team(tgt):
        return   # falls / environment / self or friendly damage: no cue
    if tgt == player:
        play_cue("hit_me")
    elif _team(tgt) == _team(player):
        play_cue("hit_teammate")

## team_kill: a teammate (not me; my kills keep the UiSfx "kill") killed an enemy.
## teammate_killed: an enemy killed a teammate (not me).
func on_kill(ev: Dictionary) -> void:
    if not _valid(player):
        return
    var k = ev.get("killer")
    var v = ev.get("victim")
    if not _valid(k) or not _valid(v) or _team(k) == _team(v):
        return
    var mine := _team(player)
    if k != player and _team(k) == mine:
        play_cue("team_kill")
    elif v != player and _team(v) == mine:
        play_cue("teammate_killed")

## Voices playing now: [all, ults].
func active_counts() -> Array:
    var n := 0
    var u := 0
    for p in players:
        if busy(p):
            n += 1
            if bool(p.get_meta("ult", false)):
                u += 1
    return [n, u]

func _count_peaks() -> void:
    var c := active_counts()
    peak_voices = maxi(peak_voices, c[0])
    peak_ults = maxi(peak_ults, c[1])

func _heroes() -> Array:
    var hs: Array = get_tree().get_nodes_in_group("heroes") if is_inside_tree() else []
    if _valid(player) and not hs.has(player):
        hs.append(player)
    return hs

## Poll every hero's weapon ammo (a drop = a shot/swing) and the local player's ult meter (no events for those).
## First sample of a hero instance never plays (spawn, respawn as another hero, swap).
func poll() -> void:
    var seen := {}
    for h in _heroes():
        if not _valid(h) or _hero_id(h) == "":
            continue
        var iid: int = h.get_instance_id()
        seen[iid] = true
        var st: Dictionary = _state.get(iid, {"ammo": -1, "ult_full": null})
        _state[iid] = st
        var dead: bool = "dead" in h and h.dead
        if "weapon" in h and h.weapon != null:
            var a := int(h.weapon.ammo)
            if int(st.ammo) >= 0 and a < int(st.ammo) and not dead:
                play_hero("fire", h)
            st.ammo = a
        if h == player and "ult" in h and h.ult != null:
            var full: bool = h.ult.is_full()
            if st.ult_full == false and full and not dead:
                play_hero("ult_ready", h)
            st.ult_full = full
    for iid in _state.keys():
        if not seen.has(iid):
            _state.erase(iid)

## Positional voices follow their hero while playing (dash, leap, ride).
func _follow() -> void:
    for v in voices3d:
        if busy(v) and v.has_meta("hero"):
            var h = v.get_meta("hero").get_ref()
            if _valid(h) and h is Node3D and h.is_inside_tree():
                v.global_position = h.global_position

func _process(_dt: float) -> void:
    poll()
    _follow()
    _count_peaks()
