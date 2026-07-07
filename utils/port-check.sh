#!/usr/bin/env bash
# ---
# Summary: Checks whether a local TCP port is listening.
# Changes: None. This is read-only.
# Run: ./utils/port-check.sh <port>
# ---

set -euo pipefail

show_help() {
    cat <<'HELP'
Usage: port-check.sh <port>

Checks whether a local TCP port appears to be listening.
Examples:
  ./utils/port-check.sh 22
  ./utils/port-check.sh 8080
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

port="${1:-}"
if [[ -z "$port" || ! "$port" =~ ^[0-9]+$ || "$port" -lt 1 || "$port" -gt 65535 ]]; then
    echo "Provide a valid TCP port from 1 to 65535." >&2
    show_help >&2
    exit 2
fi

echo "Checking local TCP port: $port"

if command -v ss >/dev/null 2>&1; then
    if ss -ltnp 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" { found=1; print } END { exit found ? 0 : 1 }'; then
        echo "Port $port is listening."
        exit 0
    fi
elif command -v netstat >/dev/null 2>&1; then
    if netstat -ltnp 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" { found=1; print } END { exit found ? 0 : 1 }'; then
        echo "Port $port is listening."
        exit 0
    fi
else
    echo "Neither ss nor netstat is available." >&2
    exit 3
fi

echo "Port $port does not appear to be listening locally."
exit 1