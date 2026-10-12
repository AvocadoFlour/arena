#!/usr/bin/env bash
# v0.2 screenshots from the Linux export under Xvfb.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=dist/linux/arena.x86_64
shot() { local name=$1; shift; timeout 150 xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" --resolution 1280x720 --rendering-driver opengl3 -- --screenshot="$PWD/shots/$name.png" "$@" > build/$name.log 2>&1; echo "$name: $(grep -E 'SCREENSHOT|SCRIPT ERROR' build/$name.log | head -2) $(grep -E '^STATS' build/$name.log | cut -c1-160)"; }
shot v0.2-main-menu --mainmenu --delay=2
shot v0.2-hero-select --mainmenu --ui_screen=heroes --delay=2
shot v0.2-rampart-shield-wall --hero=rampart --map=arena01 --use=ability2 --use_lead=0.5 --delay=7
shot v0.2-willow-frost-bolt --hero=willow --map=arena01 --use=ability2 --use_lead=0.12 --delay=7
shot v0.2-willow-heal-beam --hero=willow --map=arena01 --use=ability1 --use_lead=0.6 --delay=8
shot v0.2-arena02-mixed-bots --hero=kestrel --map=arena02 --delay=12
