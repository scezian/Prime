"""
Network control — WiFi (via nmcli/NetworkManager) and Bluetooth (via bluetoothctl).

Deliberately scoped down: this only lists and connects to networks/devices
that are already known to the system (a saved NetworkManager connection
profile, or an already-paired Bluetooth device). No passwords or pairing
flows are ever handled here — that keeps credentials off the API entirely
and keeps this module simple. New networks/devices must be set up on the
laptop itself first.
"""
import subprocess


class NetworkError(Exception):
    pass


def _run(cmd: list[str], timeout: int = 10) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        raise NetworkError(f"{cmd[0]} not found on this system")
    except subprocess.TimeoutExpired:
        raise NetworkError(f"{cmd[0]} timed out")


# ---- WiFi ----

def _known_wifi_names() -> set[str]:
    """Saved NetworkManager connection profiles of type 802-11-wireless.
    Profile NAME is used as the SSID match — this holds as long as profiles
    were created the normal way (nmcli/GUI default to naming the profile
    after the SSID)."""
    proc = _run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"])
    if proc.returncode != 0:
        raise NetworkError(proc.stderr.strip() or "failed to list saved connections")

    names = set()
    for line in proc.stdout.strip().splitlines():
        if not line:
            continue
        # nmcli escapes literal ':' in fields as '\:' — connection names can
        # contain colons, so split from the right on the (unescaped) type field.
        name, _, conn_type = line.rpartition(":")
        if conn_type == "802-11-wireless":
            names.add(name.replace("\\:", ":"))
    return names


def list_wifi_networks() -> dict:
    """Known networks currently visible over the air, with signal + connected state."""
    known = _known_wifi_names()

    proc = _run(["nmcli", "-t", "-f", "SSID,SIGNAL,IN-USE", "dev", "wifi", "list"], timeout=15)
    if proc.returncode != 0:
        raise NetworkError(proc.stderr.strip() or "failed to scan for wifi networks")

    best_by_ssid: dict[str, dict] = {}
    for line in proc.stdout.strip().splitlines():
        if not line:
            continue
        parts = line.rsplit(":", 2)
        if len(parts) != 3:
            continue
        ssid, signal, in_use = parts
        ssid = ssid.replace("\\:", ":")
        if not ssid or ssid not in known:
            continue  # only ever surface already-known networks
        try:
            signal_val = int(signal)
        except ValueError:
            signal_val = 0
        existing = best_by_ssid.get(ssid)
        if existing is None or signal_val > existing["signal"]:
            best_by_ssid[ssid] = {
                "ssid": ssid,
                "signal": signal_val,
                "connected": in_use.strip() == "*",
            }

    networks = sorted(best_by_ssid.values(), key=lambda n: -n["signal"])
    return {"networks": networks}


def connect_wifi(ssid: str) -> dict:
    if ssid not in _known_wifi_names():
        raise NetworkError(f'"{ssid}" is not a known network on this machine')
    proc = _run(["nmcli", "connection", "up", "id", ssid], timeout=20)
    if proc.returncode != 0:
        raise NetworkError(proc.stderr.strip() or f"failed to connect to {ssid}")
    return {"connected": True, "ssid": ssid}


# ---- Bluetooth ----

def list_bluetooth_devices() -> dict:
    proc = _run(["bluetoothctl", "devices", "Paired"])
    if proc.returncode != 0:
        raise NetworkError(proc.stderr.strip() or "failed to list paired devices")

    devices = []
    for line in proc.stdout.strip().splitlines():
        # "Device AA:BB:CC:DD:EE:FF Device Name Here"
        parts = line.split(" ", 2)
        if len(parts) != 3 or parts[0] != "Device":
            continue
        mac, name = parts[1], parts[2]

        info_proc = _run(["bluetoothctl", "info", mac])
        connected = info_proc.returncode == 0 and "Connected: yes" in info_proc.stdout

        devices.append({"mac": mac, "name": name, "connected": connected})

    return {"devices": devices}


def connect_bluetooth(mac: str) -> dict:
    paired = {d["mac"] for d in list_bluetooth_devices()["devices"]}
    if mac not in paired:
        raise NetworkError(f"{mac} is not a paired device on this machine")

    proc = _run(["bluetoothctl", "connect", mac], timeout=15)
    combined_output = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode != 0 or "Failed" in combined_output:
        raise NetworkError(combined_output.strip() or f"failed to connect to {mac}")
    return {"connected": True, "mac": mac}


# ---- Radio power / disconnect ----

def get_wifi_radio() -> dict:
    proc = _run(["nmcli", "radio", "wifi"])
    if proc.returncode != 0:
        raise NetworkError(proc.stderr.strip() or "failed to get wifi radio status")
    return {"enabled": proc.stdout.strip() == "enabled"}


def set_wifi_radio(enabled: bool) -> dict:
    proc = _run(["nmcli", "radio", "wifi", "on" if enabled else "off"])
    if proc.returncode != 0:
        raise NetworkError(proc.stderr.strip() or "failed to set wifi radio")
    return {"enabled": enabled}


def _active_wifi_device() -> str | None:
    proc = _run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "dev", "status"])
    if proc.returncode != 0:
        return None
    for line in proc.stdout.strip().splitlines():
        parts = line.split(":")
        if len(parts) != 3:
            continue
        device, dtype, state = parts
        if dtype == "wifi" and state == "connected":
            return device
    return None


def disconnect_wifi() -> dict:
    device = _active_wifi_device()
    if not device:
        return {"disconnected": False, "note": "no active wifi connection"}
    proc = _run(["nmcli", "device", "disconnect", device], timeout=15)
    if proc.returncode != 0:
        raise NetworkError(proc.stderr.strip() or "failed to disconnect wifi")
    return {"disconnected": True}


def get_bluetooth_radio() -> dict:
    proc = _run(["bluetoothctl", "show"])
    if proc.returncode != 0:
        raise NetworkError(proc.stderr.strip() or "failed to get bluetooth power status")
    return {"enabled": "Powered: yes" in proc.stdout}


def set_bluetooth_radio(enabled: bool) -> dict:
    proc = _run(["bluetoothctl", "power", "on" if enabled else "off"], timeout=15)
    combined = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode != 0 or "Failed" in combined:
        raise NetworkError(combined.strip() or "failed to set bluetooth power")
    return {"enabled": enabled}


def disconnect_bluetooth(mac: str) -> dict:
    proc = _run(["bluetoothctl", "disconnect", mac], timeout=15)
    combined = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode != 0 or "Failed" in combined:
        raise NetworkError(combined.strip() or f"failed to disconnect {mac}")
    return {"disconnected": True, "mac": mac}
