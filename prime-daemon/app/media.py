"""
Media playback (via playerctl, MPRIS-based) and volume control (via pamixer).
Both tools are already present on scez-2.
"""
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


def now_playing() -> dict:
    status_proc = _run(["playerctl", "status"])
    if status_proc.returncode != 0:
        # No player running / no MPRIS source active.
        return {"active": False}

    status = status_proc.stdout.strip()

    meta_proc = _run(["playerctl", "metadata", "--format", _METADATA_FORMAT])
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
        "status": status,  # "Playing" | "Paused" | "Stopped"
        "title": title,
        "artist": artist,
        "album": album,
        "position_seconds": to_seconds(position_us),
        "duration_seconds": to_seconds(length_us),
        "art_url": art_url,
    }


def play_pause() -> dict:
    proc = _run(["playerctl", "play-pause"])
    return {"ok": proc.returncode == 0}


def next_track() -> dict:
    proc = _run(["playerctl", "next"])
    return {"ok": proc.returncode == 0}


def previous_track() -> dict:
    proc = _run(["playerctl", "previous"])
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
