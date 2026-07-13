# Prime Daemon

Laptop-side API for the **Prime** Android app. Part 1 of the build: token
auth, `/status`, systemd service. File browser, templated commands
(install/delete/etc.), and free-form shell come in later parts.

## Setup on scez-2

```bash
# Copy this folder to the laptop, e.g.:
#   ~/Projects/prime-daemon/

cd ~/Projects/prime-daemon
./setup.sh
systemctl --user start prime-daemon.service
journalctl --user -u prime-daemon.service -f
```

The first run generates an auth token and prints it to the log — copy that
into the Prime app's Settings screen (also saved at `~/.config/prime/token`
if you need it again later).

## Requirements

- Python 3.10+
- Tailscale running and connected (`tailscale ip -4` must return something)
- `systemd --user` (standard on EndeavourOS)

## Endpoints so far

- `GET /health` — unauthenticated, confirms the daemon is up
- `GET /status` — requires `X-Auth-Token` header, returns hostname, uptime,
  disk usage, allowlisted file roots

Test it manually before wiring up the app:

```bash
curl http://<tailscale-ip>:8420/health

curl http://<tailscale-ip>:8420/status \
  -H "X-Auth-Token: <token-from-log>"
```

## Config

Edit `app/config.py` to change:
- `ALLOWLISTED_ROOTS` — which directories the file browser will eventually
  be allowed to touch (defaults: `~/Projects`, `~/Downloads`, `~/.config`)
- `BIND_PORT` — defaults to 8420

The bind *host* is resolved automatically at startup from your current
Tailscale IP (see `run.sh`), so it survives IP changes across reconnects.

## Next parts

1. ~~Skeleton + token auth + `/status` + systemd~~ ← you are here
2. Predefined commands (git status across repos, restart ebot-hub,
   restart hyprpanel, toggle hyprsunset, reboot/suspend)
3. File browser + delete-to-trash
4. Package install/uninstall/search (sudo flow)
5. Free-form shell with confirm + denylist
6. WebSocket streaming for long-running commands
