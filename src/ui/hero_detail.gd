class_name HeroDetail
extends BoxContainer
## Hero-select detail: 3D preview + info (name, role, HP, then every slot in order via AbilityList: slot with its
## live key, name, precise text from HeroAbilities (JSON fallback: type/cooldown/"description"), labelled stats one per line (StatLabels)).
## Horizontal when wide; on narrow screens (< NARROW px) the preview stacks above the info.
## All text comes from the hero def / HeroAbilities (no new names).
const NARROW := 900.0
const SLOT_LABELS := {"ability1": "Ability 1", "ability2": "Ability 2", "ability3": "Ability 3", "ultimate": "Ultimate"}
var preview: HeroPreview
var info: VBoxContainer
var def: Dictionary = {}
var abilities: AbilityList
var scroll: ScrollContainer

func _ready() -> void:
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", 20)
    preview = HeroPreview.new()
    preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(preview)
    scroll = ScrollContainer.new()
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

## Stacked (narrow): the ability list gets more height than the preview.
func layout_for_width(w: float) -> void:
    vertical = w < NARROW
    if scroll != null:
        scroll.size_flags_stretch_ratio = 1.6 if vertical else 1.0
    if preview != null:
        preview.custom_minimum_size = Vector2(200, 150) if vertical else Vector2(320, 320)

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
    abilities = AbilityList.new()
    abilities.name = "Abilities"
    info.add_child(abilities)
    abilities.show_hero(String(d.get("id", "")), d)
    preview.show_def(d)

func show_path(path: String) -> void:
    var j := JSON.new()
    if j.parse(FileAccess.get_file_as_string(path)) == OK and j.data is Dictionary:
        show_def(j.data)
