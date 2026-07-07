#!/usr/bin/env bash
# ---
# Summary: Shows or performs common local cleanup tasks for cache, trash, crash reports, and apt.
# Changes: Dry-run by default. Deletes files and runs cleanup commands only with --apply.
# Run: ./utils/bash_cleanUp.sh then ./utils/bash_cleanUp.sh --apply
# ---

set -euo pipefail

APPLY=false

show_help() {
    cat <<'HELP'
Usage: bash_cleanUp.sh [--apply]

Shows cleanup targets by default. Use --apply to remove user cache, thumbnail cache, trash, apt cache, crash reports, and old journal entries.
This script can delete files. Review the output before using --apply.
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ "${1:-}" == "--apply" ]]; then
    APPLY=true
fi

run_or_show() {
    if [[ "$APPLY" == true ]]; then
        echo "+ $*"
        eval "$@"
    else
        echo "DRY RUN: $*"
    fi
}

echo "System cleanup helper"
echo "Mode: $([[ "$APPLY" == true ]] && echo apply || echo dry-run)"
echo ""

run_or_show 'rm -rf "$HOME/.cache/thumbnails"/*'
run_or_show 'rm -rf "$HOME/.local/share/Trash"/*'
run_or_show 'sudo apt-get clean'
run_or_show 'sudo apt-get autoremove --purge -y'
run_or_show 'sudo rm -rf /var/crash/*'
run_or_show 'sudo journalctl --vacuum-time=7d'

if [[ "$APPLY" != true ]]; then
    echo ""
    echo "No files were removed. Rerun with --apply to perform cleanup."
fi