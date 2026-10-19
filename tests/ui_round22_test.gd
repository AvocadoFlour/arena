extends "res://tests/test_base.gd"
## Overhead bar + name team colours (TeamPalette): self blue, allies green, enemies red; FFA = all others red;
## team change / hero swap recolour; client perspective (no MatchRules, authoritative team ids from hero_info).
var tree: SceneTree

class FakeHealth extends RefCounted:
    func fraction() -> float: return 0.5

class FakeHero extends Node3D:
    var team := 0
    var dead := false
    var health := FakeHealth.new()
    var display_name := ""
    func _init(n: String, t: int) -> void:
        display_name = n
        team = t

class FakeRules extends Node:
    var mode := "control"

class HostRoot extends Node:
    var rules: FakeRules = null

class HookRoot extends Node:
    var m := "ffa"
    func match_mode() -> String: return m

func _hero(n: String, t: int) -> FakeHero:
    var h := FakeHero.new(n, t)
    h.add_to_group("heroes")
    tree.root.add_child(h)
    return h

func _hud(root: Node, me) -> Hud:
    var hud := Hud.new()
    tree.root.add_child(hud)
    hud.mode_root = root
    hud.player = me
    return hud

func _bar(hud: Hud, h) -> Node3D:
    return hud._bars.get(h)

func _is(hud: Hud, h, rel: String, what: String) -> void:
    var b := _bar(hud, h)
    check(b != null, what + ": has a bar")
    if b == null:
        return
    var want := TeamPalette.color(rel)
    var fill: StandardMaterial3D = (b.get_child(1) as MeshInstance3D).material_override
    var name_l: Label3D = b.get_child(2)
    check(Hud.bar_relation(b) == rel and fill.albedo_color == want and name_l.modulate == want,
        "%s: %s (got %s, fill %s, name %s)" % [what, rel, Hud.bar_relation(b), fill.albedo_color, name_l.modulate])
    check(name_l.outline_size >= 8 and name_l.outline_modulate.a >= 0.8 and name_l.text == h.display_name, what + ": outlined name")

func _host(mode: String) -> HostRoot:
    var r := HostRoot.new()
    r.rules = FakeRules.new()
    r.rules.mode = mode
    r.add_child(r.rules)
    tree.root.add_child(r)
    return r

func test_palette_distinct_and_in_one_place() -> void:
    var cs := [TeamPalette.SELF, TeamPalette.ALLY, TeamPalette.ENEMY]
    for i in 3:
        for j in 3:
            if i != j:
                var d: float = absf(cs[i].r - cs[j].r) + absf(cs[i].g - cs[j].g) + absf(cs[i].b - cs[j].b)
                check(d > 0.6, "colours %d/%d clearly distinct (%s)" % [i, j, d])
    check(TeamPalette.SELF.b > TeamPalette.SELF.r and TeamPalette.ALLY.g > TeamPalette.ALLY.r and TeamPalette.ENEMY.r > TeamPalette.ENEMY.g, "blue / green / red")
    var src := FileAccess.get_file_as_string("res://src/ui/hud.gd")
    var bars := src.substr(src.find("func _update_bars"), src.find("func _on_damage") - src.find("func _update_bars"))
    check(bars.length() > 100 and not bars.contains("Color(\""), "overhead bar code uses the palette, no colour literals")

func test_control_self_ally_enemy() -> void:
    var root := _host("control")
    var me := _hero("You (Cob)", 0)
    var ally := _hero("Ally 1 (Tomo)", 0)
    var foe := _hero("Bot 1 (Nidjo)", 1)
    var hud := _hud(root, me)
    hud._update_bars()
    _is(hud, me, "self", "control me")
    _is(hud, ally, "ally", "control ally")
    _is(hud, foe, "enemy", "control enemy")
    check(_bar(hud, ally).get_child(1).scale.x == 0.5, "fill still follows health")
    for n in [hud, me, ally, foe, root]:
        n.free()

