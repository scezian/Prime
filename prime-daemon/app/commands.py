"""
Predefined commands — the fixed button set in the Prime app.

Each command is either:
- "sync": runs and returns output immediately (e.g. git status scan)
- "fire": runs in the background and returns immediately without
  waiting for completion (needed for reboot/suspend, since the
  daemon itself may get killed before it can respond otherwise)
"""
import subprocess
import os
from pathlib import Path

PROJECTS_DIR = Path.home() / "Projects"

MUSIC_DIR = Path.home() / "Music"
NOCTURNE_TRACK = MUSIC_DIR / "Leave It All To Sink Into Heavy Rain And Thunderstorms - Relax And Sleep In Cozy Car.m4a"


def scan_git_status() -> dict:
    """Walk ~/Projects, report uncommitted changes per repo."""
    if not PROJECTS_DIR.exists():
        return {"repos": [], "note": f"{PROJECTS_DIR} does not exist"}

    results = []
    for entry in sorted(PROJECTS_DIR.iterdir()):
        git_dir = entry / ".git"
        if not entry.is_dir() or not git_dir.exists():
            continue

        proc = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=entry,
            capture_output=True,
            text=True,
            timeout=15,
        )
        changed_files = [l for l in proc.stdout.splitlines() if l.strip()]

        branch_proc = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=entry,
            capture_output=True,
            text=True,
            timeout=10,
        )
        branch = branch_proc.stdout.strip() or "unknown"

        results.append({
            "repo": entry.name,
            "branch": branch,
            "dirty": len(changed_files) > 0,
            "changed_files": len(changed_files),
        })

    return {"repos": results}


def run_sync(cmd: list[str], timeout: int = 20) -> dict:
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return {
        "returncode": proc.returncode,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
    }


def _find_wayland_display() -> str | None:
    """Locate the live Wayland socket under XDG_RUNTIME_DIR.

    The daemon may start via systemd lingering before (or without ever)
    inheriting a graphical session's environment, so WAYLAND_DISPLAY can be
    missing even while Hyprland is running. Looking the socket up at call
    time (rather than trusting inherited env) keeps this correct regardless
    of when the daemon started or whether Hyprland has restarted since.
    """
    import re
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    try:
        for entry in sorted(Path(runtime_dir).glob("wayland-*")):
            # Only true display sockets (e.g. "wayland-1"), not related
            # files other tools create alongside it (e.g. "wayland-1.lock",
            # "wayland-1-awww-daemon.sock").
            if re.fullmatch(r"wayland-\d+", entry.name):
                return entry.name
    except OSError:
        pass
    return None


def _wayland_env() -> dict:
    """A copy of the current environment with WAYLAND_DISPLAY corrected/added
    if a live socket can be found. Falls back to the inherited environment
    unchanged if no socket is found (the command will then fail with its own
    clear error rather than silently using a stale value)."""
    env = os.environ.copy()
    display = _find_wayland_display()
    if display:
        env["WAYLAND_DISPLAY"] = display
    return env


def run_fire(cmd: list[str], env: dict | None = None) -> dict:
    """Fire-and-forget — for commands that may kill the daemon (reboot/suspend)."""
    subprocess.Popen(cmd, env=env)
    return {"started": True}


TRASH_DIR = Path.home() / ".prime-trash"
SCREENSHOT_CACHE = Path("/tmp/prime-screenshot.png")


def get_network_status() -> dict:
    ts = run_sync(["tailscale", "status"], timeout=10)
    ip = run_sync(["hostname", "-I"], timeout=5)
    return {
        "tailscale_status": (ts["stdout"] or ts["stderr"]).strip(),
        "local_ip": ip["stdout"].strip(),
    }




def clear_trash() -> dict:
    import shutil as _shutil
    if not TRASH_DIR.exists():
        return {"cleared": 0}
    count = 0
    for item in TRASH_DIR.iterdir():
        if item.is_dir():
            _shutil.rmtree(item, ignore_errors=True)
        else:
            item.unlink(missing_ok=True)
        count += 1
    return {"cleared": count}


def is_screen_locked() -> bool:
    """True if a hyprlock process is currently running."""
    proc = subprocess.run(["pgrep", "-x", "hyprlock"], capture_output=True, text=True, timeout=5)
    return proc.returncode == 0


def unlock_screen(password: str) -> dict:
    """Type the password into the running hyprlock prompt and press Enter,
    letting hyprlock's own PAM check validate it. This is not a bypass —
    it's the same input path a physical keystroke takes."""
    import time

    if not is_screen_locked():
        return {"unlocked": False, "note": "screen was not locked"}

    env = _wayland_env()
    try:
        subprocess.run(["wtype", password], env=env, timeout=10, check=True)
        subprocess.run(["wtype", "-k", "Return"], env=env, timeout=5, check=True)
    except FileNotFoundError:
        raise RuntimeError("wtype not found — install it (paru -S wtype) to enable remote unlock")
    except subprocess.CalledProcessError:
        raise RuntimeError("failed to send password to the lock screen")

    time.sleep(1.2)  # give hyprlock a moment to validate and exit
    return {"unlocked": not is_screen_locked()}


