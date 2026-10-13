class_name HeroBadge
extends Control
## Hero "icon" without art: the hero name's initials in a round badge filled with the hero's own
## colour (first non-team model colour in its def), ringed in the team colour.
const TEAM_COLORS := {0: Color("#3ea0ff"), 1: Color("#ff4848")}
var initials := "?"
var fill := Color(0.4, 0.4, 0.45)
var ring := Color.WHITE

static func initials_for(n: String) -> String:
    var words := n.strip_edges().split(" ", false)
    if words.is_empty():
        return "?"
    if words.size() == 1:
        return words[0].left(2).to_upper()
    return (words[0].left(1) + words[1].left(1)).to_upper()

## Hero colour from its def: first model part with a "#hex" colour, else grey.
static func color_for_def(def) -> Color:
    if def is Dictionary:
        for part in def.get("model", []):
            var c := str(part.get("color", "")) if part is Dictionary else ""
            if c.begins_with("#"):
                return Color(c)
    return Color(0.4, 0.4, 0.45)

## Hero display name from a hero node: def.name (not the "Bot 1 (...)" display name).
static func hero_name(h) -> String:
    var d = h.get("def") if h != null and is_instance_valid(h) else null
    if d is Dictionary and d.has("name"):
        return str(d.name)
    return str(h.get("display_name")) if h != null else "?"

static func for_hero(h, size := 44.0) -> HeroBadge:
    var b := HeroBadge.new()
    b.initials = initials_for(hero_name(h))
    b.fill = color_for_def(h.get("def") if h != null else null)
    b.ring = TEAM_COLORS.get(int(h.get("team")) if h != null else -1, Color.WHITE)
    b.custom_minimum_size = Vector2(size, size)
    b.mouse_filter = Control.MOUSE_FILTER_IGNORE
    b.tooltip_text = hero_name(h)
    return b

func _draw() -> void:
    var r := minf(size.x, size.y) * 0.5
    var c := size * 0.5
    draw_circle(c, r, ring)
    draw_circle(c, r - 3.0, fill)
    var f := get_theme_default_font()
    var fs := int(r * 0.85)
    var w := f.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
    # readable on any fill: dark outline + white text
    var pos := Vector2(c.x - w * 0.5, c.y + fs * 0.35)
    draw_string_outline(f, pos, initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
    draw_string(f, pos, initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
