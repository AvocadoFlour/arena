#!/usr/bin/env bash
# Builds the slim Windows release export template (GL Compatibility only, used modules only) from Godot
# 4.7.2-stable source. Output: ~/godot-tpl/arena-windows-release.exe (picked up by ./build.sh).
# Needs: scons, mingw-w64 with posix threads (a PATH shim to the *-posix compilers is created if needed).
set -euo pipefail
SRC=${GODOT_SRC:-$HOME/godot-src}
[ -d "$SRC" ] || git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot.git "$SRC"
SHIM=$HOME/mingw-posix/bin; mkdir -p "$SHIM"
for t in gcc g++ gcc-ar gcc-nm gcc-ranlib; do
  [ -e /usr/bin/x86_64-w64-mingw32-$t-posix ] && ln -sf /usr/bin/x86_64-w64-mingw32-$t-posix "$SHIM/x86_64-w64-mingw32-$t"
done
export PATH=$SHIM:$PATH
HERE=$(cd "$(dirname "$0")" && pwd)
(cd "$SRC" && nice scons profile="$HERE/custom.py" winrt=no accesskit=no -j"$(nproc)")
mkdir -p ~/godot-tpl && cp "$SRC/bin/godot.windows.template_release.x86_64.exe" ~/godot-tpl/arena-windows-release.exe
ls -la ~/godot-tpl/arena-windows-release.exe
