class_name NetPanel
extends Control
## Online play screens (Host / Join), opened from the main menu. Hero and map come from the
## main menu's current selection; registered with MainMenu.add_screen (UiCatalog). Emits host_requested(port) / join_requested(addr, port).
signal host_requested(port: int)
signal join_requested(address: String, port: int)
signal closed

var kind := "host"
var status: Label
var port_edit: LineEdit
var addr_edit: LineEdit

func _init(k: String = "host") -> void:
    kind = k

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_anchors_preset(Control.PRESET_FULL_RECT)
    var bg := ColorRect.new()
    bg.color = Color(0.04, 0.06, 0.1, 0.97)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(bg)
    var m := MenuStyle.margin()
    bg.add_child(m)
    var v := VBoxContainer.new()
    v.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_theme_constant_override("separation", 14)
    m.add_child(v)
    v.add_child(MenuStyle.title("HOST ONLINE GAME" if kind == "host" else "JOIN ONLINE GAME"))
    var sel := MenuStyle.label("Hero: %s     Map: %s" % [UiCatalog.selected_hero.get_file().get_basename(),
        UiCatalog.selected_map.get_file().get_basename()] if kind == "host" else
        "Hero: %s" % UiCatalog.selected_hero.get_file().get_basename(), 20)
    sel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(sel)
    if kind == "host":
        port_edit = _edit(str(Net.DEFAULT_PORT))
        v.add_child(_labeled("Port (UDP)", port_edit))
        status = MenuStyle.label("Finding your public IP...", 20)
        Net.public_ip_ready.connect(_on_ip)
        Net.fetch_public_ip()   # no HTTP when Net.offline (tests): reports "" immediately
    else:
        addr_edit = _edit("")
        addr_edit.placeholder_text = "host IP:port, e.g. 203.0.113.7:%d" % Net.DEFAULT_PORT
        v.add_child(_labeled("Address", addr_edit))
        status = MenuStyle.label("Enter the address the host gave you.", 20)
    status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    v.add_child(status)
    var go := MenuStyle.button("Start hosting" if kind == "host" else "Connect", _go)
    go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    v.add_child(go)
    var back := MenuStyle.button("Back", func(): closed.emit())
    back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    v.add_child(back)

func _edit(t: String) -> LineEdit:
    var e := LineEdit.new()
    e.text = t
    e.custom_minimum_size = Vector2(360, 0)
    MenuStyle.style_line_edit(e)
    return e

func _labeled(t: String, c: Control) -> HBoxContainer:
    var h := HBoxContainer.new()
    h.alignment = BoxContainer.ALIGNMENT_CENTER
    var l := MenuStyle.label(t, 22)
    l.custom_minimum_size = Vector2(160, 0)
    h.add_child(l)
    h.add_child(c)
    return h

func _on_ip(ip: String) -> void:
    if status == null:
        return
    var p := port_edit.text if port_edit else str(Net.DEFAULT_PORT)
    var lan := ", ".join(Net.lan_addresses())
    status.text = ("Friends join with:  %s:%s\n" % [ip, p] if ip != "" else "Could not look up your public IP (check whatsmyip in a browser).\n") \
        + ("Same network (LAN): %s:%s\n" % [lan, p] if lan != "" else "") \
        + "Starting the match opens UDP %s on the router. No VPN or other program. If a friend still cannot connect, forward that UDP port to this PC." % p

## "IP:port" or "IP" -> [ip, port]
static func parse_address(s: String) -> Array:
    s = s.strip_edges()
    var i := s.rfind(":")
    if i > 0 and s.count(":") == 1:
        return [s.left(i), int(s.substr(i + 1)) if s.substr(i + 1).is_valid_int() else Net.DEFAULT_PORT]
    return [s, Net.DEFAULT_PORT]

func _go() -> void:
    if kind == "host":
        var p := int(port_edit.text) if port_edit.text.is_valid_int() else Net.DEFAULT_PORT
        host_requested.emit(clampi(p, 1024, 65535))
    else:
        var a := parse_address(addr_edit.text)
        if String(a[0]) == "":
            status.text = "Enter an address first."
            return
        status.text = "Connecting to %s:%d ..." % a
        join_requested.emit(a[0], a[1])

func set_status(t: String) -> void:
    if status:
        status.text = t
