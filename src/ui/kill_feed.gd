class_name KillFeed
extends VBoxContainer
## Kill feed (top right). Driven by Events.killed {killer, victim, kind, ability_id}: killer name, ability
## badge (initials, HeroBadge style), victim name; names in team colours. Newest on top, at most MAX
## entries, each lasts LIFETIME s (fades over the last FADE s). Local player kills/deaths get a neutral
## panel highlight (white / grey border) so team colours stay readable.
const MAX := 5
const LIFETIME := 5.0
const FADE := 0.6
## Legacy only (events without ability_id): damage kind -> ability types that produce it (INTERFACES §2.2/§3), used to name the ability.
const KIND_TYPES := {"slam": ["ground_slam", "leap"], "charge": ["charge"], "projectile": ["projectile"], "ultimate": ["nova"]}
var player

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_theme_constant_override("separation", 4)

static func def_of(h):
    if h == null or not is_instance_valid(h):
        return null
    var d = h.get("def")
    return d if d is Dictionary else null

## Slot ("ability1"/"ability2"/"ultimate") whose ability has this id (or, per INTERFACES §3, this type).
static func slot_of(def, ability_id: String) -> String:
    if not def is Dictionary or ability_id == "":
        return ""
    var abs: Dictionary = def.get("abilities", {})
    for slot in ["ability1", "ability2", "ultimate"]:
        if abs.has(slot) and str(abs[slot].get("id", "")) == ability_id:
            return slot
    for slot in ["ability1", "ability2", "ultimate"]:
        if abs.has(slot) and str(abs[slot].get("type", "")) == ability_id:
            return slot
    return ""

## Primary weapon display name: def primary.name if present, else "Melee" / "Primary" by type.
static func primary_name(def) -> String:
    var p: Dictionary = def.get("primary", {}) if def is Dictionary else {}
    if p.has("name"):
        return str(p.name)
    return "Melee" if str(p.get("type", "")) == "melee" else "Primary"

## Weapon/ability label for a kill or hit.
##   ability_id set  -> that ability's display name from the killer's def (or the id, prettified)
##   ability_id ""   -> "Fall" for falls, "Environment" when there is no killer, else the primary weapon name
##   ability_id null -> older event without the field: legacy inference from the damage kind
static func weapon_name(killer, kind: String, ability_id = null) -> String:
    var d = def_of(killer)
    if ability_id == null:
        return _legacy_name(d, kind)
    var aid := str(ability_id)
    if aid != "":
        var slot := slot_of(d, aid)
        if slot != "":
            return str(d.abilities[slot].get("name", aid.capitalize()))
        return aid.capitalize()
    if kind == "fall":
        return "Fall"
    if d == null:
        return "Environment"
    return primary_name(d)

static func _legacy_name(d, kind: String) -> String:
    if kind == "fall":
        return "Fall"
    if d != null:
        if kind == "primary":
            return primary_name(d)
        var abs: Dictionary = d.get("abilities", {})
        if kind == "ultimate" and abs.has("ultimate"):
            return str(abs.ultimate.get("name", "Ultimate"))
        var cands: Array = []
        for slot in ["ability1", "ability2", "ultimate"]:
            if abs.has(slot) and KIND_TYPES.get(kind, []).has(str(abs[slot].get("type", ""))):
                cands.append(abs[slot])
        if cands.size() == 1:   # only name it when unambiguous
            return str(cands[0].get("name", kind.capitalize()))
    return kind.capitalize()

static func entry_text(ev: Dictionary) -> String:
    var k = ev.get("killer")
    var killer: String = k.display_name if k != null and is_instance_valid(k) else "World"
    return "%s  [%s]  %s" % [killer, weapon_name(k, str(ev.get("kind", "")), ev.get("ability_id")), ev.victim.display_name]

