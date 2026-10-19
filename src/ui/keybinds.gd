class_name Keybinds
extends RefCounted
## Key rebinding on top of the Actions action map (InputMap). Persists to user://keybinds.cfg.
## Only touches the InputMap events; gameplay keeps reading InputFrame via Actions.
const PATH := "user://keybinds.cfg"

## UI-only actions (not gameplay, never in InputFrame). Registered here until core adds them to
## Actions.BINDINGS (request in docs/requests/ui.md); skipped if core already defines them.
const UI_BINDINGS := {"scoreboard": [KEY_TAB]}

static func actions() -> Array:
    var a: Array = Actions.BINDINGS.keys() + Actions.MOUSE_BINDINGS.keys()
    for u in UI_BINDINGS:
        if not a.has(u):
            a.append(u)
    return a

static func ensure_ui_actions() -> void:
    for u in UI_BINDINGS:
        if Actions.BINDINGS.has(u) or InputMap.has_action(u):
            continue
        InputMap.add_action(u)
        for k in UI_BINDINGS[u]:
            var ev := InputEventKey.new()
            ev.physical_keycode = k
            InputMap.action_add_event(u, ev)

static func pretty(action: String) -> String:
    return action.replace("_", " ").capitalize()

static func event_text(ev: InputEvent) -> String:
    if ev is InputEventKey:
        var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
        return OS.get_keycode_string(k)
    if ev is InputEventMouseButton:
        return {MOUSE_BUTTON_LEFT: "Mouse Left", MOUSE_BUTTON_RIGHT: "Mouse Right",
            MOUSE_BUTTON_MIDDLE: "Mouse Middle"}.get(ev.button_index, "Mouse %d" % ev.button_index)
    return ev.as_text()

static func binding_text(action: String) -> String:
    var evs := InputMap.action_get_events(action)
    return event_text(evs[0]) if evs.size() > 0 else "-"

## Every binding of an action, e.g. "Shift, Mouse Right" ("-" if none).
static func bindings_text(action: String) -> String:
    var evs := InputMap.action_get_events(action) if InputMap.has_action(action) else []
    return ", ".join(evs.map(func(e): return event_text(e))) if evs.size() > 0 else "-"

static func _same(a: InputEvent, b: InputEvent) -> bool:
    if a is InputEventKey and b is InputEventKey:
        return a.physical_keycode == b.physical_keycode
    if a is InputEventMouseButton and b is InputEventMouseButton:
        return a.button_index == b.button_index
    return false

## Accepts a key or mouse-button event; returns "" or the action that lost the binding (swap).
static func rebind(action: String, ev: InputEvent) -> String:
    if not (ev is InputEventKey or ev is InputEventMouseButton):
        return ""
    var clean: InputEvent
    if ev is InputEventKey:
        clean = InputEventKey.new()
        clean.physical_keycode = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
    else:
        clean = InputEventMouseButton.new()
        clean.button_index = ev.button_index
    var displaced := ""
    var old := InputMap.action_get_events(action)
    for other in actions():
        if other == action:
            continue
        for e in InputMap.action_get_events(other):
            if _same(e, clean):
                InputMap.action_erase_event(other, e)
                for o in old:
                    InputMap.action_add_event(other, o)
                displaced = other
    InputMap.action_erase_events(action)
    InputMap.action_add_event(action, clean)
    return displaced

static func reset_defaults() -> void:
    for a in actions():
        if not InputMap.has_action(a):
            InputMap.add_action(a)
    for a in Actions.BINDINGS:
        InputMap.action_erase_events(a)
        for k in Actions.BINDINGS[a]:
            var ev := InputEventKey.new()
            ev.physical_keycode = k
            InputMap.action_add_event(a, ev)
    for a in UI_BINDINGS:
        if Actions.BINDINGS.has(a):
            continue
        InputMap.action_erase_events(a)
        for k in UI_BINDINGS[a]:
            var ev := InputEventKey.new()
            ev.physical_keycode = k
            InputMap.action_add_event(a, ev)
    for a in Actions.MOUSE_BINDINGS:
        InputMap.action_erase_events(a)
        for b in Actions.MOUSE_BINDINGS[a]:
            var ev := InputEventMouseButton.new()
            ev.button_index = b
            InputMap.action_add_event(a, ev)

static func save(path := PATH) -> void:
    var cfg := ConfigFile.new()
    for a in actions():
        var list := []
        for e in InputMap.action_get_events(a):
            if e is InputEventKey:
                list.append("key:%d" % e.physical_keycode)
            elif e is InputEventMouseButton:
                list.append("mouse:%d" % e.button_index)
        cfg.set_value("bindings", a, list)
    cfg.save(path)

static func load_saved(path := PATH) -> bool:
    ensure_ui_actions()
    var cfg := ConfigFile.new()
    if cfg.load(path) != OK:
        return false
    for a in actions():
        if not cfg.has_section_key("bindings", a) or not InputMap.has_action(a):
            continue
        InputMap.action_erase_events(a)
        for s in cfg.get_value("bindings", a, []):
            var parts := str(s).split(":")
            if parts.size() != 2:
                continue
            if parts[0] == "key":
                var ev := InputEventKey.new()
                ev.physical_keycode = int(parts[1])
                InputMap.action_add_event(a, ev)
            elif parts[0] == "mouse":
                var ev := InputEventMouseButton.new()
                ev.button_index = int(parts[1])
                InputMap.action_add_event(a, ev)
    return true
