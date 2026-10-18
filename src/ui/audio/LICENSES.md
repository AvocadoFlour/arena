# Audio licences (src/ui/audio)

All files in `src/ui/audio/lq/` come from the official **LibreQuake** project and are **unmodified, byte-identical copies**
(no pitch change, processing, trimming or format conversion; Godot imports these PCM WAVs as they are).

- Source repository: https://github.com/lavenderdotpet/LibreQuake
- Commit: `dd4d5bffcabbcf9ceca32a1d83829109928c3f08` (2026-10-16, branch master; newest release tag at that time: v0.09-beta)
- Source path: `lq1/sound/<path>`; local path: `src/ui/audio/lq/<path>` (original sub-folders and file names kept)
- Licence: **BSD 3-Clause**, "Copyright © 2019-2023 Contributors to the LibreQuake project" (`docs/COPYING`, quoted in full below).
  `docs/README-IMPORTANT-LICENCE-INFO` states that BSD-3 covers all models, textures and sounds (GPL-2 applies only to the QuakeC, progs.dat and pop.lmp).
  No per-directory or per-file licence notes exist under `lq1/sound/`.
- Selection rule: only files created for LibreQuake. Skipped as unclear: Freedoom/Blasphemer placeholders, files with a Freesound sample mixed in,
  files whose metadata carries 1996 creation dates, and files with a swapped/reworked history.
- No id Software pak data was used.
- Checksums: SHA-256 verified identical against the file in the source repo at the commit above (both the checkout and the git blob).

