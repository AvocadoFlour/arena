class_name MatchEndScreen
extends CanvasLayer
## Match-end screen: VICTORY / DEFEAT / DRAW banner, highlight cards, final scoreboard and buttons.
## Driven by show_results(result) with result = Events.match_ended {winner_team (-1 draw), reason, mode, ...}.
## Emits play_again / main_menu for the root (main.gd, INTERFACES §9).
## Buttons (RematchControl decides): offline "Play again", "Main menu", "Quit to desktop"; online host "Rematch"
## (everyone; disabled until core has the hook), "Main menu", "Quit to desktop"; online client "Leave",
## "Quit to desktop". Esc = Main menu / Leave. The first button has keyboard/gamepad focus.
## While shown: the cursor is kept free (re-freed every frame if anything captures it) and the gameplay HUD
## behind it is hidden (Hud.set_gameplay_visible(false)).
## Layout: banner, reason and buttons are always on screen; the summary (cards + table) sits in a scroll area
## between them, so nothing goes off screen at 1280x720 (the game's base size; larger windows scale it up with
## stretch canvas_items) or smaller. Cards have a real minimum width and wrap onto more rows when narrow.
signal play_again
signal main_menu
const CARD_MIN := Vector2(270, 100)
const CARD_TEXT_MIN := 180.0    ## text column of a card (a wrapping label in a non-expanding box collapses to 1 px)
const REASONS := {"score": "Target score reached", "forced": "Match over"}
var banner: Label
var reason_l: Label
var scroll: ScrollContainer
var board: VBoxContainer        ## summary: highlights + team table + totals
var highlights_row: HFlowContainer
var table: ScoreTable
var outcome := ""
var totals_l: Label
var note_l: Label
var button_row: HBoxContainer
var buttons := {}               ## kind -> Button: play_again | rematch | main_menu | leave | quit
var control: RematchControl
var quit_fn := func(): get_tree().quit()   ## tests replace it

## Highlight card: plain label ("Top damage"), hero badge, player name and value.
func _highlight_card(hl: Dictionary) -> PanelContainer:
    var pc := PanelContainer.new()
    pc.name = "Card"
    pc.custom_minimum_size = CARD_MIN
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.08, 0.11, 0.18, 0.95)
    sb.set_corner_radius_all(10)
    sb.set_content_margin_all(12)
    pc.add_theme_stylebox_override("panel", sb)
    var h := HBoxContainer.new()
    h.add_theme_constant_override("separation", 12)
    pc.add_child(h)
    var badge := HeroBadge.for_hero(hl.hero, 56)
    badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    h.add_child(badge)
    var v := VBoxContainer.new()
    v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    v.custom_minimum_size.x = CARD_TEXT_MIN
    v.add_theme_constant_override("separation", 2)
    for spec in [[hl.label, 18, false], [hl.name, 22, true], [str(hl.value), 26, false]]:
        var l := MenuStyle.label(spec[0], spec[1])
        l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if spec[2] else TextServer.AUTOWRAP_OFF
        v.add_child(l)
    h.add_child(v)
    return pc

func _ready() -> void:
    layer = 15
    process_mode = Node.PROCESS_MODE_ALWAYS
    var bg := ColorRect.new()
    bg.name = "Background"
    bg.color = Color(0.02, 0.03, 0.06, 0.9)
    bg.mouse_filter = Control.MOUSE_FILTER_STOP   # clicks never fall through to main.gd's click-to-capture
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(bg)
    var m := MarginContainer.new()
    m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right"]:
        m.add_theme_constant_override("margin_" + side, 32)
    for side in ["top", "bottom"]:
        m.add_theme_constant_override("margin_" + side, 20)
    bg.add_child(m)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 10)
    m.add_child(v)
    banner = MenuStyle.title("")
    banner.add_theme_font_size_override("font_size", 60)
    v.add_child(banner)
    reason_l = MenuStyle.label("", 22)
    reason_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(reason_l)
    scroll = ScrollContainer.new()
    scroll.name = "Summary"
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    v.add_child(scroll)
    board = VBoxContainer.new()
    board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    board.add_theme_constant_override("separation", 12)
    scroll.add_child(board)
    highlights_row = HFlowContainer.new()
    highlights_row.name = "Highlights"
    highlights_row.alignment = FlowContainer.ALIGNMENT_CENTER
    highlights_row.add_theme_constant_override("h_separation", 16)
    highlights_row.add_theme_constant_override("v_separation", 12)
    board.add_child(highlights_row)
    table = ScoreTable.new()
    board.add_child(table)
    totals_l = MenuStyle.label("", 20)
    totals_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    board.add_child(totals_l)
    note_l = MenuStyle.label("", 18)
    note_l.name = "Note"
    note_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(note_l)
    button_row = HBoxContainer.new()
    button_row.name = "Buttons"
    button_row.alignment = BoxContainer.ALIGNMENT_CENTER
    button_row.add_theme_constant_override("separation", 16)
    v.add_child(button_row)
    visible = false

