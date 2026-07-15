"""
Prime daemon configuration.

Everything lives under ~/.config/prime/. On first run, a token is
generated automatically if one doesn't exist yet.
"""
import os
import secrets
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "prime"
TOKEN_PATH = CONFIG_DIR / "token"
TRASH_DIR = Path.home() / ".prime-trash"

# Bind address: Tailscale interface only, never 0.0.0.0.
# Override with PRIME_BIND_HOST env var if your tailnet IP changes.
BIND_HOST = os.environ.get("PRIME_BIND_HOST", "100.64.0.0")  # placeholder, see README
BIND_PORT = int(os.environ.get("PRIME_BIND_PORT", "8420"))

# Roots the file browser / delete / move endpoints are allowed to touch.
# Anything outside these paths is rejected, no exceptions.
ALLOWLISTED_ROOTS = [
    Path.home() / "Projects",
    Path.home() / "Downloads",
    Path.home() / ".config",
]

# systemd --user services exposed for status/restart via the app's dynamic
# service management. Add a new project's service name here and it appears
# in the app automatically — no new daemon code needed.
SERVICES_TO_CHECK = ["prime-daemon.service", "hyprpanel.service"]


def get_or_create_token() -> str:
    """Return the auth token, generating one on first run."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if TOKEN_PATH.exists():
        return TOKEN_PATH.read_text().strip()

    token = secrets.token_urlsafe(32)
    TOKEN_PATH.write_text(token)
    TOKEN_PATH.chmod(0o600)
    print(f"[prime] Generated new auth token, saved to {TOKEN_PATH}")
    print(f"[prime] Token: {token}")
    print("[prime] Enter this in the Prime app's Settings screen.")
    return token


def is_path_allowed(path: Path) -> bool:
    """Check a resolved path falls under one of the allowlisted roots."""
    resolved = path.resolve()
    for root in ALLOWLISTED_ROOTS:
        try:
            resolved.relative_to(root.resolve())
            return True
        except ValueError:
            continue
    return False
