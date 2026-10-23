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

## Heroes added in v0.2 (heroes branch)
| Hero | Role | Primary | Ability 1 | Ability 2 | Ultimate |
|---|---|---|---|---|---|
| Rampart | Tank | Hitscan 9 dmg | Bull Rush (charge, 40 dmg + knockback) | Bulwark (5 s shield wall) | Fault Line (AoE 180) |
| Willow | Support | Hitscan 11 dmg | Mending Beam (3 s heal channel) | Frost Bolt (projectile, 30 dmg, 50% slow) | Second Wind (team heal 150) |

Deferred to v0.2: projectile *primary* fire (`"primary": {"type": "projectile"}`, heroes request 3) —
needs a Weapon/schema change in core; declined for now.

## v0.3 roster (replaces the placeholders, which moved to src/heroes/archive/)
| Hero | Role | Primary | Ability 1 | Ability 2 | Ultimate |
|---|---|---|---|---|---|
| Twin Tails | Support | Hitscan 11, heals an ally 7 per hit | Encore Beam (4 s: heal an ally, or a red 1 m beam that damages enemies in its path; Shift again cancels; cannot shoot during it) | Staccato Note (30 damage, heals allies it passes for 19) | Grand Finale (team heal) |
| The Best | Brawler | Melee 3-hit combo | Fearless Leap | Swagger Step (dash) | No Limits (team buff + overheal) |
| Cob | Tank | Hitscan | Boulder Roll (charge) | Geode Wall (shield wall) | Quarry Quake (slam) |

## v0.9 roster (added on top of v0.3; numbers from the hero JSON)
| Hero | Role | Primary | Ability 1 | Ability 2 | Ultimate |
|---|---|---|---|---|---|
| Tomo | Duelist | Packet Burst 3×15, 14/s in a burst, 0.36 s between bursts, 24 mag | Hotfix (blink) | Breakpoint (root projectile) | Force Push (9 m cone) |
| Niđo | Brawler, 300 HP | Ping Hammer melee 30 ×[1, 1, 1.4], 1.6/s, 3 m, 3rd hit knockback 5 | Firewall (3.4 m wall, 3.5 s, 10 s CD) | Stand-up Meeting (8 m pull + 60% slow 2 s, 9 s CD) | Rollback (10 m, 4 s window, 35% DR 4 s, 600 ult) |
| Übel | Dive, 250 HP | Paper Cut melee 25, 2.5/s, 2.8 m | Uninvited Guest (ride, 10 m) | Clean Cut (6 m line) | Last Smile (nova, 6 m, 150) |

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
- Windows build size with official templates is ~109 MB exe → ~38 MB zip; a custom-compiled
  template with unused modules disabled is the planned fix for the 24 MB target.
