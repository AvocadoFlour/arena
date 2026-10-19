extends Node3D
## HeroSfx on the real composition root (main.tscn, offline) as Niđo: a real ability cast (Events.ability_used
## from hero.gd), a real weapon shot (ammo drop) and an enemy hit on the player play the mapped LibreQuake files
## (the bots' own sounds play alongside, positionally).
var results: Array = []
var done := false
var m
var t := 0.0
var step := 0
var orig := ""

func _rec(n: String, ok: bool, info := "") -> void:
    results.append([n, ok, info])

func _ready() -> void:
    orig = GameConfig.hero_id
    GameConfig.set_hero("nidjo")
    GameConfig.skip_menu_once = true
    m = load("res://src/main.tscn").instantiate()
    add_child(m)

func _physics_process(dt: float) -> void:
    if done:
        return
    t += dt
    var s: HeroSfx = m.hud.hero_sfx if m.hud != null else null
    match step:
        0:
            if t < 0.5:
                return
            _rec("owned_by_hud", s != null and s.player == m.player and String(m.player.def.id) == "nidjo", String(m.player.def.get("id", "")))
            _rec("sfx_bus", s.players.all(func(p): return p.bus == "SFX") and AudioServer.get_bus_index("SFX") >= 0)
            s.last_play.clear()   # a bot may already have triggered a rate-limited cue
            m.player._use("ability2")   # Stand-up Meeting through the hero's own path -> Events.ability_used
            _rec("ability_sound", s.last_file == HeroSfx.path_for("nidjo", "ability2"), s.last_file)
            m.player.weapon.try_fire()  # a swing: ammo drops; HeroSfx sees it on its next poll
            step = 1
        1:
            # bots' sounds play too now (a bot Niđo shares the per-hero count): check the local instance's own key
            _rec("fire_sound", s.last_play.has(HeroSfx.rate_key(m.player, "fire")) and s.play_count.get("nidjo/fire", 0) >= 1 and HeroSfx.path_for("nidjo", "fire").ends_with("player/axhit1.wav"), str(s.play_count.get("nidjo/fire", 0)))
            var foe = null
            for h in get_tree().get_nodes_in_group("heroes"):
                if h.team != m.player.team:
                    foe = h
                    break
            if foe != null:
                s.last_play.clear()
                Events.damage_dealt.emit({"source": foe, "target": m.player, "amount": 1.0, "pos": m.player.global_position, "src_pos": null, "kind": "primary", "killed": false, "ability_id": "", "crit": false})
                _rec("hit_me_cue", s.last_key == "hit_me", s.last_key)
            else:
                _rec("hit_me_cue", false, "no enemy")
            GameConfig.set_hero(orig)
            done = true
