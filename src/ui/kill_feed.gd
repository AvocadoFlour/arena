class_name KillFeed
extends VBoxContainer
## Kill feed (top right). Driven by Events.killed {killer, victim, kind}: "Killer  [Weapon]  Victim",
## newest on top, at most MAX entries, each fades out after LIFETIME s. Player kills/deaths highlighted.
const MAX := 5
const LIFETIME := 5.0
const FADE := 0.6
const COL_KILL := Color(1, 0.85, 0.3)
const COL_DEATH := Color(1, 0.4, 0.4)
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

func on_kill(ev: Dictionary) -> Label:
    var l := Label.new()
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var ls := LabelSettings.new()
    ls.font_size = 20
    ls.outline_size = 6
    ls.outline_color = Color(0, 0, 0, 0.85)
    if player != null and ev.get("killer") == player:
        ls.font_color = COL_KILL
        l.set_meta("highlight", "kill")
    elif player != null and ev.get("victim") == player:
        ls.font_color = COL_DEATH
        l.set_meta("highlight", "death")
    l.label_settings = ls
    l.text = entry_text(ev)
    add_child(l)
    move_child(l, 0)   # newest on top
    while get_child_count() > MAX:
        var old := get_child(get_child_count() - 1)
        remove_child(old)
        old.queue_free()
    if is_inside_tree():
        var tw := l.create_tween()
        tw.tween_interval(LIFETIME - FADE)
        tw.tween_property(l, "modulate:a", 0.0, FADE)
        tw.tween_callback(func(): if is_instance_valid(l): l.queue_free())
    return l
