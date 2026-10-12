# Arena — design doc (v0.1 skeleton)

## Vision
An original third-person hero shooter, mechanically inspired by Marvel Rivals (fast hero
movement, cooldown abilities, damage-charged ultimates, team fights). **No Marvel characters,
names or assets.** Free-speech-friendly chat later (player-side mute, no automatic word filter);
no chat in v0.1.

## Platforms
PC (Windows) first. Must stay portable to Android/iOS: Godot 4 export, GL Compatibility
renderer, input abstraction so touch controls can be added without gameplay changes.

## Scope of v0.1 (this skeleton)
- 1 hero (Kestrel), 1 map (Proving Grounds), 3 bots, free-for-all vs bots, local only.
- Fixed 60 Hz physics (Jolt), gravity, jump, capsule vs box colliders, wall sliding.
- Over-the-shoulder camera that pulls in on walls (SpringArm3D).
- HUD: HP, ammo, cooldowns, ult %, crosshair, hit markers, damage numbers, kill feed, FPS.
- Settings: window mode, resolution, mouse sensitivity (Esc menu).

## Controls (PC)
| Action | Key |
|---|---|
| Move | W A S D |
| Look | Mouse (cursor captured; click to recapture) |
| Fire | Left mouse |
| Jump | Space |
| Ability 1 – Dash | Shift |
| Ability 2 – Ground Slam | E |
| Ultimate – Nova Burst | Q |
| Reload | R |
| Menu / release cursor | Esc |

Touch (planned): left virtual stick = move, right-half drag = look, buttons for the rest —
implemented as an `Actions.sources` provider (see INTERFACES.md §1).

## Heroes
| Hero | Role | Primary | Ability 1 | Ability 2 | Ultimate |
|---|---|---|---|---|---|
| Kestrel | Duelist | Hitscan rifle, 14 dmg, 9/s, 30 rounds, 1.6 s reload | Dash 7 m, 4 s CD | Ground Slam: instant AoE on ground, dive+AoE in air, 70 dmg r5, 8 s CD | Nova Burst: 220 dmg AoE r10, needs 500 damage dealt |

## Roadmap
1. v0.1 skeleton (this). 2. v0.2: 2–3 more heroes, projectile weapons, team 3v3 vs bots,
better bot nav (NavigationRegion3D). 3. v0.3: touch controls + Android export. 4. v0.4:
art pass (models, animation, sound). 5. v0.5: online multiplayer (Godot high-level
multiplayer, server-authoritative; InputFrame is already the network message). 6. Chat with
player-side mute/block and report (required by app stores).

## Decisions
- **Godot 4.7.2 + GDScript** (not Three.js/Electron): native 3D physics (Jolt), one codebase for
  Windows/Android/iOS, built-in networking. Headless export works on Linux.
- **GL Compatibility renderer**: runs on low-end GPUs and mobile, and on Xvfb for CI screenshots.
- **Everything data-driven** (hero JSON, map JSON) and built in code — no .tscn merges between bots.
- **Input sources**: player, bots, future touch and network all produce the same `InputFrame`.
- **Event bus** (`Events`) decouples gameplay from UI/FX.
- **Gate**: `./build.sh` must pass (tests + 40 s gameplay smoke + exports) before any merge.
- Window size via official templates is ~109 MB exe → ~38 MB zip; a custom-compiled
  template with unused modules disabled is the planned fix for the 24 MB target.
