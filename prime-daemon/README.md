# Prime Daemon

Laptop-side API for the **Prime** Android app. Prime lets you control and
monitor a Linux laptop from your phone: check system stats, run predefined
commands, browse/manage files, install/remove packages, control media and
volume, manage services, and more — all over Tailscale, authenticated with a
token generated on first run.

This repo has two halves:
- **`prime-daemon/`** — the Python (FastAPI) server that runs on the laptop
- **`prime_app/`** — the Flutter Android app that talks to it

---

## 1. Requirements

Before you start, make sure you have:

- **Linux laptop** running an Arch-based distro with `pacman` (this was built
  and tested on EndeavourOS + Hyprland; other Arch-based setups will likely
  work but aren't guaranteed)
- **`systemd --user`** available (standard on most modern distros)
- **Python 3.10+**
- **A [Tailscale](https://tailscale.com) account** — the daemon binds to your
  Tailscale IP so your phone can reach it without exposing anything to the
  open internet
- **Android phone** with Developer Options + USB debugging enabled, if you
  want to build/install the app yourself (see [Part 3](#3-connecting-the-android-app))
- Root/sudo access on the laptop (setup needs it a few times, see below)

You do **not** need to pre-install Tailscale, `paru`, Flutter, or the Android
SDK — `setup.sh` installs anything missing.

---

## 2. Setting up the daemon

### Clone the repo

```bash
git clone https://github.com/scezian/Prime.git ~/Projects/prime
cd ~/Projects/prime/prime-daemon
```

> You can technically clone this anywhere — `setup.sh` figures out its own
> location and doesn't assume a fixed path. `~/Projects/prime` is just a
> sane default.

### Run setup

```bash
./setup.sh
```

This one script does everything. Specifically, in order, it:

1. **Authenticates sudo up front** — you'll be prompted for your password
   once at the very start, before anything else runs.
2. **Installs & connects Tailscale**, if not already set up. If you're not
   logged into a tailnet yet, it'll open a login flow — follow the URL it
   prints, log in, then the script continues automatically.
3. **Installs `paru`** (AUR helper), if missing.
4. **Sets up a scoped, passwordless `sudo` rule for `pacman` only** — this is
   what lets the app install/remove packages from your phone without you
   typing your password every time. It does *not* grant broader sudo access.
5. **Enables "lingering"** for your user account, so the daemon can start at
   boot even before you log in graphically.
6. **Opens port 8420/tcp on the `trusted` firewalld zone** (only for the
   Tailscale interface) — skipped with a warning if you're not using
   firewalld, in which case you'll need to open the port yourself.
7. **Installs CLI tools the daemon depends on**: `brightnessctl`,
   `playerctl`, `pamixer`, `grim`, `lm_sensors`, `hyprlock`, `wtype`,
   `mpv-mpris`, `bluez-utils`, `networkmanager`, `git`.
8. **Creates a Python virtualenv** and installs daemon dependencies.
9. **Installs and starts the `prime-daemon` systemd user service**, enabled
   to auto-start on boot.
10. **Installs Flutter, Java 17, and the Android SDK** (cmdline-tools,
    platform-tools, build-tools) if they're not already present, and adds the
    required environment variables to your shell's rc file (works with zsh,
    bash, or falls back to `.profile`).
11. **Installs any missing Flutter package dependencies** for `prime_app`.
12. **Sets up `wayvnc`** for screen mirroring, with a self-signed TLS cert and
    a randomly generated password (desktop client) plus a second,
    Tailscale-only config for the mobile app (no extra password layer, since
    Tailscale itself is the auth boundary there).

The script is **idempotent** — safe to re-run any time (after a git pull, to
pick up new dependencies, to recover from a partial failure, etc.). It skips
anything already correctly set up.

### Get your auth token

Once setup finishes, it prints your token directly, and it's also saved to:

```
~/.config/prime/token
```

You'll need this in the app in a minute — copy it somewhere safe, or just
remember it's saved to that file.

### Verify the daemon is running

```bash
systemctl --user status prime-daemon.service
journalctl --user -u prime-daemon.service -f
```

Then test it manually before wiring up the phone:

```bash
# Get your Tailscale IP
tailscale ip -4

# Unauthenticated health check
curl http://<tailscale-ip>:8420/health

# Authenticated status check
curl http://<tailscale-ip>:8420/status \
  -H "X-Auth-Token: <token-from-~/.config/prime/token>"
```

If both return sensible JSON, the daemon side is done.

---

## 3. Connecting the Android app

### Option A — build and install via ADB (development)

```bash
cd ~/Projects/prime/prime_app

# Find your phone's IP (on the phone, or via your router)
adb connect <phone-ip>:<port>   # port shown in phone's wireless debugging screen
flutter devices                  # confirm the phone shows up
flutter run -d <device-id>       # explicit -d avoids it defaulting to Linux desktop
```

> Prime's ADB connection uses your **local Wi-Fi**, not Tailscale — Tailscale
> is only used for the daemon<->app runtime traffic, not for `flutter run`/ADB
> during development.

### Option B — build a release APK and sideload it

```bash
cd ~/Projects/prime/prime_app
flutter build apk --release
# APK lands in build/app/outputs/flutter-apk/app-release.apk
# transfer it to the phone and install (allow "unknown sources" if prompted)
```

### First launch

On first open, the app will ask for:
- **Daemon host** — your laptop's Tailscale IP (from `tailscale ip -4`)
- **Auth token** — from `~/.config/prime/token`

Both are stored locally on the phone (`shared_preferences`), so you only
enter them once.

---

## 4. Configuration

Daemon settings live in `prime-daemon/app/config.py`:

| Setting | Default | What it does |
|---|---|---|
| `ALLOWLISTED_ROOTS` | `~/Projects`, `~/Downloads`, `~/.config` | Directories the file browser is permitted to touch. The daemon refuses to read/write/delete anything outside these. |
| `SERVICES_TO_CHECK` | `[]` (empty) | Which systemd services show up in the app's Services screen. Add your own, e.g. `["hyprpanel.service"]`, or manage this list at runtime via `POST /services`. |
| `BIND_PORT` | `8420` | Port the daemon listens on. |

The bind **host** is *not* set here — it's resolved automatically at every
startup from your current Tailscale IP (see `run.sh`), so it survives
reconnects and IP changes without any manual config.

---

## 5. Troubleshooting

**`setup.sh` fails at the sudo prompt / "pam_faillock" error**
You were likely locked out from a previous failed sudo attempt. Wait ~10
minutes and re-run, or check status with `faillock --user $USER`.

**Daemon won't start / app can't connect**
```bash
journalctl --user -u prime-daemon.service -n 50
tailscale status          # confirm you're connected to your tailnet
tailscale ip -4           # confirm this matches what's in the app's settings
```

**`flutter run` opens on the laptop instead of the phone**
Make sure you passed `-d <device-id>` explicitly — without it, Flutter can
default to the Linux desktop target if one's available.

**Package install/uninstall from the app fails**
Check the scoped sudoers rule installed correctly:
```bash
sudo test -f /etc/sudoers.d/prime-pacman && echo "present"
sudo -n pacman --version   # should succeed with no password prompt
```

**Firewall blocking connections and you're not using firewalld**
Open port 8420/tcp manually for your firewall of choice, scoped to your
Tailscale interface if possible.

---

## 6. Endpoints reference

All endpoints except `/health` require an `X-Auth-Token` header.

| Area | Endpoints |
|---|---|
| Core | `GET /health`, `GET /status`, `GET /commands`, `POST /commands/{id}/run` |
| Power | `GET /power/lock-status`, `POST /power/unlock` |
| Services | `GET /services`, `POST /services/{name}/restart` |
| Processes | `GET /processes`, `POST /processes/{pid}/kill` |
| Files | `GET /fs/list`, `GET /fs/preview`, `GET /fs/download`, `POST /fs/upload`, `POST /fs/delete`, `POST /fs/move`, `POST /fs/rename` |
| Packages | `GET /packages/installed`, `GET /packages/search`, `POST /packages/install`, `POST /packages/uninstall`, `GET /packages/jobs/{id}` |
| Media | `GET /media/now-playing`, `GET /media/art`, `POST /media/play-pause`, `POST /media/next`, `POST /media/previous` |
| Audio | `GET /audio/volume`, `POST /audio/volume`, `POST /audio/mute-toggle` |
| Display | `GET /display/brightness`, `POST /display/brightness`, `GET /keyboard/backlight`, `POST /keyboard/backlight` |
| Network | `GET /network/wifi`, `POST /network/wifi/connect`, `GET /network/wifi/power`, `POST /network/wifi/power`, `POST /network/wifi/disconnect`, `GET /network/bluetooth`, `POST /network/bluetooth/connect`, `GET /network/bluetooth/power`, `POST /network/bluetooth/power`, `POST /network/bluetooth/disconnect` |
| Screenshot | `GET /commands/screenshot/image` |

---

## 7. Project layout

```
prime/
├── prime-daemon/       # Python FastAPI server (this README's subject)
│   ├── app/            # daemon source
│   ├── setup.sh         # one-shot installer, safe to re-run
│   ├── run.sh            # launches the daemon bound to current Tailscale IP
│   └── *.service          # systemd user unit files
└── prime_app/           # Flutter Android app
    └── lib/
```
