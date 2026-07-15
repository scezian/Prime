#!/usr/bin/env python3
"""
Patches for the WiFi/Bluetooth + Shutdown-only-in-Control change:
  1. main.py              — import network module, add 4 routes
  2. commands.py           — add a "shutdown" power command (didn't exist before)
  3. api_client.dart       — add getWifiNetworks/connectWifi/getBluetoothDevices/connectBluetooth
  4. commands_screen.dart  — drop 'power' from the rendered categories (Shutdown/etc
     now live only in Control; the daemon commands themselves are untouched)

Run locally:
    python3 patch_prime_network.py
"""
from pathlib import Path

DAEMON_MAIN = Path.home() / "Projects/prime/prime-daemon/app/main.py"
DAEMON_COMMANDS = Path.home() / "Projects/prime/prime-daemon/app/commands.py"
API_CLIENT = Path.home() / "Projects/prime/prime_app/lib/services/api_client.dart"
COMMANDS_SCREEN = Path.home() / "Projects/prime/prime_app/lib/screens/commands_screen.dart"


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
    # 1a. daemon: import the new network module
    patch(
        DAEMON_MAIN,
        old='from app import filesystem, packages, media, services',
        new='from app import filesystem, packages, media, services, network',
        label="main.py network import",
        already_done_marker="from app import filesystem, packages, media, services, network",
    )

    # 1b. daemon: add the 4 network routes, right after /display/brightness GET
    patch(
        DAEMON_MAIN,
        old=(
            '@app.get("/display/brightness", dependencies=[Depends(verify_token)])\n'
            'def display_get_brightness():\n'
            '    try:\n'
            '        return media.get_brightness()\n'
            '    except media.ControlError as e:\n'
            '        raise HTTPException(status_code=500, detail=str(e))\n'
        ),
        new=(
            '@app.get("/display/brightness", dependencies=[Depends(verify_token)])\n'
            'def display_get_brightness():\n'
            '    try:\n'
            '        return media.get_brightness()\n'
            '    except media.ControlError as e:\n'
            '        raise HTTPException(status_code=500, detail=str(e))\n'
            '\n\n'
            '@app.get("/network/wifi", dependencies=[Depends(verify_token)])\n'
            'def network_wifi_list():\n'
            '    try:\n'
            '        return network.list_wifi_networks()\n'
            '    except network.NetworkError as e:\n'
            '        raise HTTPException(status_code=500, detail=str(e))\n'
            '\n\n'
            'class WifiConnectBody(BaseModel):\n'
            '    ssid: str\n'
            '\n\n'
            '@app.post("/network/wifi/connect", dependencies=[Depends(verify_token)])\n'
            'def network_wifi_connect(body: WifiConnectBody):\n'
            '    try:\n'
            '        return network.connect_wifi(body.ssid)\n'
            '    except network.NetworkError as e:\n'
            '        raise HTTPException(status_code=500, detail=str(e))\n'
            '\n\n'
            '@app.get("/network/bluetooth", dependencies=[Depends(verify_token)])\n'
            'def network_bluetooth_list():\n'
            '    try:\n'
            '        return network.list_bluetooth_devices()\n'
            '    except network.NetworkError as e:\n'
            '        raise HTTPException(status_code=500, detail=str(e))\n'
            '\n\n'
            'class BluetoothConnectBody(BaseModel):\n'
            '    mac: str\n'
            '\n\n'
            '@app.post("/network/bluetooth/connect", dependencies=[Depends(verify_token)])\n'
            'def network_bluetooth_connect(body: BluetoothConnectBody):\n'
            '    try:\n'
            '        return network.connect_bluetooth(body.mac)\n'
            '    except network.NetworkError as e:\n'
            '        raise HTTPException(status_code=500, detail=str(e))\n'
        ),
        label="main.py network routes",
        already_done_marker='@app.get("/network/wifi"',
    )

    # 2. daemon: add a shutdown command next to reboot
    patch(
        DAEMON_COMMANDS,
        old=(
            '    "reboot": {\n'
            '        "name": "Reboot",\n'
            '        "description": "Reboot the laptop",\n'
            '        "category": "power",\n'
            '        "needs_confirm": True,\n'
            '        "run": lambda: run_fire(["systemctl", "reboot"]),\n'
            '    },\n'
        ),
        new=(
            '    "reboot": {\n'
            '        "name": "Reboot",\n'
            '        "description": "Reboot the laptop",\n'
            '        "category": "power",\n'
            '        "needs_confirm": True,\n'
            '        "run": lambda: run_fire(["systemctl", "reboot"]),\n'
            '    },\n'
            '    "shutdown": {\n'
            '        "name": "Shutdown",\n'
            '        "description": "Power off the laptop",\n'
            '        "category": "power",\n'
            '        "needs_confirm": True,\n'
            '        "run": lambda: run_fire(["systemctl", "poweroff"]),\n'
            '    },\n'
        ),
        label="commands.py shutdown command",
        already_done_marker='"shutdown": {',
    )

    # 3. Dart: add WiFi/Bluetooth client methods after setKbdBacklight
    patch(
        API_CLIENT,
        old=(
            "  Future<Map<String, dynamic>> getKbdBacklight() => _get('/keyboard/backlight');\n"
            "\n"
            "  Future<Map<String, dynamic>> setKbdBacklight(int level) => _post('/keyboard/backlight', {'level': level});\n"
        ),
        new=(
            "  Future<Map<String, dynamic>> getKbdBacklight() => _get('/keyboard/backlight');\n"
            "\n"
            "  Future<Map<String, dynamic>> setKbdBacklight(int level) => _post('/keyboard/backlight', {'level': level});\n"
            "\n"
            "  // ---- Network ----\n"
            "\n"
            "  Future<Map<String, dynamic>> getWifiNetworks() => _get('/network/wifi');\n"
            "\n"
            "  Future<Map<String, dynamic>> connectWifi(String ssid) => _post('/network/wifi/connect', {'ssid': ssid});\n"
            "\n"
            "  Future<Map<String, dynamic>> getBluetoothDevices() => _get('/network/bluetooth');\n"
            "\n"
            "  Future<Map<String, dynamic>> connectBluetooth(String mac) => _post('/network/bluetooth/connect', {'mac': mac});\n"
        ),
        label="api_client.dart network methods",
        already_done_marker="getWifiNetworks",
    )

    # 4a. Flutter: drop 'power' from the category order
    patch(
        COMMANDS_SCREEN,
        old="  static const _categoryOrder = ['info', 'power', 'utility'];",
        new="  static const _categoryOrder = ['info', 'utility'];",
        label="commands_screen.dart category order",
        already_done_marker="_categoryOrder = ['info', 'utility'];",
    )

    # 4b. Flutter: drop the 'power' label entry
    patch(
        COMMANDS_SCREEN,
        old=(
            "  static const _categoryLabels = {\n"
            "    'info': 'INFO',\n"
            "    'power': 'POWER',\n"
            "    'utility': 'UTILITY',\n"
            "  };"
        ),
        new=(
            "  static const _categoryLabels = {\n"
            "    'info': 'INFO',\n"
            "    'utility': 'UTILITY',\n"
            "  };"
        ),
        label="commands_screen.dart category labels",
        already_done_marker="'info': 'INFO',\n    'utility': 'UTILITY',\n  };",
    )

    # 4c. Flutter: stop rendering the 'power' category in the list
    patch(
        COMMANDS_SCREEN,
        old=(
            "    // POWER, UTILITY\n"
            "    for (final cat in ['power', 'utility']) {"
        ),
        new=(
            "    // UTILITY\n"
            "    for (final cat in ['utility']) {"
        ),
        label="commands_screen.dart render loop",
        already_done_marker="for (final cat in ['utility']) {",
    )


if __name__ == "__main__":
    main()
