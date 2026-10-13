class_name KillFeed
extends VBoxContainer
## Kill feed (top right). Driven by Events.killed {killer, victim, kind}: "Killer  [Weapon]  Victim",
## newest on top, at most MAX entries, each fades out after LIFETIME s. Player kills/deaths highlighted.
const MAX := 5
const LIFETIME := 5.0
const FADE := 0.6
const COL_KILL := Color(1, 0.85, 0.3)
const COL_DEATH := Color(1, 0.4, 0.4)
## Damage kind -> ability types that produce it (INTERFACES §2.2/§3), used to name the ability.
const KIND_TYPES := {"slam": ["ground_slam", "leap"], "charge": ["charge"], "projectile": ["projectile"], "ultimate": ["nova"]}
var player

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_theme_constant_override("separation", 4)

## Best-effort weapon/ability name from the killer's def; falls back to the damage kind.
static func weapon_name(killer, kind: String) -> String:
    if kind == "fall":
        return "Fall"
    var d = killer.get("def") if killer != null and is_instance_valid(killer) else null
    if d is Dictionary:
        if kind == "primary":
            return "Melee" if str(d.get("primary", {}).get("type", "")) == "melee" else "Primary"
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
    return "%s  [%s]  %s" % [killer, weapon_name(k, str(ev.get("kind", ""))), ev.victim.display_name]

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
