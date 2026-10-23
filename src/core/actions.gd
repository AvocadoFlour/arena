extends Node
## Input abstraction layer (autoload "Actions").
## Physical device -> named action (InputMap) -> InputFrame. Gameplay only ever sees InputFrame.
## Touch / gamepad: append an object with `contribute(frame: InputFrame)` to `sources`.

const BINDINGS := {
    "move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
    "jump": [KEY_SPACE], "ability1": [KEY_SHIFT], "ability2": [KEY_E], "ultimate": [KEY_Q],
    "reload": [KEY_R], "pause": [KEY_ESCAPE],
    "scoreboard": [KEY_TAB],   # UI-only, never part of InputFrame
}
const MOUSE_BINDINGS := {"fire": [MOUSE_BUTTON_LEFT], "ability3": [MOUSE_BUTTON_RIGHT]}

var mouse_sensitivity := 0.0025   ## radians per pixel
var gameplay_enabled := true      ## false while paused / cursor released
var sources: Array = []           ## extra providers (touch, gamepad)
var _look_px := Vector2.ZERO

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    for a in BINDINGS:
        _ensure(a)
        for k in BINDINGS[a]:
            var ev := InputEventKey.new()
            ev.physical_keycode = k
            InputMap.action_add_event(a, ev)
    for a in MOUSE_BINDINGS:
        _ensure(a)
        for b in MOUSE_BINDINGS[a]:
            var ev := InputEventMouseButton.new()
            ev.button_index = b
            InputMap.action_add_event(a, ev)

func _ensure(a: String) -> void:
    if not InputMap.has_action(a):
        InputMap.add_action(a)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        _look_px += event.relative

## Input-source interface: poll(hero) -> InputFrame (called once per physics tick).
func poll(_hero = null) -> InputFrame:
    var f := InputFrame.new()
    if not gameplay_enabled:
        _look_px = Vector2.ZERO
        return f
    f.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
    f.look = -_look_px * mouse_sensitivity
    _look_px = Vector2.ZERO
    f.fire = Input.is_action_pressed("fire")
    f.jump = Input.is_action_just_pressed("jump")
    f.reload = Input.is_action_just_pressed("reload")
    f.ability1 = Input.is_action_just_pressed("ability1")
    f.ability2 = Input.is_action_just_pressed("ability2")
    f.ability3 = Input.is_action_just_pressed("ability3")
    f.ultimate = Input.is_action_just_pressed("ultimate")
    for s in sources:
        s.contribute(f)
    return f
