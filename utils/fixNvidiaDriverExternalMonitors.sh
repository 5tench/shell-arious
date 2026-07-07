#!/usr/bin/env bash
# ---
# Summary: Lists or runs Ubuntu NVIDIA/Mesa refresh commands for external monitor troubleshooting.
# Changes: Dry-run by default. Adds a PPA and installs packages only with --apply.
# Run: ./utils/fixNvidiaDriverExternalMonitors.sh then ./utils/fixNvidiaDriverExternalMonitors.sh --apply
# ---

set -euo pipefail

show_help() {
    cat <<'HELP'
Usage: fixNvidiaDriverExternalMonitors.sh [--apply]

Prints the commands commonly used to refresh Mesa/NVIDIA packages on Ubuntu-based systems.
Use --apply only after reviewing the commands for your machine.
HELP
}

APPLY=false
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
elif [[ "${1:-}" == "--apply" ]]; then
    APPLY=true
fi

commands=(
    "sudo apt update"
    "sudo apt upgrade -y"
    "sudo add-apt-repository ppa:kisak/kisak-mesa -y"
    "sudo apt update"
    "sudo apt upgrade -y"
    "sudo apt install -y nvidia-driver-535"
)

for cmd in "${commands[@]}"; do
    if [[ "$APPLY" == true ]]; then
        echo "+ $cmd"
        eval "$cmd"
    else
        echo "DRY RUN: $cmd"
    fi
done

if [[ "$APPLY" == true ]]; then
    echo "Driver commands completed. Reboot before testing external monitors."
else
    echo "No changes made. Rerun with --apply to execute these commands."
fi