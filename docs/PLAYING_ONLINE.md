# Playing online (v0.4)

One player **hosts** (their PC runs the match) and up to 5 friends **join** over the internet.
Empty slots are filled with bots. The host's PC decides everything (hits, deaths, captures), so the
host should be the player with the best internet connection and the strongest PC.

## Hosting
1. Start Arena, pick your **hero** (Hero select) and **map** (Map select) in the main menu.
2. Click **Host online**. Keep the port at **24565** unless you have a reason to change it, then click **Start hosting**.
3. The screen (and the top-left corner in game) shows your public address, e.g. `203.0.113.7:24565`.
   Send that to your friends. If it can't be found, search "what is my IP" in a browser.
4. When the match starts, Arena asks the router to open that UDP port (UPnP). You do not install a VPN,
   Hamachi, Radmin, or anything else. The corner says whether the router accepted it.
5. The first time, **Windows Defender Firewall** asks whether Arena may communicate on networks.
   Tick **Private** *and* **Public** and click **Allow access**. If you clicked Cancel by mistake:
   Windows Settings → Privacy & security → Windows Security → Firewall & network protection →
   *Allow an app through firewall* → Change settings → tick both boxes for Arena.exe (or remove the rule and start again).

## If friends cannot connect
Arena already tried to open the port. If the corner says the router refused, forward it once:
1. Find your PC's local IP: open Command Prompt, run `ipconfig`, note the *IPv4 Address* (like `192.168.1.23`).
   The Host screen also lists it under "Same network (LAN)".
2. Open your router's admin page (usually `http://192.168.1.1` or `http://192.168.0.1`; login is often on a sticker on the router).
3. Find **Port Forwarding** (also called *Virtual Server*, *NAT* or *Applications & Gaming*) and add a rule:
   - external port **24565**, internal port **24565**, protocol **UDP**, target = your PC's local IP.
4. Save. It helps to give your PC a fixed local IP (*DHCP reservation*) so the rule keeps working.

Some ISPs use carrier-grade NAT: the address on the router's WAN page differs from your public IP.
Port opening cannot work then. A friend whose corner says the port opened should host instead.

Players on the **same network** as the host join with the LAN address (e.g. `192.168.1.23:24565`), not the public one.

## Joining
1. Start Arena, pick your **hero** in Hero select (the host picks the map).
2. Click **Join online**, type the host's address such as `203.0.113.7:24565` (the port can be left out if it is 24565), and click **Connect**.
3. You are placed on the team with fewer human players, replacing a bot.
   If nothing happens for ~10 s, the host's port forwarding or firewall is probably not set up.

Esc opens the menu but the game keeps running online. Leaving the match (or the host quitting) returns you to the main menu.

## Known limitations
- Tested on one machine over localhost only. How it feels over real internet latency is not verified yet; a ping of 100 ms or less should be fine.
- Your own movement is predicted, but dashes and leaps can snap slightly when the host corrects them.
- If a player leaves, their slot stays empty until the next match. You can't rejoin a match in progress after the host restarts it.

## Later
A relay would also cover ISPs that hide the host. Direct join, with the router port opened by the game, is what shipping builds do.
