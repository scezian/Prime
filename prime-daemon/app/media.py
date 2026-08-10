"""
Media playback (via playerctl, MPRIS-based) and volume control (via pamixer).
Both tools are already present on scez-2.
"""
import json
import subprocess


class ControlError(Exception):
    pass


def _run(cmd: list[str], timeout: int = 8) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        raise ControlError(f"{cmd[0]} not found on this system")
    except subprocess.TimeoutExpired:
        raise ControlError(f"{cmd[0]} timed out")


# ---- Media playback ----

_METADATA_FORMAT = "{{title}}\t{{artist}}\t{{album}}\t{{position}}\t{{mpris:length}}\t{{mpris:artUrl}}"


def list_players() -> list[str]:
    """Names of all currently running MPRIS players (e.g. 'spotify',
    'chromium.instance_1_2381'), in playerctl's own priority order."""
    proc = _run(["playerctl", "-l"])
    if proc.returncode != 0 or not proc.stdout.strip():
        return []
    return [line.strip() for line in proc.stdout.strip("\n").split("\n") if line.strip()]


def _source_label(player: str) -> str:
    """Best-effort human-readable label derived from a playerctl player name."""
    base = player.split(".")[0]
    return base.replace("_", " ").replace("-", " ").title()


def now_playing(player: str | None = None) -> dict:
    cmd_status = ["playerctl"]
    if player:
        cmd_status += ["-p", player]
    cmd_status.append("status")

    status_proc = _run(cmd_status)
    if status_proc.returncode != 0:
        # No player running / no MPRIS source active.
        return {"active": False}

    status = status_proc.stdout.strip()

    cmd_meta = ["playerctl"]
    if player:
        cmd_meta += ["-p", player]
    cmd_meta += ["metadata", "--format", _METADATA_FORMAT]

    meta_proc = _run(cmd_meta)
    title, artist, album, position_us, length_us, art_url = "", "", "", "0", "0", ""
    if meta_proc.returncode == 0 and meta_proc.stdout.strip():
        parts = meta_proc.stdout.strip("\n").split("\t")
        parts += [""] * (6 - len(parts))
        title, artist, album, position_us, length_us, art_url = parts[:6]

    def to_seconds(us: str) -> int:
        try:
            return int(us) // 1_000_000
        except ValueError:
            return 0

    return {
        "active": True,
        "player": player,
        "source": _source_label(player) if player else None,
        "status": status,  # "Playing" | "Paused" | "Stopped"
        "title": title,
        "artist": artist,
        "album": album,
        "position_seconds": to_seconds(position_us),
        "duration_seconds": to_seconds(length_us),
        "art_url": art_url,
    }


def list_now_playing() -> list[dict]:
    """now_playing() for every currently active MPRIS player, skipping any
    that report inactive between the -l listing and the per-player query."""
    results = []
    for player in list_players():
        info = now_playing(player)
        if info.get("active"):
            results.append(info)
    return results


def play_pause(player: str | None = None) -> dict:
    cmd = ["playerctl"]
    if player:
        cmd += ["-p", player]
    cmd.append("play-pause")
    proc = _run(cmd)
    return {"ok": proc.returncode == 0}


def next_track(player: str | None = None) -> dict:
    cmd = ["playerctl"]
    if player:
        cmd += ["-p", player]
    cmd.append("next")
    proc = _run(cmd)
    return {"ok": proc.returncode == 0}


def previous_track(player: str | None = None) -> dict:
    cmd = ["playerctl"]
    if player:
        cmd += ["-p", player]
    cmd.append("previous")
    proc = _run(cmd)
    return {"ok": proc.returncode == 0}


# ---- Album art (local file:// URIs only — http(s) URLs are loaded directly by the app) ----

def resolve_art_path(file_url: str) -> str:
    """Convert a file:// URI from MPRIS metadata into a validated local path.
    Restricted to the user's home directory as a safety boundary, even though
    the path originated from the player itself rather than user input."""
    from pathlib import Path
    from urllib.parse import unquote, urlparse

    parsed = urlparse(file_url)
    if parsed.scheme != "file":
        raise ControlError("not a local file:// URI")

    path = Path(unquote(parsed.path)).resolve()
    home = Path.home().resolve()
    try:
        path.relative_to(home)
    except ValueError:
        raise ControlError("art path outside home directory")

    if not path.exists() or not path.is_file():
        raise ControlError("art file not found")

    return str(path)


# ---- Brightness ----