def take_screenshot() -> dict:
    try:
        proc = subprocess.run(
            ["grim", str(SCREENSHOT_CACHE)],
            capture_output=True, text=True, timeout=15, env=_wayland_env(),
        )
    except FileNotFoundError:
        raise RuntimeError("grim not found on this system")
    except subprocess.TimeoutExpired:
        raise RuntimeError("grim timed out")
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "grim failed")
    return {"path": str(SCREENSHOT_CACHE)}


def run_nocturne() -> dict:
    """Play the sleep-audio track, dim the screen to minimum, and lock."""
    env = _wayland_env()
    result = {"mpv": False, "brightness": False, "locked": False}

    if NOCTURNE_TRACK.exists():
        subprocess.Popen(
            ["mpv", "--script=/usr/lib/mpv-mpris/mpris.so", str(NOCTURNE_TRACK)],
            env=env,
        )
        result["mpv"] = True

    try:
        subprocess.run(["brightnessctl", "set", "1"], capture_output=True, text=True, timeout=5)
        result["brightness"] = True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    subprocess.Popen(["hyprlock"], env=env)
    result["locked"] = True

    return result


COMMANDS = {
    "git-status": {
        "name": "Git Status (all repos)",
        "description": "Scan ~/Projects for uncommitted changes",
        "category": "info",
        "needs_confirm": False,
        "run": lambda: scan_git_status(),
    },
    "uptime": {
        "name": "Uptime",
        "description": "How long the system has been running",
        "category": "info",
        "needs_confirm": False,
        "run": lambda: run_sync(["uptime", "-p"]),
    },
    "disk-usage": {
        "name": "Disk Usage",
        "description": "Full disk breakdown across mounts",
        "category": "info",
        "needs_confirm": False,
        "run": lambda: run_sync(["df", "-h"]),
    },
    "memory-usage": {
        "name": "Memory Usage",
        "description": "RAM and swap usage",
        "category": "info",
        "needs_confirm": False,
        "run": lambda: run_sync(["free", "-h"]),
    },
    "cpu-temp": {
        "name": "CPU Temperature",
        "description": "Sensor readings",
        "category": "info",
        "needs_confirm": False,
        "run": lambda: run_sync(["sensors"]),
    },
    "network-status": {
        "name": "Network Status",
        "description": "Tailscale status and local IP",
        "category": "info",
        "needs_confirm": False,
        "run": lambda: get_network_status(),
    },
    "updates-available": {
        "name": "Updates Available",
        "description": "Pending package updates (paru -Qu)",
        "category": "info",
        "needs_confirm": False,
        "run": lambda: run_sync(["paru", "-Qu"], timeout=30),
    },
    "journal-errors": {
        "name": "Recent Errors",
        "description": "Last 20 error-level journal entries",
        "category": "info",
        "needs_confirm": False,
        "run": lambda: run_sync(["journalctl", "-p", "err", "-n", "20", "--no-pager"], timeout=15),
    },
    "lock-screen": {
        "name": "Lock Screen",
        "description": "Lock the laptop screen",
        "category": "power",
        "needs_confirm": False,
        "run": lambda: run_fire(["hyprlock"], env=_wayland_env()),
    },
    "suspend": {
        "name": "Suspend",
        "description": "Suspend the laptop to RAM",
        "category": "power",
        "needs_confirm": True,
        "run": lambda: run_fire(["systemctl", "suspend"]),
    },
    "logout": {
        "name": "Logout",
        "description": "End the Hyprland session",
        "category": "power",
        "needs_confirm": True,
        "run": lambda: run_fire(["bash", str(Path.home() / ".config/hypr/scripts/exit.sh")]),
    },
    "reboot": {
        "name": "Reboot",
        "description": "Reboot the laptop",
        "category": "power",
        "needs_confirm": True,
        "run": lambda: run_fire(["systemctl", "reboot"]),
    },
    "shutdown": {
        "name": "Shutdown",
        "description": "Power off the laptop",
        "category": "power",
        "needs_confirm": True,
        "run": lambda: run_fire(["systemctl", "poweroff"]),
    },
    "clear-trash": {
        "name": "Clear Trash",
        "description": "Permanently delete everything in the Prime trash",
        "category": "utility",
        "needs_confirm": True,
        "run": lambda: clear_trash(),
    },
    "screenshot": {
        "name": "Screenshot",
        "description": "Capture the screen and preview it here",
        "category": "utility",
        "needs_confirm": False,
        "run": lambda: take_screenshot(),
    },
    "nocturne": {
        "name": "Nocturne",
        "description": "Play sleep audio, dim to minimum, and lock",
        "category": "utility",
        "needs_confirm": False,
        "run": lambda: run_nocturne(),
    },
}
