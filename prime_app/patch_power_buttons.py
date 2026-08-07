#!/usr/bin/env python3
"""
Patch: shrink Log Out / Restart / Shutdown power buttons to half-width
(right-aligned, empty space on the left) and render icon-only (no label).

Run from anywhere; paths are relative to this script's location, which
must be prime_app/ (i.e. this file should live at prime_app/patch_power_buttons.py).

Idempotent: safe to re-run. Aborts loudly on any mismatch instead of
silently corrupting the file.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent

LIQUID_BTN = ROOT / "lib/widgets/liquid_confirm_button.dart"
HOME_SCREEN = ROOT / "lib/screens/home_screen.dart"


def patch(path: pathlib.Path, replacements: list[tuple[str, str]], label: str):
    if not path.exists():
        print(f"[ABORT] {label}: file not found at {path}")
        sys.exit(1)

    text = path.read_text()
    changed = False

    for old, new in replacements:
        if new in text:
            # already applied
            continue
        count = text.count(old)
        if count == 0:
            print(f"[ABORT] {label}: anchor not found (already patched differently, or file changed):")
            print("---- expected anchor ----")
            print(old)
            sys.exit(1)
        if count > 1:
            print(f"[ABORT] {label}: anchor matched {count} times, expected exactly 1:")
            print("---- ambiguous anchor ----")
            print(old)
            sys.exit(1)
        text = text.replace(old, new)
        changed = True

    if changed:
        path.write_text(text)
        print(f"[OK] {label}: patched")
    else:
        print(f"[SKIP] {label}: already up to date")


# ---------------------------------------------------------------------------
# 1. liquid_confirm_button.dart -- add `showLabel` flag, honor it in filled variant
# ---------------------------------------------------------------------------
liquid_btn_replacements = [
    (
        '  final bool expectDaemonDeath;\n'
        '  final LiquidButtonVariant variant;\n'
        '\n'
        '  const LiquidConfirmButton({\n',

        '  final bool expectDaemonDeath;\n'
        '  final LiquidButtonVariant variant;\n'
        '  final bool showLabel;\n'
        '\n'
        '  const LiquidConfirmButton({\n'
    ),
    (
        '    this.expectDaemonDeath = false,\n'
        '    this.variant = LiquidButtonVariant.outlined,\n'
        '  }) : assert(\n',

        '    this.expectDaemonDeath = false,\n'
        '    this.variant = LiquidButtonVariant.outlined,\n'
        '    this.showLabel = true,\n'
        '  }) : assert(\n'
    ),
    (
        '                  Icon(_verifying ? Icons.fingerprint : widget.icon, size: 14, color: Colors.white),\n'
        '                  const SizedBox(width: 6),\n'
        '                  Flexible(\n'
        '                    child: Text(\n'
        '                      _verifying ? \'Verify\' : widget.label,\n'
        '                      overflow: TextOverflow.ellipsis,\n'
        '                      style: PrimeTheme.text(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),\n'
        '                    ),\n'
        '                  ),\n'
        '                ],\n',

        '                  Icon(_verifying ? Icons.fingerprint : widget.icon, size: 14, color: Colors.white),\n'
        '                  if (widget.showLabel) ...[\n'
        '                    const SizedBox(width: 6),\n'
        '                    Flexible(\n'
        '                      child: Text(\n'
        '                        _verifying ? \'Verify\' : widget.label,\n'
        '                        overflow: TextOverflow.ellipsis,\n'
        '                        style: PrimeTheme.text(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),\n'
        '                      ),\n'
        '                    ),\n'
        '                  ],\n'
        '                ],\n'
    ),
]

# ---------------------------------------------------------------------------
# 2. home_screen.dart -- thread showLabel through _PowerActionButton, and
#    wrap Log Out / Restart / Shutdown in a half-width, right-aligned box.
# ---------------------------------------------------------------------------
home_screen_replacements = [
    (
        'class _PowerActionButton extends StatelessWidget {\n'
        '  final ApiClient apiClient;\n'
        '  final String commandId;\n'
        '  final String label;\n'
        '  final IconData icon;\n'
        '  final bool needsConfirm;\n'
        '  final bool expectDaemonDeath;\n'
        '  const _PowerActionButton({\n'
        '    required this.apiClient,\n'
        '    required this.commandId,\n'
        '    required this.label,\n'
        '    required this.icon,\n'
        '    required this.needsConfirm,\n'
        '    this.expectDaemonDeath = false,\n'
        '  });\n'
        '\n'
        '  @override\n'
        '  Widget build(BuildContext context) {\n'
        '    return LiquidConfirmButton(\n'
        '      apiClient: apiClient,\n'
        '      commandId: commandId,\n'
        '      label: label,\n'
        '      icon: icon,\n'
        '      needsConfirm: needsConfirm,\n'
        '      expectDaemonDeath: expectDaemonDeath,\n'
        '      variant: LiquidButtonVariant.filled,\n'
        '    );\n'
        '  }\n'
        '}\n',

        'class _PowerActionButton extends StatelessWidget {\n'
        '  final ApiClient apiClient;\n'
        '  final String commandId;\n'
        '  final String label;\n'
        '  final IconData icon;\n'
        '  final bool needsConfirm;\n'
        '  final bool expectDaemonDeath;\n'
        '  final bool showLabel;\n'
        '  const _PowerActionButton({\n'
        '    required this.apiClient,\n'
        '    required this.commandId,\n'
        '    required this.label,\n'
        '    required this.icon,\n'
        '    required this.needsConfirm,\n'
        '    this.expectDaemonDeath = false,\n'
        '    this.showLabel = true,\n'
        '  });\n'
        '\n'
        '  @override\n'
        '  Widget build(BuildContext context) {\n'
        '    return LiquidConfirmButton(\n'
        '      apiClient: apiClient,\n'
        '      commandId: commandId,\n'
        '      label: label,\n'
        '      icon: icon,\n'
        '      needsConfirm: needsConfirm,\n'
        '      expectDaemonDeath: expectDaemonDeath,\n'
        '      variant: LiquidButtonVariant.filled,\n'
        '      showLabel: showLabel,\n'
        '    );\n'
        '  }\n'
        '}\n'
    ),
    (
        '                  Expanded(\n'
        '                    child: _PowerActionButton(\n'
        '                      apiClient: widget.apiClient,\n'
        '                      commandId: \'logout\',\n'
        '                      label: \'Log Out\',\n'
        '                      icon: Icons.logout,\n'
        '                      needsConfirm: true,\n'
        '                    ),\n'
        '                  ),\n'
        '                ],\n'
        '              ),\n'
        '              const SizedBox(height: 8),\n',

        '                  Expanded(\n'
        '                    child: FractionallySizedBox(\n'
        '                      widthFactor: 0.5,\n'
        '                      alignment: Alignment.centerRight,\n'
        '                      child: _PowerActionButton(\n'
        '                        apiClient: widget.apiClient,\n'
        '                        commandId: \'logout\',\n'
        '                        label: \'Log Out\',\n'
        '                        icon: Icons.logout,\n'
        '                        needsConfirm: true,\n'
        '                        showLabel: false,\n'
        '                      ),\n'
        '                    ),\n'
        '                  ),\n'
        '                ],\n'
        '              ),\n'
        '              const SizedBox(height: 8),\n'
    ),
    (
        '                  Expanded(\n'
        '                    child: _PowerActionButton(\n'
        '                      apiClient: widget.apiClient,\n'
        '                      commandId: \'reboot\',\n'
        '                      label: \'Restart\',\n'
        '                      icon: Icons.restart_alt,\n'
        '                      needsConfirm: true,\n'
        '                      expectDaemonDeath: true,\n'
        '                    ),\n'
        '                  ),\n'
        '                  const SizedBox(width: 8),\n'
        '                  Expanded(\n'
        '                    child: _PowerActionButton(\n'
        '                      apiClient: widget.apiClient,\n'
        '                      commandId: \'shutdown\',\n'
        '                      label: \'Shutdown\',\n'
        '                      icon: Icons.power_settings_new,\n'
        '                      needsConfirm: true,\n'
        '                      expectDaemonDeath: true,\n'
        '                    ),\n'
        '                  ),\n'
        '                ],\n'
        '              ),\n'
        '            ],\n'
        '            const SizedBox(height: 18),\n',

        '                  Expanded(\n'
        '                    child: FractionallySizedBox(\n'
        '                      widthFactor: 0.5,\n'
        '                      alignment: Alignment.centerRight,\n'
        '                      child: _PowerActionButton(\n'
        '                        apiClient: widget.apiClient,\n'
        '                        commandId: \'reboot\',\n'
        '                        label: \'Restart\',\n'
        '                        icon: Icons.restart_alt,\n'
        '                        needsConfirm: true,\n'
        '                        expectDaemonDeath: true,\n'
        '                      ),\n'
        '                    ),\n'
        '                  ),\n'
        '                  const SizedBox(width: 8),\n'
        '                  Expanded(\n'
        '                    child: FractionallySizedBox(\n'
        '                      widthFactor: 0.5,\n'
        '                      alignment: Alignment.centerRight,\n'
        '                      child: _PowerActionButton(\n'
        '                        apiClient: widget.apiClient,\n'
        '                        commandId: \'shutdown\',\n'
        '                        label: \'Shutdown\',\n'
        '                        icon: Icons.power_settings_new,\n'
        '                        needsConfirm: true,\n'
        '                        expectDaemonDeath: true,\n'
        '                      ),\n'
        '                    ),\n'
        '                  ),\n'
        '                ],\n'
        '              ),\n'
        '            ],\n'
        '            const SizedBox(height: 18),\n'
    ),
]

patch(LIQUID_BTN, liquid_btn_replacements, "liquid_confirm_button.dart")
patch(HOME_SCREEN, home_screen_replacements, "home_screen.dart")

print("\nDone. Next steps:")
print("  1. python3 -c \"import ast\" # (dart has no ast module here -- just run flutter analyze)")
print("  2. flutter analyze")
print("  3. flutter run (or hot-reload if already running)")
