#!/usr/bin/env bash
# Online Match page check (manual; build.sh's tools/net_test.sh covers the core swap path):
# headless host + headless client probe (tests/ui_net_probe.gd) on a free localhost port.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/godot/godot}
PORT=$(python3 -c "import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.bind(('127.0.0.1',0));print(s.getsockname()[1])")
OUT=$(mktemp -d /tmp/ui_net.XXXXXX)
"$GODOT" --headless --path . -- --net_host=$PORT --hero=cob --map=arena01 --force_end=30 --net_test=35 >"$OUT/host.log" 2>&1 &
HP=$!
sleep 3
timeout 60 "$GODOT" --headless --path . -s tests/ui_net_probe.gd -- --net_join=127.0.0.1:$PORT --hero=the_best >"$OUT/client.log" 2>&1
wait $HP
python3 - "$OUT" <<'PY'
import json, sys, re
d = sys.argv[1]
c = open(d + "/client.log", errors="replace").read()
errs = [l for f in ("host.log", "client.log") for l in open(d + "/" + f, errors="replace") if re.search(r"SCRIPT ERROR|Parse Error|^ERROR:", l)]
m = [l for l in c.splitlines() if l.startswith("UIPROBE ")]
if not m: sys.exit("UI NET FAIL: no UIPROBE (%s)" % d)
r = json.loads(m[0][8:]); print(r)
f = []
if not r.get("client"): f.append("not client")
if not r.get("bots_disabled"): f.append("client bot steppers enabled")
if "host" not in r.get("bot_note", ""): f.append("no host note")
if not r.get("set_refused"): f.append("client set_bot_count accepted")
if "host" not in r.get("hero_note", ""): f.append("no request note")
if "countdown" not in r: f.append("no countdown")
if r.get("new_hero") != r.get("target"): f.append("hero not swapped: %s" % r.get("new_hero"))
if not r.get("countdown_hidden"): f.append("countdown left up")
if errs: f.append("errors: %s" % errs[:3])
print("UI NET FAIL: " + "; ".join(f) if f else "UI NET PASS"); sys.exit(1 if f else 0)
PY
