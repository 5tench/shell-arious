#!/usr/bin/env bash
# ---
# Summary: Installs VirtualBox Guest Additions from an already-mounted ISO.
# Changes: Installs build packages and runs the Guest Additions installer.
# Run: sudo ./scripts/install-guest-additions.sh [/mnt/cdrom]
# ---

set -euo pipefail

show_help() {
    cat <<'HELP'
Usage: install-guest-additions.sh [mount_path]

Installs VirtualBox Guest Additions from an already-mounted ISO.
Default mount path: /mnt/cdrom
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

mount_path="${1:-/mnt/cdrom}"
installer="$mount_path/VBoxLinuxAdditions.run"

if [[ $EUID -ne 0 ]]; then
    echo "Run this script with sudo or as root." >&2
    exit 1
fi

if [[ ! -f "$installer" ]]; then
    echo "Installer not found: $installer" >&2
    echo "Mount the Guest Additions ISO first, then rerun this script." >&2
    exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y build-essential dkms linux-headers-"$(uname -r)" perl
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y gcc make perl dkms kernel-devel kernel-headers
else
    echo "Unsupported package manager. Install build tools and kernel headers manually." >&2
    exit 1
fi

sh "$installer"
echo "Guest Additions installer finished. Reboot the VM before testing."