def get_brightness() -> dict:
    current_proc = _run(["brightnessctl", "get"])
    max_proc = _run(["brightnessctl", "max"])

    try:
        current = int(current_proc.stdout.strip())
        maximum = int(max_proc.stdout.strip())
        percent = round(current / maximum * 100) if maximum else 0
    except ValueError:
        percent = 0

    return {"percent": percent}


def set_brightness(percent: int) -> dict:
    percent = max(1, min(100, percent))  # brightnessctl treats 0% as "off" on some backlights
    proc = _run(["brightnessctl", "set", f"{percent}%"])
    if proc.returncode != 0:
        raise ControlError(proc.stderr.strip() or "failed to set brightness")
    return get_brightness()


# ---- Keyboard backlight ----

def get_kbd_backlight() -> dict:
    current_proc = _run(["brightnessctl", "--device=tpacpi::kbd_backlight", "get"])
    max_proc = _run(["brightnessctl", "--device=tpacpi::kbd_backlight", "max"])
    try:
        current = int(current_proc.stdout.strip())
        maximum = int(max_proc.stdout.strip())
        percent = round(current / maximum * 100) if maximum else 0
    except ValueError:
        percent = 0
    return {"percent": percent}


def set_kbd_backlight(percent: int) -> dict:
    max_proc = _run(["brightnessctl", "--device=tpacpi::kbd_backlight", "max"])
    try:
        maximum = int(max_proc.stdout.strip())
    except ValueError:
        maximum = 2
    # Only a few discrete steps exist (e.g. off/low/high) — snap to the nearest one.
    raw = round(max(0, min(100, percent)) / 100 * maximum)
    proc = _run(["brightnessctl", "--device=tpacpi::kbd_backlight", "set", str(raw)])
    if proc.returncode != 0:
        raise ControlError(proc.stderr.strip() or "failed to set keyboard backlight")
    return get_kbd_backlight()


# ---- Volume ----

def get_volume() -> dict:
    vol_proc = _run(["pamixer", "--get-volume"])
    mute_proc = _run(["pamixer", "--get-mute"])

    try:
        volume = int(vol_proc.stdout.strip())
    except ValueError:
        volume = 0

    muted = mute_proc.stdout.strip() == "true"

    return {"volume": volume, "muted": muted}


def set_volume(level: int) -> dict:
    level = max(0, min(100, level))
    proc = _run(["pamixer", "--set-volume", str(level)])
    if proc.returncode != 0:
        raise ControlError(proc.stderr.strip() or "failed to set volume")
    return get_volume()


def toggle_mute() -> dict:
    proc = _run(["pamixer", "--toggle-mute"])
    if proc.returncode != 0:
        raise ControlError(proc.stderr.strip() or "failed to toggle mute")
    return get_volume()


# ---- Per-app audio mixer ----

def list_audio_apps() -> list[dict]:
    proc = _run(["pactl", "-f", "json", "list", "sink-inputs"])
    if proc.returncode != 0:
        raise ControlError(proc.stderr.strip() or "failed to list audio apps")
    try:
        raw = json.loads(proc.stdout)
    except (json.JSONDecodeError, ValueError):
        return []

    apps = []
    for item in raw:
        props = item.get("properties", {})
        name = props.get("application.name") or props.get("node.name") or "Unknown"
        subtitle = props.get("media.name", "")
        volume_map = item.get("volume", {})
        percent = 0
        if volume_map:
            first = next(iter(volume_map.values()))
            try:
                percent = int(str(first.get("value_percent", "0%")).rstrip("%"))
            except ValueError:
                percent = 0
        apps.append({
            "index": item.get("index"),
            "name": name,
            "subtitle": subtitle,
            "volume": percent,
            "muted": bool(item.get("mute", False)),
        })
    return apps


def set_app_volume(index: int, level: int) -> dict:
    level = max(0, min(100, level))
    proc = _run(["pactl", "set-sink-input-volume", str(index), f"{level}%"])
    if proc.returncode != 0:
        raise ControlError(proc.stderr.strip() or "failed to set app volume")
    return {"index": index, "volume": level}


def toggle_app_mute(index: int) -> dict:
    proc = _run(["pactl", "set-sink-input-mute", str(index), "toggle"])
    if proc.returncode != 0:
        raise ControlError(proc.stderr.strip() or "failed to toggle app mute")
    for app in list_audio_apps():
        if app["index"] == index:
            return app
    return {"index": index}
