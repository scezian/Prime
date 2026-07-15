#!/usr/bin/env python3
"""
Patches prime-daemon's /status endpoint (adds cpu/memory/network) and
prime_app's theme (adds stat accent colors) for the Home screen redesign.

Run locally:
    python3 patch_prime_backend.py

If your layout differs from ~/Projects/prime/..., edit the two paths below.
"""
from pathlib import Path

DAEMON_MAIN = Path.home() / "Projects/prime/prime-daemon/app/main.py"
THEME_FILE = Path.home() / "Projects/prime/prime_app/lib/theme/prime_theme.dart"


def patch(path: Path, old: str, new: str, label: str, already_done_marker: str) -> bool:
    if not path.exists():
        print(f"[SKIP] {label}: file not found at {path}")
        return False
    text = path.read_text()
    if already_done_marker in text:
        print(f"[SKIP] {label}: already applied.")
        return False
    count = text.count(old)
    if count != 1:
        print(f"[SKIP] {label}: expected 1 anchor match, found {count}. No changes made.")
        return False
    path.write_text(text.replace(old, new))
    print(f"[OK] {label} patched.")
    return True


def main():
    # 1. daemon: import psutil, prime its sample window, init net-delta state
    patch(
        DAEMON_MAIN,
        old=(
            'from app import filesystem, packages, media, services\n'
            '\n'
            'app = FastAPI(title="Prime Daemon")\n'
            '\n'
            '_BOOT_TIME = time.time()\n'
        ),
        new=(
            'from app import filesystem, packages, media, services\n'
            'import psutil\n'
            '\n'
            'app = FastAPI(title="Prime Daemon")\n'
            '\n'
            '_BOOT_TIME = time.time()\n'
            'psutil.cpu_percent(interval=None)  # prime the internal sample window\n'
            '_prev_net = psutil.net_io_counters()\n'
            '_prev_net_time = time.time()\n'
        ),
        label="main.py imports/state",
        already_done_marker="import psutil",
    )

    # 2. daemon: extend status() to return cpu/memory/network alongside disk
    patch(
        DAEMON_MAIN,
        old=(
            '@app.get("/status", dependencies=[Depends(verify_token)])\n'
            'def status():\n'
            '    disk = shutil.disk_usage("/")\n'
            '    uptime_seconds = int(time.time() - _BOOT_TIME)\n'
            '\n'
            '    return {\n'
            '        "hostname": socket.gethostname(),\n'
            '        "daemon_uptime": str(timedelta(seconds=uptime_seconds)),\n'
            '        "disk": {\n'
        ),
        new=(
            '@app.get("/status", dependencies=[Depends(verify_token)])\n'
            'def status():\n'
            '    global _prev_net, _prev_net_time\n\n'
            '    disk = shutil.disk_usage("/")\n'
            '    uptime_seconds = int(time.time() - _BOOT_TIME)\n\n'
            '    cpu_percent = psutil.cpu_percent(interval=None)\n'
            '    mem = psutil.virtual_memory()\n\n'
            '    now = time.time()\n'
            '    current_net = psutil.net_io_counters()\n'
            '    dt = max(now - _prev_net_time, 0.001)\n'
            '    download_kbps = (current_net.bytes_recv - _prev_net.bytes_recv) / dt / 1024\n'
            '    upload_kbps = (current_net.bytes_sent - _prev_net.bytes_sent) / dt / 1024\n'
            '    _prev_net = current_net\n'
            '    _prev_net_time = now\n\n'
            '    return {\n'
            '        "hostname": socket.gethostname(),\n'
            '        "daemon_uptime": str(timedelta(seconds=uptime_seconds)),\n'
            '        "cpu_percent": round(cpu_percent, 1),\n'
            '        "memory": {\n'
            '            "used_gb": round(mem.used / 1e9, 1),\n'
            '            "total_gb": round(mem.total / 1e9, 1),\n'
            '            "percent": round(mem.percent, 1),\n'
            '        },\n'
            '        "network": {\n'
            '            "download_kbps": round(download_kbps, 1),\n'
            '            "upload_kbps": round(upload_kbps, 1),\n'
            '        },\n'
            '        "disk": {\n'
        ),
        label="main.py status() body",
        already_done_marker="global _prev_net, _prev_net_time",
    )

    # 3. theme: add stat/action accent colors used by the new Home screen
    patch(
        THEME_FILE,
        old='  static const warning = Color(0xFFF59E0B); // amber - dirty/AUR/caution',
        new=(
            '  static const warning = Color(0xFFF59E0B); // amber - dirty/AUR/caution\n'
            '  static const cpuAccent = Color(0xFF38BDF8); // cyan - cpu stat\n'
            '  static const memAccent = Color(0xFFF472B6); // pink - memory stat\n'
            '  static const netAccent = Color(0xFF818CF8); // violet - network stat\n'
            '  static const filesAccent = Color(0xFF4F8EF7); // blue - files action\n'
            '  static const packagesAccent = Color(0xFFC084FC); // purple - packages action'
        ),
        label="prime_theme.dart accent colors",
        already_done_marker="cpuAccent",
    )


if __name__ == "__main__":
    main()
