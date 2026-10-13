class_name MatchPage
extends VBoxContainer
## Esc overlay "Match" page: bot count per team (steppers, 0-5, live), switch hero (UiCatalog list),
## switch team. Talks only to a MatchControl adapter. Online clients: bot steppers disabled with a note;
## hero/team changes are requests the host decides. Missing hooks show "Not available yet".
## The swap countdown lives in `countdown` (a Label on its own CanvasLayer, see PauseMenu) so it stays
## visible after the overlay closes.
signal back
const NA := "Not available yet"
var ctl: MatchControl
var countdown: Label
var bot_val := {}      ## team -> Label
var bot_btn := {}      ## team -> [minus, plus]
var hero_btns: Array = []
var team_btns := {}
var bot_note: Label
var hero_note: Label
var team_note: Label
var swap_left := -1.0
var swap_hero := ""
var swap_team_only := false

func setup(c: MatchControl) -> void:
    ctl = c
    ctl.swap_started.connect(_on_swap_started)
    ctl.swap_finished.connect(func(_h): _end_swap(""))
    ctl.swap_cancelled.connect(func(r): _end_swap(r))
    ctl.state_changed.connect(refresh)
    refresh()

func _ready() -> void:
    name = "MatchPage"
    process_mode = Node.PROCESS_MODE_ALWAYS
    add_theme_constant_override("separation", 12)
    add_child(MenuStyle.title("Match"))
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(440, 420)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    add_child(scroll)
    var v := VBoxContainer.new()
    v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    v.add_theme_constant_override("separation", 10)
    scroll.add_child(v)
    v.add_child(MenuStyle.label("Bots", 24))
    for t in [0, 1]:
        var row := HBoxContainer.new()
        row.name = "BotsTeam%d" % t
        row.add_theme_constant_override("separation", 10)
        var l := MenuStyle.label("Your team" if t == 0 else "Enemy team", 20)
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(l)
        var minus := _small("-", _step.bind(t, -1))
        minus.name = "Minus"
        var val := MenuStyle.label("-", 22)
        val.name = "Value"
        val.custom_minimum_size = Vector2(48, 0)
        val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var plus := _small("+", _step.bind(t, 1))
        plus.name = "Plus"
        row.add_child(minus)
        row.add_child(val)
        row.add_child(plus)
        bot_val[t] = val
        bot_btn[t] = [minus, plus]
        v.add_child(row)
    bot_note = _note("BotNote")
    v.add_child(bot_note)
    v.add_child(MenuStyle.label("Hero", 24))
    var grid := GridContainer.new()
    grid.name = "Heroes"
    grid.columns = 2
    for h in UiCatalog.list_heroes():
        var b := MenuStyle.button(String(h.name), _pick_hero.bind(String(h.id)))
        b.name = "Hero_" + String(h.id)
        b.set_meta("hero_id", String(h.id))
        b.set_meta("hero_name", String(h.name))
        b.custom_minimum_size = Vector2(210, 64)
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        grid.add_child(b)
        hero_btns.append(b)
    v.add_child(grid)
    hero_note = _note("HeroNote")
    v.add_child(hero_note)
    v.add_child(MenuStyle.label("Team", 24))
    var trow := HBoxContainer.new()
    trow.add_theme_constant_override("separation", 10)
    for t in [0, 1]:
        var b := MenuStyle.button("Team %d" % (t + 1), _pick_team.bind(t))
        b.name = "Team%d" % t
        b.custom_minimum_size = Vector2(210, 64)
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        trow.add_child(b)
        team_btns[t] = b
    v.add_child(trow)
    team_note = _note("TeamNote")
    v.add_child(team_note)
    var bk := MenuStyle.button("Back", func(): back.emit())
    bk.name = "Back"
    bk.custom_minimum_size = Vector2(360, 72)
    add_child(bk)
    countdown = MenuStyle.label("", 30)
    countdown.name = "SwapCountdown"
    countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    countdown.set_anchors_preset(Control.PRESET_CENTER_TOP)
    countdown.offset_top = 120
    countdown.grow_horizontal = Control.GROW_DIRECTION_BOTH
    countdown.visible = false

func _small(t: String, cb: Callable) -> Button:
    var b := MenuStyle.button(t, cb)
    b.custom_minimum_size = Vector2(72, 64)
    return b

func _note(n: String) -> Label:
    var l := MenuStyle.label("", 18)
    l.name = n
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.custom_minimum_size = Vector2(400, 0)
    return l

func refresh() -> void:
    if ctl == null:
        return
    var counts := ctl.bot_counts()
    var bots_ok := ctl.bots_available()
    var host_ok := ctl.can_set_bots()
    for t in [0, 1]:
        var n := int(counts.get(t, -1))
        bot_val[t].text = str(n) if n >= 0 else "-"
        bot_btn[t][0].disabled = not (bots_ok and host_ok and n > 0)
        bot_btn[t][1].disabled = not (bots_ok and host_ok and n >= 0 and n < MatchControl.MAX_BOTS)
    bot_note.text = NA if not bots_ok else ("Only the host can change bots" if not host_ok else "")
    var swapping := swap_left >= 0.0
    var cur := ctl.local_hero_id()
    for b in hero_btns:
        var is_cur: bool = b.get_meta("hero_id") == cur
        b.disabled = not ctl.hero_available() or swapping or is_cur
        b.text = _base_name(b) + ("  (current)" if is_cur else "")
    if not ctl.hero_available():
        hero_note.text = NA
    var mine := ctl.local_team()
    for t in team_btns:
        team_btns[t].disabled = not ctl.team_available() or t == mine
        team_btns[t].text = ("Team %d" % (t + 1)) + ("  (current)" if t == mine else "")
    if not ctl.team_available():
        team_note.text = NA

func _step(team: int, d: int) -> void:
    var counts := ctl.bot_counts()
    ctl.set_bot_count(team, int(counts.get(team, 0)) + d)
    refresh()

func _pick_hero(id: String) -> void:
    if not ctl.request_hero(id):
        hero_note.text = NA if not ctl.hero_available() else "Can't switch hero right now"
        return
    hero_note.text = "Request sent to the host" if ctl.is_client() else ""

func _pick_team(t: int) -> void:
    if not ctl.request_team(t):
        team_note.text = NA if not ctl.team_available() else "Can't switch team right now"
        return
    team_note.text = "Request sent to the host" if ctl.is_client() else ""
    refresh()

func _on_swap_started(hero_id: String, delay: float) -> void:
    swap_hero = hero_id
    swap_team_only = hero_id == ctl.local_hero_id()   # team change: respawn as the same hero
    swap_left = maxf(0.0, delay)
    _update_countdown()
    refresh()

func _end_swap(reason: String) -> void:
    swap_left = -1.0
    countdown.visible = false
    hero_note.text = "" if reason == "" else "Switch cancelled: " + reason
    refresh()

func _base_name(b: Button) -> String:
    return String(b.get_meta("hero_name", b.text))

func _hero_name(id: String) -> String:
    for b in hero_btns:
        if b.get_meta("hero_id") == id:
            return _base_name(b)
    return id

func _update_countdown() -> void:
    countdown.visible = swap_left >= 0.0
    if countdown.visible:
        countdown.text = ("Switching team in %d" % maxi(1, ceili(swap_left))) if swap_team_only else "Switching to %s in %d" % [_hero_name(swap_hero), maxi(1, ceili(swap_left))]

func _process(dt: float) -> void:
    if swap_left < 0.0:
        return
    if not get_tree().paused:   # offline the swap timer (core) is paused with the tree
        swap_left = maxf(0.0, swap_left - dt)
    _update_countdown()
