#!/usr/bin/env bash
# Approval gate: a patch is approved only if this script exits 0.
#   1. import  2. unit + physics tests  3. headless gameplay smoke  4. export Linux + Windows  5. zip
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/godot/godot}"
VER=0.1
LOG=build/build.log
mkdir -p build dist/windows dist/linux
: > "$LOG"
fail_on_errors() { if grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$1" >/dev/null; then grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$1" | head -20; echo "!! errors in $1"; exit 1; fi; }

echo "[1/5] import";   "$GODOT" --headless --path . --import >build/import.log 2>&1 || true; fail_on_errors build/import.log
echo "[2/5] tests";    "$GODOT" --headless --path . -s tests/run_tests.gd 2>&1 | tee build/tests.log; grep -q "RESULT: .* 0 failed" build/tests.log
echo "[3/5] smoke";    timeout 180 "$GODOT" --headless --path . -- --smoke=40 2>&1 | tee build/smoke.log; grep -q "SMOKE PASS" build/smoke.log; fail_on_errors build/smoke.log
echo "[4/5] export";   rm -rf dist/windows/* dist/linux/*
"$GODOT" --headless --path . --export-release "Linux" dist/linux/arena.x86_64 >build/export_linux.log 2>&1; fail_on_errors build/export_linux.log
"$GODOT" --headless --path . --export-release "Windows Desktop" dist/windows/Arena.exe >build/export_win.log 2>&1; fail_on_errors build/export_win.log
test -s dist/windows/Arena.exe && test -s dist/windows/Arena.pck
echo "[5/5] zip"
rm -f dist/arena-$VER-windows.zip
python3 -c "import zipfile,sys;z=zipfile.ZipFile(sys.argv[1],'w',zipfile.ZIP_DEFLATED,compresslevel=9);[z.write('dist/windows/'+f,'Arena/'+f) for f in ('Arena.exe','Arena.pck')]" dist/arena-$VER-windows.zip
ls -la dist/arena-$VER-windows.zip
echo "BUILD OK"
