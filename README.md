# Arena

**Version 0.9.1.** Repo: <https://github.com/AvocadoFlour/arena> (private)

Arena is an original third-person hero shooter built in Godot 4.7.2, for Windows PCs first. You pick a hero with unique abilities (left click, right-click, Q, E, Shift and an ultimate for now at leaest) and fight alongside or against bots and friends.

## Heroes
| Hero | Role |
|---|---|
| The Best | Brawler |
| Tomo | Duelist |
| Niđo | Brawler |
| Cob | Tank |
| Twin Tails | Support |

See `docs/ROSTER.md` for details.

## Game modes and maps
- **Free-for-all:** every player for themselves.
- **Control:** two teams fight over a capture zone.

Maps: Proving Grounds and Twin Spires.

## Online play
One player hosts and up to 5 friends join over the internet, with bots filling empty slots. See `docs/PLAYING_ONLINE.md`.

There's also a settings menu, and you can change the bot count, hero and team during a match.

## Build and run
```
./build.sh
```
This runs the full gate (import, unit tests, a headless smoke test on every map and hero, a network test, then the Linux and Windows exports) and packages `dist/arena-<version>-windows.7z`. Set `GODOT=/path/to/godot` if Godot isn't at `~/godot/godot`. To play, unpack the .7z on Windows and run `Arena.exe`.

## Docs
- `docs/DESIGN.md`: game design
- `docs/INTERFACES.md`: code interfaces
- `docs/TEAM.md`: who owns what

Audio credits: `src/ui/audio/LICENSES.md` (LibreQuake, BSD-3).
