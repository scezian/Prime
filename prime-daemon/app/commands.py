"""
Predefined commands — the fixed button set in the Prime app.

Each command is either:
- "sync": runs and returns output immediately (e.g. git status scan)
- "fire": runs in the background and returns immediately without
  waiting for completion (needed for reboot/suspend, since the
  daemon itself may get killed before it can respond otherwise)
"""
import subprocess
from pathlib import Path

PROJECTS_DIR = Path.home() / "Projects"


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


def run_fire(cmd: list[str]) -> dict:
    """Fire-and-forget — for commands that may kill the daemon (reboot/suspend)."""
    subprocess.Popen(cmd)
    return {"started": True}


SERVICES_TO_CHECK = ["prime-daemon.service", "hyprpanel.service"]
TRASH_DIR = Path.home() / ".prime-trash"
SCREENSHOT_CACHE = Path("/tmp/prime-screenshot.png")


def get_network_status() -> dict:
    ts = run_sync(["tailscale", "status"], timeout=10)
    ip = run_sync(["hostname", "-I"], timeout=5)
    return {
        "tailscale_status": (ts["stdout"] or ts["stderr"]).strip(),
        "local_ip": ip["stdout"].strip(),
    }


def get_service_status() -> dict:
    results = []
    for svc in SERVICES_TO_CHECK:
        proc = run_sync(["systemctl", "--user", "is-active", svc], timeout=10)
        results.append({"service": svc, "status": (proc["stdout"] or proc["stderr"]).strip()})
    return {"services": results}


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


def take_screenshot() -> dict:
    proc = run_sync(["grim", str(SCREENSHOT_CACHE)], timeout=15)
    if proc["returncode"] != 0:
        raise RuntimeError(proc["stderr"] or "grim failed")
    return {"path": str(SCREENSHOT_CACHE)}


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
    "service-status": {
        "name": "Service Status",
        "description": "Status of key user services",
        "category": "info",
        "needs_confirm": False,
        "run": lambda: get_service_status(),
    },
    "journal-errors": {
        "name": "Recent Errors",
        "description": "Last 20 error-level journal entries",
        "category": "info",
        "needs_confirm": False,
        "run": lambda: run_sync(["journalctl", "-p", "err", "-n", "20", "--no-pager"], timeout=15),
    },
    "restart-prime-daemon": {
        "name": "Restart Prime Daemon",
        "description": "Restarts this daemon \u2014 connection will drop briefly",
        "category": "service",
        "needs_confirm": True,
        "run": lambda: run_fire(["systemctl", "--user", "restart", "prime-daemon.service"]),
    },
    "restart-hyprpanel": {
        "name": "Restart HyprPanel",
        "description": "Restarts the Hyprland system tray panel",
        "category": "service",
        "needs_confirm": True,
        "run": lambda: run_sync(["systemctl", "--user", "restart", "hyprpanel.service"]),
    },
    "lock-screen": {
        "name": "Lock Screen",
        "description": "Lock the laptop screen",
        "category": "power",
        "needs_confirm": False,
        "run": lambda: run_fire(["hyprlock"]),
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
}
