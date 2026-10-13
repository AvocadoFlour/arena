class_name HeroDetail
extends BoxContainer
## Hero-select detail: 3D preview + info (name, role, HP, primary, abilities with slot, type, cooldown and
## "description" when the def has one). Horizontal when wide; on narrow screens (< NARROW px) the preview
## stacks above the info. All text comes from the hero def (no new names).
const NARROW := 900.0
const SLOT_LABELS := {"ability1": "Ability 1", "ability2": "Ability 2", "ultimate": "Ultimate"}
var preview: HeroPreview
var info: VBoxContainer
var def: Dictionary = {}

func _ready() -> void:
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", 20)
    preview = HeroPreview.new()
    preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(preview)
    var scroll := ScrollContainer.new()
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    add_child(scroll)
    info = VBoxContainer.new()
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.add_theme_constant_override("separation", 8)
    scroll.add_child(info)
    resized.connect(_relayout)

func _relayout() -> void:
    layout_for_width(size.x)

func layout_for_width(w: float) -> void:
    vertical = w < NARROW

static func slot_line(slot: String, a: Dictionary) -> String:
    var s := "%s: %s  (%s" % [SLOT_LABELS.get(slot, slot), a.get("name", a.get("id", "?")), str(a.get("type", "")).replace("_", " ")]
    if a.has("cooldown") and not a.get("needs_ult", false):
        s += ", %ss cooldown" % str(a.cooldown)
    elif a.get("needs_ult", false) or slot == "ultimate":
        s += ", needs full ultimate"
    return s + ")"

static func primary_line(d: Dictionary) -> String:
    var p: Dictionary = d.get("primary", {})
    return "Primary: %s  (%s dmg, %s/s)" % [KillFeed.primary_name(d), str(p.get("damage", "?")), str(p.get("fire_rate", "?"))]

func show_def(d: Dictionary) -> void:
    def = d
    for c in info.get_children():
        info.remove_child(c)
        c.queue_free()
    info.add_child(MenuStyle.label(str(d.get("name", d.get("id", "?"))), 34))
    var role := MenuStyle.label("%s    %d HP" % [UiCatalog.role_label(d.get("role", "")), int(d.get("max_hp", 0))], 22)
    role.name = "Role"
    info.add_child(role)
    info.add_child(MenuStyle.label(primary_line(d), 20))
    var abs: Dictionary = d.get("abilities", {})
    for slot in ["ability1", "ability2", "ultimate"]:
        if not abs.has(slot):
            continue
        var a: Dictionary = abs[slot]
        var l := MenuStyle.label(slot_line(slot, a), 20)
        l.name = "Slot_" + slot
        info.add_child(l)
        if a.has("description"):
            var dl := MenuStyle.label(str(a.description), 17)
            dl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
            info.add_child(dl)
    preview.show_def(d)

func show_path(path: String) -> void:
    var j := JSON.new()
    if j.parse(FileAccess.get_file_as_string(path)) == OK and j.data is Dictionary:
        show_def(j.data)
