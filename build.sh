#!/usr/bin/env bash
# Approval gate: a patch is approved only if this script exits 0.
#   1. import  2. unit + physics tests  3. headless gameplay smoke  4. export Linux + Windows  5. zip
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/godot/godot}"
VER=0.4
LOG=build/build.log
mkdir -p build dist/windows dist/linux
: > "$LOG"
# Any SCRIPT ERROR / ERROR / GDScript backtrace fails the gate unless listed in tests/expected_warnings.txt.
fail_on_errors() { python3 tools/check_log.py "$@" || { echo "!! script/engine errors in $*"; exit 1; }; }

echo "[1/5] import";   "$GODOT" --headless --path . --import >build/import.log 2>&1 || true; fail_on_errors build/import.log
echo "[2/5] tests (auto-discovered unit suites + integration sims incl. abilities_sim)";    "$GODOT" --headless --path . -s tests/run_tests.gd 2>&1 | tee build/tests.log; grep -q "RESULT: .* 0 failed" build/tests.log; fail_on_errors build/tests.log
echo "[3/5] smoke (every map x every hero)"
: > build/smoke.log
SMOKE_S=${SMOKE_S:-35}
for m in $(ls src/maps/*.json | xargs -n1 basename | sed 's/\.json$//'); do
for h in $(ls src/heroes/*.json | xargs -n1 basename | sed 's/\.json$//'); do
  L=build/smoke_${m}_$h.log
  timeout 180 "$GODOT" --headless --path . -- --smoke=$SMOKE_S --force_end=$((SMOKE_S - 3)) --hero="$h" --map="$m" > $L 2>&1 || true
  cat $L >> build/smoke.log
  echo "  $m/$h: $(grep -E '^SMOKE' $L || echo 'SMOKE MISSING')  $(grep -E '^STATS' $L)"
  grep -q "SMOKE PASS" $L || { echo "!! smoke failed for $m/$h"; exit 1; }
done; done
fail_on_errors build/smoke.log
echo "[3b/5] network: 2 headless instances (host + client) on localhost"
OUT=build/net ./tools/net_test.sh | tee build/net_test.log; grep -q "NET TEST PASS" build/net_test.log
echo "[4/5] export";   rm -rf dist/windows/* dist/linux/*
"$GODOT" --headless --path . --export-release "Linux" dist/linux/arena.x86_64 >build/export_linux.log 2>&1; fail_on_errors build/export_linux.log
"$GODOT" --headless --path . --export-release "Windows Desktop" dist/windows/Arena.exe >build/export_win.log 2>&1; fail_on_errors build/export_win.log
test -s dist/windows/Arena.exe && test -s dist/windows/Arena.pck
echo "[5/5] zip"
rm -f dist/arena-$VER-windows.zip
python3 -c "import zipfile,sys;z=zipfile.ZipFile(sys.argv[1],'w',zipfile.ZIP_DEFLATED,compresslevel=9);[z.write('dist/windows/'+f,'Arena/'+f) for f in ('Arena.exe','Arena.pck')]" dist/arena-$VER-windows.zip
ls -la dist/arena-$VER-windows.zip
echo "BUILD OK"
