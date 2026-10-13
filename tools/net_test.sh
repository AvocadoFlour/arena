#!/usr/bin/env bash
# 2-instance network test: headless host + headless client on localhost, both autopiloted.
# Asserts both saw the same kills, the client's hp at its last snapshot matches the host's, and match_ended agrees.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/godot/godot}
PORT=${NET_TEST_PORT:-24599}
OUT=${OUT:-/tmp/arena_net}
mkdir -p "$OUT"
"$GODOT" --headless --path . -- --net_host=$PORT --hero=cob --map=arena01 --autopilot --force_end=24 --net_test=30 >"$OUT/host.log" 2>&1 &
HP=$!
sleep 3
"$GODOT" --headless --path . -- --net_join=127.0.0.1:$PORT --hero=the_best --autopilot --net_test=40 >"$OUT/client.log" 2>&1 &
CP=$!
wait $HP; HE=$?
wait $CP; CE=$?
python3 tools/check_log.py "$OUT/host.log" && python3 tools/check_log.py "$OUT/client.log" || { echo "NET TEST FAIL: errors in logs ($OUT)"; exit 1; }
python3 - "$OUT/host.log" "$OUT/client.log" <<'PY'
import json, sys
def dump(p):
    for l in open(p, errors="replace"):
        if l.startswith("NETDUMP "):
            return json.loads(l[8:])
    sys.exit(f"NET TEST FAIL: no NETDUMP in {p}")
h, c = dump(sys.argv[1]), dump(sys.argv[2])
fails = []
if h["peers"] != 1: fails.append("host peers=%s" % h["peers"])
if h["inputs_received"] < 300: fails.append("host got only %d inputs" % h["inputs_received"])
if h["remote_dmg"] <= 0: fails.append("client hero dealt no damage on the host")
if not h["kills"]: fails.append("no kills after join")
if h["kills"] != c["kills"]: fails.append("kills differ: host %d vs client %d" % (len(h["kills"]), len(c["kills"])))
if not h["match_ended"] or h["match_ended"] != c["match_ended"]: fails.append("match_ended differs: %s vs %s" % (h["match_ended"], c["match_ended"]))
snap = h["snap_hp"].get(str(c["server_tick"]))
if snap is None: fails.append("host has no snapshot for client tick %s" % c["server_tick"])
elif any(abs(float(snap[k]) - float(v)) > 1e-3 for k, v in c["hp"].items()) or set(snap) != set(c["hp"]):
    fails.append("hp differs at tick %s: %s vs %s" % (c["server_tick"], snap, c["hp"]))
print("NET host: kills=%d remote_dmg=%.0f inputs=%d | client: kills=%d tick=%d reconciles=%d max_corr=%.3f m (respawn snaps excluded: %d, max %.1f m; >2 m: %s; deaths %d) | match_ended=%s"
      % (len(h["kills"]), h["remote_dmg"], h["inputs_received"], len(c["kills"]), c["server_tick"], c["reconciles"], c["max_correction"], c.get("teleports", 0), c.get("max_teleport", 0), c.get("big_corrections", []), c.get("deaths", 0), h["match_ended"]))
if fails:
    print("NET TEST FAIL: " + "; ".join(fails)); sys.exit(1)
print("NET TEST PASS")
PY
