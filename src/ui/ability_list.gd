class_name AbilityList
extends VBoxContainer
## Per-slot ability rows (hero select detail, Match page hero switch). One block per AbilityInfo entry:
##   header "Ability 1 [SHIFT]: <name>" (node Slot_<slot>), the precise text (Text_<slot>), the def's own
##   "description" if any, and a compact stats line (Stats_<slot>). Keys are the live bindings at show time.
## All names come from the hero def / HeroAbilities; nothing new is invented here.
var entries: Array = []
var hero_id := ""
var text_size := 17

func _ready() -> void:
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", 4)

func show_hero(id: String, def := {}) -> void:
    hero_id = id
    show_entries(AbilityInfo.describe_all(id, def))

func show_entries(list: Array) -> void:
    entries = list
    for c in get_children():
        remove_child(c)
        c.queue_free()
    for e in list:
        var slot := String(e.slot)
        var h := MenuStyle.label("%s: %s" % [AbilityInfo.slot_label(slot), e.name], text_size + 3)
        h.name = "Slot_" + slot
        add_child(h)
        if String(e.text) != "":
            add_child(_sub("Text_" + slot, String(e.text), text_size, Color(0.88, 0.9, 0.95)))
        if String(e.get("description", "")) != "" and e.description != e.text:
            add_child(_sub("Desc_" + slot, String(e.description), text_size, Color(0.75, 0.8, 0.9)))
        var st := AbilityInfo.stats_line(e.get("stats", {}))
        if st != "":
            add_child(_sub("Stats_" + slot, st, text_size - 1, Color(0.55, 0.8, 1.0)))
        var gap := Control.new()
        gap.custom_minimum_size = Vector2(0, 6)
        add_child(gap)

func _sub(n: String, t: String, sz: int, col: Color) -> Label:
    var l := MenuStyle.label(t, sz)
    l.name = n
    l.add_theme_color_override("font_color", col)
    l.custom_minimum_size = Vector2(320, 0)
    return l

func header(slot: String) -> Label:
    return get_node_or_null("Slot_" + slot) as Label
