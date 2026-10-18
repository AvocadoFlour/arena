class_name Hud
extends CanvasLayer
## HUD: crosshair + hit marker, HP, ammo, ability cooldowns, ult %, FPS, kill feed,
## floating damage numbers and enemy health bars. Reads hero state; listens to Events.
## All layout is anchor-based against the 1280x720 base (stretch canvas_items/expand).

var player
var fps_label: Label
var hp_bar: ProgressBar
var hp_label: Label
var ammo_label: Label
var ab_labels := {}
var kill_feed: KillFeed
var crosshair: Crosshair
var center_label: Label
var _bars := {}
var fps_samples: Array = []

class Crosshair extends Control:
    ## Hit-marker flash: X marks + crosshair tint; a kill is longer, bigger, thicker and red.
    const HIT := {"time": 0.15, "inner": 8.0, "outer": 16.0, "width": 3.0, "color": Color(1, 1, 1)}
    const KILL := {"time": 0.4, "inner": 9.0, "outer": 24.0, "width": 5.0, "color": Color(1, 0.2, 0.2)}
    var hit_t := 0.0
    var kill := false
    func flash(is_kill: bool) -> void:
        if kill and hit_t > 0.0 and not is_kill:
            return   # don't downgrade an active kill flash to a hit
        kill = is_kill
        hit_t = (KILL if is_kill else HIT).time
    func params() -> Dictionary:
        return KILL if kill else HIT
    func _process(dt: float) -> void:
        hit_t = maxf(0.0, hit_t - dt)
        queue_redraw()
    func _draw() -> void:
        var c := size * 0.5
        var p := params()
        var k: float = hit_t / p.time if hit_t > 0.0 else 0.0   # 1 -> 0 over the flash
        var col := Color(1, 1, 1, 0.9).lerp(p.color, k * 0.8)
        for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
            draw_line(c + d * 5, c + d * 13, col, 2.0)
        draw_circle(c, 1.5, col)
        if hit_t > 0.0:
            var hc: Color = p.color
            hc.a = clampf(k * 1.5, 0.0, 1.0)
            var grow: float = 1.0 + (1.0 - k) * (0.5 if kill else 0.2)   # marks expand while fading
            for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
                draw_line(c + d * p.inner * grow, c + d * p.outer * grow, hc, p.width)

func _label(size: int) -> Label:
    var l := Label.new()
    var ls := LabelSettings.new()
    ls.font_size = size
    ls.outline_size = 6
    ls.outline_color = Color(0, 0, 0, 0.8)
    l.label_settings = ls
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return l

func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
    c.anchor_left = al
    c.anchor_top = at
    c.anchor_right = ar
    c.anchor_bottom = ab
    c.offset_left = ol
    c.offset_top = ot
    c.offset_right = orr
    c.offset_bottom = ob
    c.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(c)

func setup(p) -> void:
    player = p
    crosshair = Crosshair.new()
    _place(crosshair, 0, 0, 1, 1, 0, 0, 0, 0)
    fps_label = _label(18)
    _place(fps_label, 0, 0, 0, 0, 16, 10, 300, 40)
    kill_feed = KillFeed.new()
    kill_feed.player = p
    _place(kill_feed, 1, 0, 1, 0, -560, 10, -16, 260)   # top-right, grows down
    kill_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
    hp_label = _label(20)
    _place(hp_label, 0, 1, 0, 1, 24, -100, 360, -72)
    hp_bar = ProgressBar.new()
    hp_bar.show_percentage = false
    var bg := StyleBoxFlat.new()
    bg.bg_color = Color(0, 0, 0, 0.5)
    var fg := StyleBoxFlat.new()
    fg.bg_color = Color("#3ee07a")
    hp_bar.add_theme_stylebox_override("background", bg)
    hp_bar.add_theme_stylebox_override("fill", fg)
    _place(hp_bar, 0, 1, 0, 1, 24, -68, 360, -40)
    ammo_label = _label(40)
    ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _place(ammo_label, 1, 1, 1, 1, -360, -96, -24, -36)
    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", 14)
    _place(row, 0.5, 1, 0.5, 1, -330, -110, 330, -30)
    for slot in ["ability1", "ability2", "ultimate"]:
        var pc := PanelContainer.new()
        pc.custom_minimum_size = Vector2(150, 70)
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.05, 0.07, 0.12, 0.7)
        sb.set_corner_radius_all(8)
        pc.add_theme_stylebox_override("panel", sb)
        var l := _label(17)
        l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        pc.add_child(l)
        row.add_child(pc)
        ab_labels[slot] = [l, sb]
    tooltip = AbilityTooltip.new()
    add_child(tooltip)
    for slot in ab_labels:
        tooltip.panels[slot] = ab_labels[slot][0].get_parent()
    tooltip.entry_for = ability_entry
    center_label = _label(34)
    center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _place(center_label, 0.5, 0.35, 0.5, 0.35, -300, -30, 300, 30)
    Events.damage_dealt.connect(_on_damage)
    Events.killed.connect(_on_kill)
    _setup_round2()
    bind_ready_event(Events)
    _setup_net_ui()
    Settings.apply_fov(get_viewport().get_camera_3d())   # player camera exists (rig set up before HUD)