| Use | Local / source path (`lq1/sound/…`) | Source URL | Licence | Credit | SHA-256 |
|---|---|---|---|---|---|
| The Best: primary fire (Left mouse) | `knight/sword1.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/knight/sword1.wav) | BSD-3-Clause | Jack Folkner / Diplodokus (file IART tag; commit 004fad5 "6/6 knight sounds (temp?) [Jack Folkner/diplodokus]") | `74dcb96eb0b524e722ffbad2e614319d87ae22f91d8c5e37359c6ad2770ff119` |
| The Best: ability1 (Shift) | `demon/djump.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/demon/djump.wav) | BSD-3-Clause | Ashat Maself (commit b18013c "added Ashat Maself's new demon sounds") | `e9a56cb51163357b9a1c8e50e3c54effc0a56ac80e3e0f4915110009a01dbd60` |
| The Best: ability2 (E) | `weapons/ax1.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/weapons/ax1.wav) | BSD-3-Clause | MissLavender (file IART tag) | `bb83236ca82149f261f5f87f88e955fad7e88ff1429292a5b21828bf5f71f516` |
| The Best: ultimate (Q) | `items/damage.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/items/damage.wav) | BSD-3-Clause | MarkieMusic (commit 622d5d4 "16/16 item sounds [MarkieMusic]") | `02317ccbe2c1884ae6dc335e70118f90286d1f590d1d9c80dd45ae24f5261928` |
| The Best: ultimate ready (meter full) | `items/damage3.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/items/damage3.wav) | BSD-3-Clause | MarkieMusic (commit 622d5d4 "16/16 item sounds [MarkieMusic]") | `e07cb7a0aa21ddd3e62a7ef7ca480ad9375b7a3198ef882c6b09597fb35a56c5` |
| Tomo: primary fire (Left mouse) | `enforcer/enfire.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/enforcer/enfire.wav) | BSD-3-Clause | Ashat Maself (commit 25aa101 "10/10 enforcer sounds [Ashat Maself]") | `cfd49c60f4d944bf1e5785f8835b5ceb9103a1932f2b2aeb33e697e64e1da12d` |
| Tomo: ability1 (Shift) | `misc/r_tele1.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/misc/r_tele1.wav) | BSD-3-Clause | LibreQuake contributors (commit 70ad4d1 "14/20 misc sounds [Multiple Artists]", added by MissLavender-LQ) | `10a85cd33a1bcba91d7b5afc9fdcc2845de378047ceedf7d8f28d08d6f489a16` |
| Tomo: ability2 (E) | `weapons/lock4.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/weapons/lock4.wav) | BSD-3-Clause | MarkieMusic (file IART tag) | `865713c81d2cbac6791d448fabf10659088b96d8c526687374a56e8257396322` |
| Tomo: ultimate (Q) | `weapons/grenade.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/weapons/grenade.wav) | BSD-3-Clause | MarkieMusic (file IART tag) | `22550bb08115daf4edf06c06bd07f9aa873ef3a3e78732effd5b0e86f4577fc6` |
| Tomo: ultimate ready (meter full) | `weapons/guncock.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/weapons/guncock.wav) | BSD-3-Clause | MarkieMusic (file IART tag) | `10ac0ca64ccaf923a49e0c266eaeb4e66db0c0247abc6bb52862818402b74c63` |
| Niđo: primary fire (Left mouse) | `player/axhit1.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/player/axhit1.wav) | BSD-3-Clause | wiedo (file IART tag; 16-bit conversion committed by lavender.pet, 70b1377) | `1dcada195d1582fd813f719fbc2b3e417e2c696fdabf1fd15b858b52f46c0195` |
| Niđo: ability1 (Shift) | `items/protect.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/items/protect.wav) | BSD-3-Clause | MarkieMusic (commit 622d5d4 "16/16 item sounds [MarkieMusic]") | `e61ccc5a12327b93be7c9be6f8f43c803057353a2ca434c15e76753397502821` |
| Niđo: ability2 (E) | `misc/talk.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/misc/talk.wav) | BSD-3-Clause | LibreQuake contributors (commit 70ad4d1 "14/20 misc sounds [Multiple Artists]", added by MissLavender-LQ) | `5d27fdf471c02ccd9f4db2276b5644e73767922a74607dd066a5dfc39d7d86f2` |
| Niđo: ultimate (Q) | `items/health1.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/items/health1.wav) | BSD-3-Clause | MarkieMusic (commit 622d5d4 "16/16 item sounds [MarkieMusic]") | `f90fbea0d99bb51398b2a07d891d88f8abebe231cc2ffe6c021dcdd599315c5e` |
| Niđo: ultimate ready (meter full) | `misc/basekey.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/misc/basekey.wav) | BSD-3-Clause | LibreQuake contributors (commit 70ad4d1 "14/20 misc sounds [Multiple Artists]", added by MissLavender-LQ) | `8a8270cf518595dc28989e7ac781b54af5fe6264676dc23e0065c2ba4334b1e1` |
| Cob: primary fire (Left mouse) | `weapons/ric1.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/weapons/ric1.wav) | BSD-3-Clause | MarkieMusic (file IART tag) | `25ad278ccf93a3057367d272fc4dd492d4f202be3ea88d6f29577dcc25aefeef` |
| Cob: ability1 (Shift) | `weapons/bounce.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/weapons/bounce.wav) | BSD-3-Clause | MissLavender and MarkieMusic (file IART tag) | `0532d5538f11bdcac0613c07b63ef6c4eec7e2919399bb24177f7fa55fa05323` |
| Cob: ability2 (E) | `doors/basesec1.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/doors/basesec1.wav) | BSD-3-Clause | ZungrySoft (commit 25c0e25 "Added remaining brush entity sound effects") | `dce0bcb403496245e7ae60dfb13253c801e50d5e3ffbcbb90d1fa006841f3a30` |
| Cob: ultimate (Q) | `demon/dland2.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/demon/dland2.wav) | BSD-3-Clause | Ashat Maself (commit b18013c "added Ashat Maself's new demon sounds") | `1a61b0c30c4aba65c030cf496acc4123322ca80b17337b0b85ae94fde52a479f` |
| Cob: ultimate ready (meter full) | `demon/sight2.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/demon/sight2.wav) | BSD-3-Clause | Ashat Maself (commit b18013c "added Ashat Maself's new demon sounds") | `2cc864b0fe033ddf841db3096113e2c277b7dbdc6309a8ddd866a6a228758c7f` |
| Twin Tails: primary fire (Left mouse) | `misc/menu2.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/misc/menu2.wav) | BSD-3-Clause | LibreQuake contributors (commit 70ad4d1 "14/20 misc sounds [Multiple Artists]", added by MissLavender-LQ) | `f9e689df935b64768d7d6214f83bd67943249bb4cd3ac38fa569abfbbb9f2b48` |
| Twin Tails: ability1 (Shift) | `weapons/lstart.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/weapons/lstart.wav) | BSD-3-Clause | Nolcoz and MarkieMusic (file IART tag) | `40a9f4a707728692bdccb8b9c9aae0ff1ef97fe273e9527b32a7d8729ef5481f` |
| Twin Tails: ability2 (E) | `misc/menu3.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/misc/menu3.wav) | BSD-3-Clause | LibreQuake contributors (commit 70ad4d1 "14/20 misc sounds [Multiple Artists]", added by MissLavender-LQ) | `fa6dc53511d93d2be81c5a8d4e8082a250801c6e64fad63d167cd68d071bbbc5` |
| Twin Tails: ultimate (Q) | `misc/secret.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/misc/secret.wav) | BSD-3-Clause | ZungryWare (ZungrySoft) and MissLavender (file IART tag) | `af6da6afbebd3839ba60f1b0ba25c3c9b9916875cd9d6c9f2f7cb825cf686025` |
| Twin Tails: ultimate ready (meter full) | `items/inv1.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/items/inv1.wav) | BSD-3-Clause | MarkieMusic (commit 622d5d4 "16/16 item sounds [MarkieMusic]") | `0c144ecd64da17b560606e116268a6821703215222258e099f42ac7c5e86ca4f` |
| Cue: an enemy hits me | `player/pain1.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/player/pain1.wav) | BSD-3-Clause | wiedo (file IART tag) | `c4a1d79986f0c755272cab3c7ea137c4536a80ee3305d1dcc760b462034c2ac1` |
| Cue: an enemy hits a teammate | `player/pain5.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/player/pain5.wav) | BSD-3-Clause | wiedo (file IART tag) | `b4a819f90545e30e2bb65d241bf56f31361fe431144db85d798e9f2a3df34ec2` |
| Cue: a teammate gets a kill | `player/death3.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/player/death3.wav) | BSD-3-Clause | wiedo (file IART tag) | `94ffd00a6df7e496709edb8d8ba42005dba00d1ff70d8b524e327026430add6d` |
| Cue: an enemy kills a teammate | `player/death1.wav` | [link](https://github.com/lavenderdotpet/LibreQuake/blob/dd4d5bffcabbcf9ceca32a1d83829109928c3f08/lq1/sound/player/death1.wav) | BSD-3-Clause | wiedo (file IART tag) | `e2314babbfabac4b6c562283f265e9daaea1a9d15c9b9fe5b1c2dc39ce77f092` |

## LibreQuake licence notice (`docs/README-IMPORTANT-LICENCE-INFO`, verbatim)

```
This project contains files under multiple different licenses. Please read the below files for the relevant licensing info.

Please make sure you understand the licences before using in your projects!

[bsd3]
https://www.tldrlegal.com/license/bsd-3-clause-license-revised

[gpl2]
https://www.tldrlegal.com/license/gnu-general-public-license-v2

bsd3 is permissive and is what all the models textures and sounds are under

gpl2 is more restrictive and just applies to the quakec, progs.dat and pop.lmp

docs/COPYING [BSD3 Licence]
docs/freedoom-docs/COPYING.adoc [BSD3 Licence]
docs/misc-docs/LibreProgsDeluxe.md [GPL2 Licence]
docs/misc-docs/pop.lmp.md [GPL2 Licence]
docs/misc-docs/COPYING [GPL2 Licence]
```

## BSD 3-Clause licence text (`docs/COPYING`, verbatim)

```
Copyright © 2019-2023
Contributors to the LibreQuake project.  All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
  * Neither the name of the LibreQuake project nor the names of its
    contributors may be used to endorse or promote products derived from
    this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS
IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

For a list of contributors to the LibreQuake project, see the file
CREDITS.

For a list of resources used in the LibreQuake project, see the directory
docs
```
