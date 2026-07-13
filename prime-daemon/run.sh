#!/usr/bin/env bash
# Resolves the current Tailscale IP at startup (it can change across
# reconnects/reinstalls) and launches the daemon bound to it.
set -euo pipefail

cd "$(dirname "$0")"

TS_IP="$(tailscale ip -4 2>/dev/null || true)"

if [ -z "$TS_IP" ]; then
    echo "[prime] Could not resolve Tailscale IP. Is tailscale up?" >&2
    exit 1
fi

export PRIME_BIND_HOST="$TS_IP"
echo "[prime] Binding to Tailscale IP: $TS_IP"

exec ./venv/bin/uvicorn app.main:app --host "$PRIME_BIND_HOST" --port 8420
