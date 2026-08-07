#!/usr/bin/env python3
"""
Follow-up fix: the first patch added `showLabel: false` to Log Out but
missed Restart and Shutdown. This adds it to those two.

Run from prime_app/ (same folder as home_screen.dart).
Idempotent: safe to re-run.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
HOME_SCREEN = ROOT / "lib/screens/home_screen.dart"

if not HOME_SCREEN.exists():
    print(f"[ABORT] file not found at {HOME_SCREEN}")
    sys.exit(1)

text = HOME_SCREEN.read_text()
changed = False

replacements = [
    (
        "                        commandId: 'reboot',\n"
        "                        label: 'Restart',\n"
        "                        icon: Icons.restart_alt,\n"
        "                        needsConfirm: true,\n"
        "                        expectDaemonDeath: true,\n"
        "                      ),\n",

        "                        commandId: 'reboot',\n"
        "                        label: 'Restart',\n"
        "                        icon: Icons.restart_alt,\n"
        "                        needsConfirm: true,\n"
        "                        expectDaemonDeath: true,\n"
        "                        showLabel: false,\n"
        "                      ),\n"
    ),
    (
        "                        commandId: 'shutdown',\n"
        "                        label: 'Shutdown',\n"
        "                        icon: Icons.power_settings_new,\n"
        "                        needsConfirm: true,\n"
        "                        expectDaemonDeath: true,\n"
        "                      ),\n",

        "                        commandId: 'shutdown',\n"
        "                        label: 'Shutdown',\n"
        "                        icon: Icons.power_settings_new,\n"
        "                        needsConfirm: true,\n"
        "                        expectDaemonDeath: true,\n"
        "                        showLabel: false,\n"
        "                      ),\n"
    ),
]

for old, new in replacements:
    if new in text:
        continue
    count = text.count(old)
    if count == 0:
        print("[ABORT] anchor not found:")
        print(old)
        sys.exit(1)
    if count > 1:
        print(f"[ABORT] anchor matched {count} times, expected 1:")
        print(old)
        sys.exit(1)
    text = text.replace(old, new)
    changed = True

if changed:
    HOME_SCREEN.write_text(text)
    print("[OK] home_screen.dart: added showLabel: false to Restart and Shutdown")
else:
    print("[SKIP] already up to date")
