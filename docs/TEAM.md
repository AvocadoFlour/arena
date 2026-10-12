# Arena team protocol

Lead: Miku (owns src/core, docs/INTERFACES.md, docs/DESIGN.md, build.sh, tests infra, main branch, merging).

| Bot | Branch | Owns (may edit ONLY these paths) |
|---|---|---|
| Arena Heroes | heroes | src/heroes/, src/abilities/, tests/heroes_*, tests/abilities_* |
| Arena AI | ai | src/ai/, tests/ai_* |
| Arena Maps | maps | src/maps/, tests/maps_* |
| Arena UI | ui | src/ui/, platform/ (export presets for Android later), tests/ui_* |

Rules
1. Work in your own git worktree: /workspace/arena-wt/<branch> (`git -C /workspace/arena worktree add /workspace/arena-wt/<branch> -b <branch> main` if missing). Never edit /workspace/arena (main) directly.
2. Edit only paths you own. If you need a change outside them (esp. src/core or INTERFACES.md), write a request in docs/requests/<branch>.md in your branch and message the lead. Do not work around the interface.
3. Before handing in: rebase on latest main, run ./build.sh in your worktree; it must pass (tests + automated gameplay run + export, zero script errors).
4. Hand in at most once per hour: commit, then message the lead with branch, commit hash, summary, test result.
5. Do not start the next feature until the lead confirms the latest integrated build on main passes with your patch. Meanwhile only fix review feedback.
6. Never modify another bot's branch or worktree. Never push anywhere external.
7. Art: stylised low-poly/toon, original only. No Marvel/third-party IP or assets.
