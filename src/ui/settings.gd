extends Node
## Graphics/input settings (autoload "Settings"), persisted to user://settings.cfg.
const PATH := "user://settings.cfg"
const MODES := ["Windowed", "Borderless Fullscreen", "Exclusive Fullscreen"]
const RESOLUTIONS := [
    Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
    Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1280, 800), Vector2i(1920, 1200),
    Vector2i(2560, 1080), Vector2i(3440, 1440),
]
var window_mode := "Windowed"
var resolution := Vector2i(1280, 720)
var sensitivity := 1.0
var skip_apply := false

func _ready() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(PATH) == OK:
        window_mode = cfg.get_value("video", "window_mode", window_mode)
        resolution = cfg.get_value("video", "resolution", resolution)
        sensitivity = cfg.get_value("input", "sensitivity", sensitivity)
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--screenshot") or a.begins_with("--smoke") or a.begins_with("--demo"):
            skip_apply = true
    Keybinds.load_saved()   # user key rebinds on top of Actions defaults
    if not skip_apply:
        apply()

func save() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("video", "window_mode", window_mode)
    cfg.set_value("video", "resolution", resolution)
    cfg.set_value("input", "sensitivity", sensitivity)
    cfg.save(PATH)

## Windowed: resolution = window size. Fullscreen: desktop size; resolution sets 3D render scale.
func apply() -> void:
    Actions.mouse_sensitivity = 0.0025 * sensitivity
    if DisplayServer.get_name() == "headless":
        return
    match window_mode:
        "Borderless Fullscreen":
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
        "Exclusive Fullscreen":
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
        _:
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
            DisplayServer.window_set_size(resolution)
            var scr := DisplayServer.window_get_current_screen()
            var pos := DisplayServer.screen_get_position(scr) + (DisplayServer.screen_get_size(scr) - resolution) / 2
            DisplayServer.window_set_position(pos)
    var vp := get_tree().root
    if window_mode == "Windowed":
        vp.scaling_3d_scale = 1.0
    else:
        var scr_size := DisplayServer.screen_get_size()
        vp.scaling_3d_scale = clampf(float(resolution.y) / float(max(1, scr_size.y)), 0.25, 1.0)
