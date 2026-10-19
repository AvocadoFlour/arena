#!/usr/bin/env bash
# Approval gate: a patch is approved only if this script exits 0.
#   1. import  2. unit + physics tests  3. headless gameplay smoke  4. export Linux + Windows  5. zip
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/godot/godot}"
VER=0.9.4
LOG=build/build.log
mkdir -p build dist/windows dist/linux
: > "$LOG"
# Any SCRIPT ERROR / ERROR / GDScript backtrace fails the gate unless listed in tests/expected_warnings.txt.
fail_on_errors() { python3 tools/check_log.py "$@" || { echo "!! script/engine errors in $*"; exit 1; }; }

echo "[1/5] import (always re-imports changed assets, so fresh checkouts never use stale models)"
"$GODOT" --headless --path . --import >build/import.log 2>&1 || true; fail_on_errors build/import.log
# every 3D model must have an up-to-date import (.import + imported resource in .godot/imported)
python3 - <<'PY' || { echo "!! asset import missing/stale"; exit 1; }
import os, re, subprocess, sys
bad = []
for f in subprocess.check_output(["git", "ls-files", "*.glb", "*.gltf", "*.fbx", "*.blend"], text=True).split():
    imp = f + ".import"
    if not os.path.exists(imp):
        bad.append(f + " (no .import)"); continue
    txt = open(imp).read()
    for dest in re.findall(r'^path(?:\.\w+)?="res://(.+?)"', txt, re.M):
        if not os.path.exists(dest) or os.path.getmtime(dest) < os.path.getmtime(f):
            bad.append(f + " -> " + dest)
if bad:
    print("stale imports:", bad); sys.exit(1)
PY
echo "[2/5] tests (auto-discovered unit suites + integration sims incl. abilities_sim)";    "$GODOT" --headless --path . -s tests/run_tests.gd 2>&1 | tee build/tests.log; grep -q "RESULT: .* 0 failed" build/tests.log; fail_on_errors build/tests.log
echo "[3/5] smoke (every map x every hero)"
: > build/smoke.log
SMOKE_S=${SMOKE_S:-35}
SMOKE_T0=$(date +%s); SMOKE_RUNS=0
echo "    smoke start: $(TZ=Europe/Warsaw date '+%Y-%m-%d %H:%M:%S %Z')"
# Timing never fails the build: it only prints, warns and appends to build/smoke_durations.csv / smoke_alerts.log.
smoke_timing() {
  local dur=$(( $(date +%s) - SMOKE_T0 )) ts; ts=$(TZ=Europe/Warsaw date '+%Y-%m-%dT%H:%M:%S%z')
  echo "    smoke end: $(TZ=Europe/Warsaw date '+%Y-%m-%d %H:%M:%S %Z')  total ${dur}s, ${SMOKE_RUNS} runs"
  [ -f build/smoke_durations.csv ] || echo "timestamp,version,runs,seconds" > build/smoke_durations.csv
  echo "$ts,$VER,$SMOKE_RUNS,$dur" >> build/smoke_durations.csv
  if [ "$dur" -gt 600 ]; then
    echo "WARNING: SMOKE SLOW: ${dur}s > 600s (${SMOKE_RUNS} map x hero runs)"
    echo "$ts version=$VER duration=${dur}s runs=$SMOKE_RUNS" >> build/smoke_alerts.log
  fi
  return 0
}
for m in $(ls src/maps/*.json | xargs -n1 basename | sed 's/\.json$//'); do
for h in $(ls src/heroes/*.json | xargs -n1 basename | sed 's/\.json$//'); do
  L=build/smoke_${m}_$h.log
  RUN_T0=$(date +%s)
  timeout 180 "$GODOT" --headless --path . -- --smoke=$SMOKE_S --force_end=$((SMOKE_S - 3)) --hero="$h" --map="$m" > $L 2>&1 || true
  SMOKE_RUNS=$((SMOKE_RUNS + 1))
  cat $L >> build/smoke.log
  echo "  $m/$h: $(grep -E '^SMOKE' $L || echo 'SMOKE MISSING')  ($(( $(date +%s) - RUN_T0 ))s)  $(grep -E '^STATS' $L)"
  grep -q "SMOKE PASS" $L || { echo "!! smoke failed for $m/$h"; smoke_timing; exit 1; }
done; done
smoke_timing
fail_on_errors build/smoke.log
echo "[3b/5] network: 2 headless instances (host + client) on localhost"
OUT=build/net ./tools/net_test.sh | tee build/net_test.log; grep -q "NET TEST PASS" build/net_test.log
echo "[4/5] export";   rm -rf dist/windows/* dist/linux/*
"$GODOT" --headless --path . --export-release "Linux" dist/linux/arena.x86_64 >build/export_linux.log 2>&1; fail_on_errors build/export_linux.log
# Slim Windows template (tools/win_template/build.sh, ~42 MB vs 109 MB stock); falls back to the stock template.
WIN_TPL=${ARENA_WIN_TEMPLATE:-$HOME/godot-tpl/arena-windows-release.exe}
if [ -f "$WIN_TPL" ]; then
  cp export_presets.cfg build/export_presets.cfg.bak
  trap 'cp build/export_presets.cfg.bak export_presets.cfg' EXIT
  python3 - "$WIN_TPL" <<'PY'
import sys,re
s=open('export_presets.cfg').read()
a=s.index('[preset.0.options]'); b=s.index('[preset.1]')
s=s[:a]+s[a:b].replace('custom_template/release=""','custom_template/release="%s"'%sys.argv[1])+s[b:]
open('export_presets.cfg','w').write(s)
PY
  echo "    windows template: $WIN_TPL"
else
  echo "    windows template: STOCK (run tools/win_template/build.sh for the slim one)"
fi
"$GODOT" --headless --path . --export-release "Windows Desktop" dist/windows/Arena.exe >build/export_win.log 2>&1; fail_on_errors build/export_win.log
[ -f "$WIN_TPL" ] && cp build/export_presets.cfg.bak export_presets.cfg && trap - EXIT
test -s dist/windows/Arena.exe && test -s dist/windows/Arena.pck
echo "[5/5] zip"
# third-party audio licences (BSD-3 etc.) ship next to Arena.exe
cp src/ui/audio/LICENSES.md dist/windows/LICENSES-audio.md
rm -f dist/arena-$VER-windows.zip
python3 -c "import zipfile,sys;z=zipfile.ZipFile(sys.argv[1],'w',zipfile.ZIP_DEFLATED,compresslevel=9);[z.write('dist/windows/'+f,'Arena/'+f) for f in ('Arena.exe','Arena.pck','LICENSES-audio.md')]" dist/arena-$VER-windows.zip
ls -la dist/arena-$VER-windows.zip
rm -f dist/arena-$VER-windows.7z
if command -v 7z >/dev/null; then
  (cd dist/windows && 7z a -mx=9 ../arena-$VER-windows.7z Arena.exe Arena.pck LICENSES-audio.md >/dev/null)
  SZ=$(stat -c %s dist/arena-$VER-windows.7z); echo "    7z: $SZ bytes"
  [ "$SZ" -lt 23000000 ] || echo "!! WARNING: Windows 7z package >= 23 MB"
fi
echo "BUILD OK"
