# Saving Grok Builder Usage

What Nabuca can do locally, on their own PC, to slow down Grok builder usage.

| Task | How to do it |
|---|---|
| Run tests and smoke runs | Open Git Bash in the project folder and run `build.sh`. |
| Pull the latest code | `git pull` |
| Play the game | Open the project in Godot 4.7.2 and press play. |
| Watch a build and read results | Check the build output and test/smoke results yourself. |
| Commit and push your own changes | `git add`, `git commit`, `git push` (no force-push). |
| Do clean merges | `git merge`, and only if git reports no conflicts. |
| Edit hero numbers | Change values in a hero `.json` file, like damage, range or cooldown. |
| Change volume levels | Edit the existing sound settings. |
| Export a Windows build | Use the Godot editor's export. |
| Test builds and write up bugs | Play the build and write steps to reproduce. |

**Rule of thumb:** if a task means running something, checking something or changing a number, do it locally. If it means deciding how something should work or untangling why it doesn't, use the builder.
