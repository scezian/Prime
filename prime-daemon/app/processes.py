"""
Active GUI process listing + kill, sourced from Hyprland's own client list
(hyprctl clients -j) rather than raw `ps aux`, since that gives us actual
user-facing windows (Firefox, Spotify, etc.) with clean app names instead
of hundreds of background/system processes.
"""
import json
import os
import signal
import subprocess
import time


class ProcessError(Exception):
    pass


def list_processes() -> dict:
    try:
        proc = subprocess.run(
            ["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=10
        )
    except FileNotFoundError:
        raise ProcessError("hyprctl not found on this system")
    except subprocess.TimeoutExpired:
        raise ProcessError("hyprctl timed out")

    if proc.returncode != 0:
        raise ProcessError(proc.stderr.strip() or "hyprctl clients failed")

    try:
        clients = json.loads(proc.stdout)
    except json.JSONDecodeError:
        raise ProcessError("could not parse hyprctl output")

    seen_pids = set()
    result = []
    for c in clients:
        pid = c.get("pid")
        if not pid or pid in seen_pids:
            continue
        seen_pids.add(pid)
        cls = (c.get("class") or "").strip()
        title = (c.get("title") or "").strip()
        result.append({
            "pid": pid,
            "name": cls or title or f"pid {pid}",
            "title": title,
        })

    result.sort(key=lambda p: p["name"].lower())
    return {"processes": result}


def kill_process(pid: int) -> dict:
    """SIGTERM first (lets the app close cleanly / save state), then
    SIGKILL after a short grace period if it hasn't exited."""
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return {"killed": True, "note": "process was already gone"}
    except PermissionError:
        raise ProcessError("permission denied killing this process")

    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)  # signal 0 = existence check only
        except ProcessLookupError:
            return {"killed": True}
        time.sleep(0.1)

    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        return {"killed": True}
    except PermissionError:
        raise ProcessError("permission denied force-killing this process")

    return {"killed": True, "forced": True}