static func outcome_for(winner_team: int, player_team: int) -> String:
    if winner_team < 0:
        return "DRAW"
    return "VICTORY" if winner_team == player_team else "DEFEAT"

## Plain reason line ("score" -> "Target score reached"); unknown reasons are capitalised.
static func reason_text(reason: String) -> String:
    return REASONS.get(reason, reason.replace("_", " ").capitalize())

## Swap the adapter (tests pass mocks). Default: the composition root (Hud's parent) + the Net autoload.
func set_control(c: RematchControl) -> void:
    control = c

func _default_control() -> RematchControl:
    var hud := get_parent()
    var root_node: Object = hud.get_parent() if hud != null else null
    return RematchControl.new(root_node, get_tree().root.get_node_or_null("Net"))

## Buttons for the current session kind (offline / host / client).
func build_buttons() -> void:
    if control == null:
        control = _default_control()
    for c in button_row.get_children():
        button_row.remove_child(c)
        c.free()
    buttons.clear()
    note_l.text = ""
    var specs := []
    if control.is_client():
        specs = [["leave", "Leave", func(): main_menu.emit()]]
        note_l.text = "Waiting for the host to start a rematch, or leave." if control.available() else ""
    elif control.is_host():
        specs = [["rematch", "Rematch", func(): control.start()], ["main_menu", "Main menu", func(): main_menu.emit()]]
        if not control.available():
            note_l.text = "Rematch for everyone isn't available online yet. Main menu ends the session."
    else:
        specs = [["play_again", "Play again", func(): play_again.emit()], ["main_menu", "Main menu", func(): main_menu.emit()]]
    specs.append(["quit", "Quit to desktop", func(): quit_fn.call()])
    for s in specs:
        var b := MenuStyle.button(s[1], s[2])
        b.name = s[1].replace(" ", "")
        b.custom_minimum_size = Vector2(260, 64)
        button_row.add_child(b)
        buttons[s[0]] = b
    if buttons.has("rematch"):
        buttons.rematch.disabled = not control.available()

## Esc / back: same as Main menu (or Leave online as a client).
func back() -> void:
    main_menu.emit()

func show_results(result: Dictionary, stats: MatchStats = null, player = null) -> void:
    var pt: int = player.team if player else 0
    outcome = outcome_for(int(result.get("winner_team", -1)), pt)
    banner.text = outcome
    banner.add_theme_color_override("font_color", {"VICTORY": Color(1, 0.85, 0.3), "DEFEAT": Color(1, 0.35, 0.35)}.get(outcome, Color.WHITE))
    reason_l.text = reason_text(str(result.get("reason", "")))
    for c in highlights_row.get_children():
        highlights_row.remove_child(c)
        c.queue_free()
    if stats:
        var heroes := get_tree().get_nodes_in_group("heroes")
        for hl in stats.highlights(heroes):
            highlights_row.add_child(_highlight_card(hl))
        table.build(stats, heroes, player)
        var tt := stats.team_totals(heroes)
        var parts := []
        var ts := tt.keys()
        ts.sort()
        for t in ts:
            parts.append("%s: %d kills, %d damage" % [ScoreTable.team_title(t), tt[t].kills, int(round(tt[t].damage))])
        totals_l.text = "     ".join(parts)
    build_buttons()
    scroll.scroll_vertical = 0
    visible = true
    var hud := get_parent()
    if hud != null and hud.has_method("set_gameplay_visible"):
        hud.set_gameplay_visible(false)
    free_mouse()
    var first: Button = button_row.get_child(0) if button_row.get_child_count() > 0 else null
    if first != null and first.is_inside_tree():
        first.grab_focus()

func free_mouse() -> void:
    if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(_dt: float) -> void:
    if visible:
        free_mouse()   # e.g. a click handled elsewhere re-captured it

func _input(event: InputEvent) -> void:
    if not visible:
        return
    if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE):
        get_viewport().set_input_as_handled()   # main.gd must not open the pause overlay over us
        back()
