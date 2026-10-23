# Übel

Fan character based on Übel (Frieren). Fine for private play; must be replaced with an original design before any commercial release.

Mage (250 HP, speed 7.6). Data: `src/heroes/ubel.json`; model: `src/heroes/models/ubel/` (Blender
script `blender/build_ubel.py` -> `ubel.glb`, ~6k tris, scaled 1.1 in game).

| Slot | Name | Type | What it does |
|---|---|---|---|
| LMB | Magma Thread | magma | Hold to pour a wavy magma stream, 16 m, 0.7 m wide, 36 damage/s to enemies it touches. No ammo. |
| Shift | Uninvited Guest | ride (new) | leap (0.3 s) onto an enemy head within 10 m (30° cone, line of sight) and ride it for 4 s; cooldown 10 s from the leap |
| E | Clean Cut | line_slash (new) | 60 damage to every enemy in a 6 x 1.2 m strip ahead, through cover; cooldown 7 s |
| Q | Last Smile | nova | 150 damage within 6 m (falloff to 50% at the edge); 500 charge |

Riding (`src/abilities/ride.gd`, host-authoritative): the victim keeps control and carries her; she keeps aiming,
casting, and pouring magma (the stream hits the victim when she aims at them; Clean Cut always reaches the victim and the ground). Jump or
Shift hops off (Shift with another enemy within 8 m hops onto that head; the ride time carries over). Knockback,
root, `Hero.cancel_ride()` (stuns), the timer, her death or the victim's death end it. Collision exceptions both
ways while riding; she stays targetable. Replicated through a MountLink net prop
(`src/abilities/mount_link.gd`, kind `mount:<rider>:<victim>`): clients show the `ride_loop` pose, the local
rider is predicted on the displayed head and replays no movement while mounted.