var tooltip: AbilityTooltip
var _entries := {}

## AbilityInfo entry for one of the local player's slots (HeroAbilities text, JSON fallback); cached per hero.
func ability_entry(slot: String) -> Dictionary:
    if player == null or not (player.def is Dictionary):
        return {}
    var key := "%s/%s" % [player.def.get("id", ""), slot]
    if not _entries.has(key):
        _entries[key] = AbilityInfo.describe(String(player.def.get("id", "")), slot, player.def)
    return _entries[key]

## Tooltip only observes input (never set_input_as_handled), so gameplay and menus get every event.
## Hover counts only when the cursor is free and not over another UI (e.g. the pause overlay).
func _input(event: InputEvent) -> void:
    if tooltip == null:
        return
    var blocked := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
    if event is InputEventMouseMotion and not blocked:
        var hc := get_viewport().gui_get_hovered_control()
        blocked = hc != null and not is_ancestor_of(hc)
    tooltip.feed(event, blocked)

var match_stats: MatchStats
var scoreboard: Scoreboard
var match_end: MatchEndScreen
var capture_widget: CaptureWidget

## Scoreboard (hold Tab), match-end screen, capture-point widget. Capture/match-end events are
## not in INTERFACES yet: the widget binds to Events only if the signals exist (docs/requests/ui.md).
func _setup_round2() -> void:
    Keybinds.ensure_ui_actions()
    match_stats = MatchStats.new()
    add_child(match_stats)
    match_stats.bind(Events)
    scoreboard = Scoreboard.new()
    scoreboard.stats = match_stats
    scoreboard.player = player
    add_child(scoreboard)
    capture_widget = CaptureWidget.new()
    add_child(capture_widget)
    capture_widget.bind(Events)
    match_end = MatchEndScreen.new()
    add_child(match_end)
    if Events.has_signal("match_ended"):
        Events.connect("match_ended", func(result: Dictionary): match_end.show_results(result, match_stats, player))

## Ammo counter only for weapons with real ammo: hidden for primary.type "melee" (INTERFACES §2.1)
## and for the "no ammo" sentinel mag >= 999.
static func shows_ammo(def) -> bool:
    if not def is Dictionary:
        return true
    var p: Dictionary = def.get("primary", {})
    return str(p.get("type", "hitscan")) != "melee" and int(p.get("mag", 0)) < 999

## Live binding text for an action (reflects rebinds immediately; read from InputMap each frame).
static func key_label(action: String) -> String:
    return Keybinds.binding_text(action).to_upper()

func _process(dt: float) -> void:
    if not player:
        return
    var fps := Engine.get_frames_per_second()
    fps_label.text = "FPS %d" % fps
    fps_samples.append(fps)
    hp_bar.max_value = player.health.max_hp
    hp_bar.value = player.health.hp
    hp_label.text = "%s   %d / %d" % [player.display_name, ceil(player.health.hp), player.health.max_hp]
    var w = player.weapon
    ammo_label.visible = shows_ammo(player.def)
    ammo_label.text = ("RELOADING" if w.reloading() else "%d / %d" % [w.ammo, w.mag_size])
    for slot in ab_labels:
        if not player.abilities.has(slot):
            continue
        var ab = player.abilities[slot]
        var l: Label = ab_labels[slot][0]
        var sb: StyleBoxFlat = ab_labels[slot][1]
        var status := ""
        var ready := false
        if slot == "ultimate":
            ready = player.ult.is_full()
            status = "READY" if ready else "%d%%" % int(player.ult.fraction() * 100)
        else:
            ready = ab.cooldown.is_ready()
            status = "READY" if ready else "%.1fs" % ab.cooldown.remaining
        if not ready_event and ready_edge(slot, ready):
            ready_cue(slot)
        l.text = "[%s] %s\n%s" % [key_label(slot), ab.def.get("name", ab.id), status]
        sb.bg_color = Color(0.1, 0.45, 0.8, 0.8) if ready else Color(0.05, 0.07, 0.12, 0.7)
    center_label.text = ("RESPAWNING IN %.1f" % player.respawn_left) if player.dead else ""
    _update_bars()

