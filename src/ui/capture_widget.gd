class_name CaptureWidget
extends Control
## Capture-point progress HUD (top centre). Source-agnostic: bind() to any object exposing the
## proposed signals (docs/requests/ui.md):
##   capture_progress(ev: {zone_id: String, team: int (-1 neutral), progress: float 0..1, contested: bool})
##   capture_completed(ev: {zone_id: String, team: int})
## Events has neither yet, so bind(Events) is a no-op and the widget stays hidden; MockCaptureSource
## drives it in tests.
## Bar colour = owner/capturing team seen from the local player (TeamPalette): own team ally green, other
## teams enemy red, neutral grey; contested yellow. Redrawn when the local player's hero or team changes.
const NEUTRAL := Color(0.7, 0.7, 0.7)
const CONTESTED := Color(1, 0.8, 0.2)
var player    ## local hero (HUD keeps it current across hero swaps / team changes)
var mode := "control"   ## capture zones only exist in Control
var _seen := []
var zones := {}   ## zone_id -> {team, progress, contested, owner}
var row: HBoxContainer

func _ready() -> void:
    anchor_left = 0.5
    anchor_right = 0.5
    offset_left = -300
    offset_right = 300
    offset_top = 12
    offset_bottom = 72
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    row = HBoxContainer.new()
    row.set_anchors_preset(Control.PRESET_FULL_RECT)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", 16)
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(row)
    visible = false

## Returns true if the source has the capture signals.
func bind(src: Object) -> bool:
    if not (src.has_signal("capture_progress") and src.has_signal("capture_completed")):
        return false
    src.connect("capture_progress", on_progress)
    src.connect("capture_completed", on_completed)
    return true

func on_progress(ev: Dictionary) -> void:
    var z := _zone(str(ev.zone_id))
    z.team = int(ev.get("team", -1))
    z.progress = clampf(float(ev.get("progress", 0.0)), 0.0, 1.0)
    z.contested = bool(ev.get("contested", false))
    _redraw()

func on_completed(ev: Dictionary) -> void:
    var z := _zone(str(ev.zone_id))
    z.owner = int(ev.get("team", -1))
    z.team = z.owner
    z.progress = 1.0
    z.contested = false
    _redraw()

func zone_color(team: int) -> Color:
    if team < 0:
        return NEUTRAL
    return TeamPalette.color(TeamPalette.team_relation(team, player, mode))

func _process(_dt: float) -> void:
    var sig := [player.get_instance_id() if player != null and is_instance_valid(player) else 0,
        int(player.team) if player != null and is_instance_valid(player) else -999, mode]
    if sig != _seen:
        _seen = sig
        if not zones.is_empty():
            _redraw()

func _zone(id: String) -> Dictionary:
    if not zones.has(id):
        zones[id] = {"team": -1, "progress": 0.0, "contested": false, "owner": -1}
    return zones[id]

func _redraw() -> void:
    visible = not zones.is_empty()
    if row == null:
        return
    for c in row.get_children():
        row.remove_child(c)
        c.queue_free()
    var ids := zones.keys()
    ids.sort()
    for id in ids:
        var z: Dictionary = zones[id]
        var v := VBoxContainer.new()
        v.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var l := Label.new()
        l.text = "%s%s" % [id, "  CONTESTED" if z.contested else ""]
        l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        l.add_theme_font_size_override("font_size", 18)
        l.add_theme_color_override("font_outline_color", Color.BLACK)
        l.add_theme_constant_override("outline_size", 6)
        v.add_child(l)
        var bar := ProgressBar.new()
        bar.name = "bar_" + id
        bar.show_percentage = false
        bar.custom_minimum_size = Vector2(160, 16)
        bar.max_value = 1.0
        bar.value = z.progress
        var fg := StyleBoxFlat.new()
        fg.bg_color = CONTESTED if z.contested else zone_color(int(z.team))
        var bg := StyleBoxFlat.new()
        bg.bg_color = Color(0, 0, 0, 0.55)
        bar.add_theme_stylebox_override("fill", fg)
        bar.add_theme_stylebox_override("background", bg)
        v.add_child(bar)
        row.add_child(v)
