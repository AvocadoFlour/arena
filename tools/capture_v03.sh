#!/usr/bin/env bash
# v0.3 screenshots from the Linux export under Xvfb (1280x720).
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=dist/linux/arena.x86_64
shot() { local name=$1; shift; timeout 150 xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" --resolution 1280x720 --rendering-driver opengl3 -- --screenshot="$PWD/shots/$name.png" "$@" > build/$name.log 2>&1; python3 tools/check_log.py build/$name.log >/dev/null && ok=clean || ok=ERRORS; echo "$name: $ok $(grep -E '^STATS' build/$name.log | grep -oE '"fps_avg":[0-9.]+')"; }
shot v0.3-hero-select --mainmenu --ui_screen=heroes --delay=2
shot v0.3-twin-tails --hero=twin_tails --map=arena01 --use=ability2 --use_lead=0.12 --delay=7
shot v0.3-the-best --hero=the_best --map=arena01 --use=ability1 --use_lead=0.25 --delay=7
shot v0.3-cob --hero=cob --map=arena01 --use=ability2 --use_lead=0.5 --delay=7
shot v0.3-heal-beam --hero=twin_tails --map=arena02 --use=ability1 --stage_ally --use_lead=0.5 --delay=2.5
shot v0.3-control --hero=cob --map=arena02 --delay=30