## Ability "icon": the weapon/ability label's initials in a HeroBadge-style circle, filled with the
## ability's def colour (if any) else the killer hero's colour, ringed in the killer's team colour.
static func ability_badge(killer, kind: String, ability_id = null, size := 34.0) -> HeroBadge:
    var label := weapon_name(killer, kind, ability_id)
    var b := HeroBadge.new()
    b.initials = HeroBadge.initials_for(label)
    var d = def_of(killer)
    var fill := HeroBadge.color_for_def(d) if d != null else Color(0.35, 0.35, 0.38)
    var aid := str(ability_id) if ability_id != null else ""
    var slot := slot_of(d, aid)
    if slot != "" and str(d.abilities[slot].get("color", "")).begins_with("#"):
        fill = Color(str(d.abilities[slot].color))
    b.fill = fill
    b.ring = team_color(killer)
    b.custom_minimum_size = Vector2(size, size)
    b.mouse_filter = Control.MOUSE_FILTER_IGNORE
    b.tooltip_text = label
    b.set_meta("label", label)
    return b

## Name colour = team colour (HeroBadge.TEAM_COLORS); no hero / unknown team = light grey.
static func team_color(h) -> Color:
    if h == null or not is_instance_valid(h):
        return Color(0.8, 0.8, 0.8)
    return HeroBadge.TEAM_COLORS.get(int(h.get("team")), Color(0.8, 0.8, 0.8))

## Player highlight that never clashes with team colours: a neutral bright panel with a white
## (kill) or dark-outlined grey (death) border plus a leading marker; names keep their team colour.
const HL_KILL_BORDER := Color(1, 1, 1, 0.95)
const HL_DEATH_BORDER := Color(0.55, 0.55, 0.6, 0.95)
const ROW_H := 40.0

func _name_label(t: String, col: Color) -> Label:
    var l := Label.new()
    l.text = t
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var ls := LabelSettings.new()
    ls.font_size = 20
    ls.font_color = col
    ls.outline_size = 6
    ls.outline_color = Color(0, 0, 0, 0.9)
    l.label_settings = ls
    return l

## One entry: [killer] (ability badge) [victim], right-aligned. Returns the row (meta "text" = plain text,
## meta "highlight" = "kill"/"death" for the local player).
func on_kill(ev: Dictionary) -> PanelContainer:
    var k = ev.get("killer")
    var victim = ev.get("victim")
    var row := PanelContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.size_flags_horizontal = Control.SIZE_SHRINK_END
    row.custom_minimum_size.y = ROW_H
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0, 0, 0, 0.45)
    sb.set_corner_radius_all(6)
    sb.content_margin_left = 10
    sb.content_margin_right = 10
    sb.content_margin_top = 3
    sb.content_margin_bottom = 3
    var hl := ""
    if player != null and k == player and victim != player:
        hl = "kill"
    elif player != null and victim == player:
        hl = "death"
    if hl != "":
        sb.bg_color = Color(1, 1, 1, 0.18) if hl == "kill" else Color(0.15, 0.15, 0.17, 0.75)
        sb.set_border_width_all(2)
        sb.border_color = HL_KILL_BORDER if hl == "kill" else HL_DEATH_BORDER
        row.set_meta("highlight", hl)
    row.add_theme_stylebox_override("panel", sb)
    var h := HBoxContainer.new()
    h.name = "Row"
    h.alignment = BoxContainer.ALIGNMENT_END
    h.add_theme_constant_override("separation", 10)
    h.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(h)
    var kname: String = k.display_name if k != null and is_instance_valid(k) else "World"
    var kl := _name_label(kname, team_color(k))
    kl.name = "Killer"
    h.add_child(kl)
    var badge := ability_badge(k, str(ev.get("kind", "")), ev.get("ability_id"))
    badge.name = "Ability"
    h.add_child(badge)
    var vl := _name_label(victim.display_name, team_color(victim))
    vl.name = "Victim"
    h.add_child(vl)
    row.set_meta("text", entry_text(ev))
    row.tooltip_text = row.get_meta("text")
    add_child(row)
    move_child(row, 0)   # newest on top
    while get_child_count() > MAX:
        var old := get_child(get_child_count() - 1)
        remove_child(old)
        old.queue_free()
    if is_inside_tree():
        var tw := row.create_tween()
        tw.tween_interval(LIFETIME - FADE)
        tw.tween_property(row, "modulate:a", 0.0, FADE)
        tw.tween_callback(func(): if is_instance_valid(row): row.queue_free())
    return row
