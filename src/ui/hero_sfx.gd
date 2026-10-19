class_name HeroSfx
extends Node
## Hero ability sounds + team cues from LibreQuake (src/ui/audio/LICENSES.md), played on the "SFX" bus.
## Files are used exactly as shipped by LibreQuake (no pitch/volume processing of the WAVs). Playback level is
## set per hero/slot on the player only (VOLUME_GAIN, applied when the sound plays; anything not listed: 0 dB).
## Keyed by hero id, so a hero's sounds activate as soon as its JSON is on the branch (Niđo: "nidjo").
## Slot keys are the Actions action names, i.e. the real bindings: fire (Left mouse), ability1 (Shift),
## ability2 (E), ultimate (Q); plus "ult_ready" when the ultimate meter becomes full.
## Sources (UI-side only, no gameplay changes):
##   ability1/2/ultimate: Events.ability_used(hero, slot, ability_id) for the local player
##   fire:      local player's weapon.ammo dropping (one shot/swing; no shot event exists; same signal hero.gd
##              animates from). Rate-limited per hero (Tomo: one sound per 3-round burst)
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
const POOL := 8
## Shortest gap between two plays of the same key (seconds).
const MIN_GAP := {"fire": 0.09, "ability1": 0.1, "ability2": 0.1, "ultimate": 0.1, "ult_ready": 1.0,
    "hit_me": 0.35, "hit_teammate": 0.6, "team_kill": 0.25, "teammate_killed": 0.25}
const FIRE_GAP := {"tomo": 0.3}   ## per-hero override: Packet Burst = one sound per burst
var player = null                  ## local hero (HUD keeps it current across hero swaps)
var players: Array = []
var streams := {}
var last_play := {}
var play_count := {}               ## key -> plays (tests)
var last_key := ""
var last_file := ""
var last_player: AudioStreamPlayer = null   ## voice used by the last play (tests)
var _seen = null                   ## hero the polled state below belongs to
var _ammo := -1
var _ult_full = null

static func path_for(hero_id: String, slot: String) -> String:
    var m: Dictionary = HERO.get(hero_id, {})
    return BASE + String(m[slot]) if m.has(slot) else ""

static func volume_db_for(hero_id: String, slot: String) -> float:
    var g := float(VOLUME_GAIN.get(hero_id, {}).get(slot, 1.0))
    return 0.0 if g == 1.0 else linear_to_db(g)

static func cue_path(cue: String) -> String:
    return BASE + String(CUES[cue]) if CUES.has(cue) else ""

func _ready() -> void:
    name = "HeroSfx"
    process_mode = Node.PROCESS_MODE_PAUSABLE
    for i in POOL:
        var p := AudioStreamPlayer.new()
        p.bus = BUS if AudioServer.get_bus_index(BUS) >= 0 else "Master"
        add_child(p)
        players.append(p)

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

## Play `path` under rate-limit key `key`; true if it started.
func _play(key: String, path: String, gap: float, volume_db := 0.0) -> bool:
    if path == "" or players.is_empty():
        return false
    var s := _stream(path)
    if s == null:
        return false
    var now := Time.get_ticks_msec() / 1000.0
    if now - float(last_play.get(key, -100.0)) < gap:
        return false
    last_play[key] = now
    var p: AudioStreamPlayer = players[0]
    for c in players:   # a free voice first, else the one that started longest ago (round robin)
        if not c.playing:
            p = c
            break
    if p.playing:
        p = players[play_count.get("_rr", 0) % players.size()]
        play_count["_rr"] = int(play_count.get("_rr", 0)) + 1
    p.stream = s
    p.volume_db = volume_db   # set on every play: pooled voices are shared by all keys
    p.play()
    last_player = p
    play_count[key] = int(play_count.get(key, 0)) + 1
    last_key = key
    last_file = path
    return true

func play_hero(slot: String) -> bool:
    var id := _hero_id(player)
    var gap: float = FIRE_GAP.get(id, MIN_GAP.fire) if slot == "fire" else float(MIN_GAP.get(slot, 0.1))
    return _play(id + "/" + slot, path_for(id, slot), gap, volume_db_for(id, slot))

func play_cue(cue: String) -> bool:
    return _play(cue, cue_path(cue), float(MIN_GAP.get(cue, 0.3)))

func on_ability_used(hero, slot: String, _ability_id := "") -> void:
    if _valid(player) and hero == player and slot in ["ability1", "ability2", "ultimate"]:
        play_hero(slot)

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

## Poll the local player's weapon ammo and ult meter (no events for those).
func poll() -> void:
    if not _valid(player):
        _seen = null
        return
    if _seen != player:   # new hero (swap/respawn as another hero): first sample never plays
        _seen = player
        _ammo = -1
        _ult_full = null
    var dead: bool = "dead" in player and player.dead
    if "weapon" in player and player.weapon != null:
        var a := int(player.weapon.ammo)
        if _ammo >= 0 and a < _ammo and not dead:
            play_hero("fire")
        _ammo = a
    if "ult" in player and player.ult != null:
        var full: bool = player.ult.is_full()
        if _ult_full == false and full and not dead:
            play_hero("ult_ready")
        _ult_full = full

func _process(_dt: float) -> void:
    poll()