func _update_bars() -> void:
    for h in get_tree().get_nodes_in_group("heroes"):
        if h == player:
            continue
        if not _bars.has(h):
            _bars[h] = _make_bar(h)
        var b: Node3D = _bars[h]
        b.visible = not h.dead
        b.get_child(1).scale.x = maxf(0.001, h.health.fraction())

func _make_bar(h) -> Node3D:
    var root := Node3D.new()
    root.position = Vector3(0, 2.25, 0)
    for i in 2:
        var mi := MeshInstance3D.new()
        var q := QuadMesh.new()
        q.size = Vector2(1.2, 0.14)
        mi.mesh = q
        var m := StandardMaterial3D.new()
        m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
        m.billboard_keep_scale = true
        m.no_depth_test = true
        m.render_priority = i
        m.albedo_color = Color(0, 0, 0, 0.7) if i == 0 else Color("#ff4848")
        m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mi.material_override = m
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        root.add_child(mi)
    var name_l := Label3D.new()
    name_l.text = h.display_name
    name_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    name_l.no_depth_test = true
    name_l.pixel_size = 0.006
    name_l.font_size = 40
    name_l.outline_size = 8
    name_l.position = Vector3(0, 0.22, 0)
    root.add_child(name_l)
    h.add_child(root)
    return root

func _on_damage(ev: Dictionary) -> void:
    if ev.source == player:
        crosshair.flash(bool(ev.get("killed", false)))
        if not ev.get("killed", false):
            Settings.sfx.play("hit")   # kill sound comes from Events.killed
        if not Settings.damage_numbers:
            return   # "Damage numbers" setting off: spawn none (hit marker + sound stay)
        var l := DamageNumber.from_event(ev)
        player.get_parent().add_child(l)
        l.global_position = ev.pos + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3))
        l.pop()

func _on_kill(ev: Dictionary) -> void:
    kill_feed.on_kill(ev)
    if player != null and ev.get("killer") == player and ev.get("victim") != player:
        crosshair.flash(true)
        Settings.sfx.play("kill")

var ping: PingIndicator
var conn_lost: ConnectionLostScreen

## Ping indicator (online only) + connection-lost screen, hooked to Net.disconnected(reason).
func _setup_net_ui(net: Object = null) -> void:
    ping = PingIndicator.new()
    ping.info = NetLinkInfo.new(net)
    _place(ping, 0, 0, 0, 0, 16, 42, 260, 74)
    conn_lost = ConnectionLostScreen.new()
    add_child(conn_lost)
    var src = net if net != null else get_tree().root.get_node_or_null("Net")
    if src != null and src.has_signal("disconnected"):
        src.connect("disconnected", on_net_lost)

func on_net_lost(reason: String) -> void:
    if conn_lost == null:
        return
    # Routes resolved now: main.gd creates its PauseMenu after hud.setup().
    conn_lost.routes.clear()
    var p := get_parent()
    if p != null and "menu" in p and p.menu != null and p.menu.has_signal("leave_requested"):
        conn_lost.routes.append(p.menu.leave_requested)
    if match_end:
        conn_lost.routes.append(match_end.main_menu)
    conn_lost.show_lost(reason)

## Ability-ready cue (sound + panel pulse). Source: `Events.ability_ready(hero, slot)` when core
## provides it; otherwise the polling fallback below.
var ready_event := false
func bind_ready_event(bus: Object) -> bool:
    if not bus.has_signal("ability_ready"):
        return false
    bus.connect("ability_ready", func(h, slot): if h == player: ready_cue(str(slot)))
    ready_event = true
    return true

func ready_cue(slot: String) -> void:
    Settings.sfx.play("ready")
    if not ab_labels.has(slot):
        return
    var pc: Control = ab_labels[slot][0].get_parent()
    pc.pivot_offset = pc.size * 0.5
    var tw := pc.create_tween()
    tw.tween_property(pc, "scale", Vector2.ONE * 1.12, 0.08)
    tw.tween_property(pc, "scale", Vector2.ONE, 0.15)

## Ability-ready edge detection (no ability_ready event exists; polls the cooldown/ult queries the
## HUD already reads). Returns true on a not-ready -> ready transition; the first sample never fires.
var _was_ready := {}
func ready_edge(slot: String, ready: bool) -> bool:
    var prev = _was_ready.get(slot)
    _was_ready[slot] = ready
    return prev == false and ready and not (player != null and player.dead)