func test_ffa_everyone_else_is_enemy() -> void:
    var root := _host("ffa")
    var me := _hero("You (Cob)", 0)
    var same_team := _hero("Host (Tomo)", 0)   # online FFA: humans still get team ids
    var foe := _hero("Bot 1 (Nidjo)", 1)
    var hud := _hud(root, me)
    hud._update_bars()
    _is(hud, me, "self", "ffa me")
    _is(hud, same_team, "enemy", "ffa same team id")
    _is(hud, foe, "enemy", "ffa enemy")
    for n in [hud, me, same_team, foe, root]:
        n.free()

func test_team_change_and_local_hero_swap_recolour() -> void:
    var root := _host("control")
    var me := _hero("You (Cob)", 0)
    var a := _hero("Ally 1 (Tomo)", 0)
    var e := _hero("Bot 1 (Nidjo)", 1)
    var hud := _hud(root, me)
    hud._update_bars()
    _is(hud, a, "ally", "before")
    # request_team_change: core re-spawns my hero on team 1 (same net id, fresh node) and moves a bot over
    var me2 := _hero("You (Cob)", 1)
    me.free()
    hud.player = me2
    var moved := _hero("Ally 3 (The Best)", 0)
    hud._update_bars()
    _is(hud, me2, "self", "after team change: me")
    _is(hud, a, "enemy", "after team change: old ally")
    _is(hud, e, "ally", "after team change: old enemy")
    _is(hud, moved, "enemy", "after team change: bot moved to my old team")
    check(hud._bars.size() == 4, "stale bar of the old hero dropped (%d)" % hud._bars.size())
    e.team = 0   # an authoritative id flip without a respawn is followed too
    hud._update_bars()
    _is(hud, e, "enemy", "live team id")
    var me3 := _hero("You (Tomo)", 1)   # hero swap: new local hero node
    me2.free()
    hud.player = me3
    hud._update_bars()
    _is(hud, me3, "self", "after hero swap")
    _is(hud, a, "enemy", "after hero swap: other team stays enemy")
    for n in [hud, me3, a, e, moved, root]:
        n.free()

func test_client_perspective_authoritative_ids() -> void:
    # Online client: no MatchRules; heroes built from Net.hero_info {team} (Hero.set_team); the map's zones exist.
    var root := Node.new()
    tree.root.add_child(root)
    var z := CaptureZone.new()
    root.add_child(z)
    var info := [{"name": "You (Twin Tails)", "team": 1}, {"name": "Host (Cob)", "team": 0}, {"name": "Ally 2 (Tomo)", "team": 1}]
    var hs := []
    for hi in info:
        hs.append(_hero(hi.name, int(hi.team)))
    var hud := _hud(root, hs[0])
    check(TeamPalette.mode_of(root) == "control", "client: control from capture zones")
    hud._update_bars()
    _is(hud, hs[0], "self", "client me (team 1)")
    _is(hud, hs[1], "enemy", "client: host on team 0 is an enemy")
    _is(hud, hs[2], "ally", "client: team-1 bot is an ally")
    z.free()
    hud._mode = ""   # mode re-read (normally once a second)
    check(TeamPalette.mode_of(root) == "ffa", "client without zones: ffa")
    hud._update_bars()
    _is(hud, hs[2], "enemy", "client ffa: same team id is still an enemy")
    var hook := HookRoot.new()
    tree.root.add_child(hook)
    hook.add_child(CaptureZone.new())
    check(TeamPalette.mode_of(hook) == "ffa", "core match_mode() hook wins over the fallback")
    hook.m = "control"
    check(TeamPalette.mode_of(hook) == "control", "hook value")
    check(TeamPalette.mode_of(null) == "ffa" and TeamPalette.relation(hs[1], null, "control") == "enemy", "graceful without root / player")
    for n in hs + [hud, root, hook]:
        n.free()

func test_bars_hidden_at_match_end_keep_colour() -> void:
    var root := _host("control")
    var me := _hero("You (Cob)", 0)
    var a := _hero("Ally 1 (Tomo)", 0)
    var hud := _hud(root, me)
    hud._update_bars()
    hud.set_gameplay_visible(false)
    check(not _bar(hud, a).visible and not _bar(hud, me).visible, "hidden behind the end screen")
    hud.set_gameplay_visible(true)
    _is(hud, a, "ally", "colour kept")
    for n in [hud, me, a, root]:
        n.free()
