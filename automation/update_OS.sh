#!/usr/bin/env bash
# ---
# Summary: Cleans apt caches and optionally updates Debian/Ubuntu packages.
# Changes: Uses sudo and can modify installed packages when run with --update.
# Run: ./automation/update_OS.sh or ./automation/update_OS.sh --update
# ---

set -euo pipefail

show_help() {
    cat <<'HELP'
Usage: update_OS.sh [--update]

Performs basic apt cleanup on Debian/Ubuntu systems. With --update, also runs package updates.
This script changes the system and may require sudo.
HELP
}

run() {
    echo "+ $*"
    "$@"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "This script expects apt-get and is intended for Debian/Ubuntu systems." >&2
    exit 1
fi

run sudo apt-get autoremove -y
run sudo apt-get autoclean -y
run sudo systemd-tmpfiles --remove || true
run sudo apt-get install -f -y
run sudo apt-get clean

if [[ "${1:-}" == "--update" ]]; then
    run sudo apt-get update
    run sudo apt-get upgrade -y
    run sudo apt-get dist-upgrade -y
else
    echo "Skipping package updates. Rerun with --update to include them."
fi

echo "Cleanup complete."