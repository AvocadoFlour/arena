#!/usr/bin/env bash
# Runs the exported Linux build under Xvfb in --demo mode: screenshots at several sizes + MP4 video.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=dist/linux/arena.x86_64
mkdir -p shots build
for spec in "1280x720:6" "1920x1080:9" "2560x1080:12" "1600x1200:15"; do
  sz=${spec%%:*}; d=${spec##*:}
  xvfb-run -a -s "-screen 0 ${sz}x24" "$BIN" --resolution "$sz" --rendering-driver opengl3 -- --screenshot="$PWD/shots/demo_${sz}.png" --delay=$d >build/shot_$sz.log 2>&1 || true
done
xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" --resolution 1280x720 --rendering-driver opengl3 -- --screenshot="$PWD/shots/menu_1280x720.png" --delay=3 --menu >build/shot_menu.log 2>&1 || true
# Video: Godot Movie Maker renders every frame at a fixed 30 fps (deterministic, independent of llvmpipe speed)
rm -f build/demo.avi
timeout 1200 xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" --resolution 1280x720 --rendering-driver opengl3 --write-movie "$PWD/build/demo.avi" --fixed-fps 30 -- --demo=${MOVIE_SECONDS:-60} >build/movie.log 2>&1 || true
ffmpeg -y -loglevel error -i build/demo.avi -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -movflags +faststart shots/demo.mp4
ls -la shots
