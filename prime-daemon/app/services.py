"""
Dynamic systemd --user service management.

Which services are exposed is controlled entirely by SERVICES_TO_CHECK in
config.py — add a new project's service name there and it shows up in the
app automatically, with status + restart, no new daemon code needed.
"""
import subprocess

from app.config import SERVICES_TO_CHECK


class ServiceError(Exception):
    pass


def list_services() -> dict:
    services = []
    for name in SERVICES_TO_CHECK:
        proc = subprocess.run(
            ["systemctl", "--user", "is-active", name],
            capture_output=True, text=True, timeout=10,
        )
        services.append({
            "name": name,
            "status": (proc.stdout.strip() or proc.stderr.strip()),
        })
    return {"services": services}


def restart_service(name: str) -> dict:
    if name not in SERVICES_TO_CHECK:
        raise ServiceError(f"Unknown or unlisted service: {name}")

    if name == "prime-daemon.service":
        # Restarting ourselves drops the connection before we can respond
        # normally — fire and forget, same pattern as the reboot command.
        subprocess.Popen(["systemctl", "--user", "restart", name])
        return {"started": True}

    proc = subprocess.run(
        ["systemctl", "--user", "restart", name],
        capture_output=True, text=True, timeout=30,
    )
    if proc.returncode != 0:
        raise ServiceError(proc.stderr.strip() or f"failed to restart {name}")
    return {"restarted": True}
