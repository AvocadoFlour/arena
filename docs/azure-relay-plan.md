# Azure Relay Plan for Arena

## Summary

The game currently requires Hamachi for online play. The plan is to host a relay server on Azure so players can connect over the internet without any VPN or port forwarding.

## Recommended setup

A small always-on Linux VM (B1s or B2ats) running Arena itself as a headless dedicated server using Godot's `--headless` mode. Both players connect to its public IP and port. The existing host/client code should mostly carry over, since the server is just a host with no local player.

**Alternative:** a bare UDP relay that forwards packets between two players while one still acts as host.

## Why not other Azure services

- **Container Apps:** public ingress only takes HTTP and TCP, not UDP.
- **Azure Relay:** a messaging service for TCP and WebSockets, not real-time game traffic.

A plain VM is the simplest fit.

## Rough monthly cost

Approximate pay-as-you-go list prices; check the [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for Nabuca's region.

| Item | Monthly cost |
|---|---|
| VM, always on | about €4 (B1ls) to €7–8 (B1s); a B1s is plenty for a two-player match; a headless Godot server could use about €8–10 for more headroom |
| Static public IP | about €3–4 |
| Disk | about €1–2 |
| Outbound traffic | two players at roughly 50–100 kbps each comes to a few GB a month, inside Azure's free first 100 GB (bandwidth figure is an estimate, not a measurement) |
| **Total** | **about €8–15 a month**, or less if the VM only runs during play sessions, because a stopped VM only pays for disk and IP |

Nabuca's budget is roughly €100–150/month, so there is plenty of headroom.


## Azure DevOps auto-deploy

Yes. A pipeline in Azure Pipelines can export the Linux headless build with Godot on each push, then copy it to the VM over SSH or through a deployment group agent installed on the VM, and restart a `systemd` service. The VM itself can be set up once with a Bicep or Terraform template, run from the same pipeline. Microsoft-hosted pipeline agents give 1,800 free minutes a month on private projects, which is plenty.

## Caveats

1. **Code work is needed:** a headless dedicated-server mode, server-only startup, and making sure nothing on the server assumes a local player or a screen. This is moderate work on the networking code.
2. **Security:** open only the game's UDP port and SSH (ideally SSH from Nabuca's IP only), and keep the OS patched.
3. **Single region:** ping depends on how far players are from the chosen region, so pick the one nearest both players, e.g. West Europe or Germany West Central.
4. **B-series VMs run on CPU credits:** fine for two players, but a busy server with lots of bots could run out of credits.
5. **Cheaper alternative:** Steam's free relay through the GodotSteam plugin, if Arena goes on Steam. It costs nothing to run, but needs a Steam app ID ($100 fee), and both players need Steam.

## Open questions / next steps

- Turn this into a step-by-step setup plan, or price it exactly for Nabuca's region.
- The headless server mode and any networking code changes are Grok builder jobs. Check with Nabuca before spending usage on them.

---

*Documentation only. No game code or Azure resources were changed.*
