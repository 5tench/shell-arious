#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'HELP'
Summary:
  Installs VirtualBox Guest Additions from an already-mounted ISO.

Usage:
  install-guest-additions.sh [mount_path]

Examples:
  sudo ./scripts/install-guest-additions.sh /mnt/cdrom

Notes:
  Changes the system by installing build packages and running the Guest Additions installer.
  Detects common package managers at runtime instead of keeping distro-specific copies.
HELP
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
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

if command_exists apt-get; then
  apt-get update
  apt-get install -y build-essential dkms linux-headers-"$(uname -r)" perl
elif command_exists dnf; then
  dnf install -y gcc make perl dkms kernel-devel kernel-headers
elif command_exists yum; then
  yum install -y gcc make perl dkms kernel-devel kernel-headers
elif command_exists zypper; then
  zypper install -y gcc make perl dkms kernel-devel kernel-default-devel
elif command_exists pacman; then
  pacman -Syu --noconfirm base-devel dkms linux-headers perl
else
  echo "Unsupported package manager. Install build tools and kernel headers manually." >&2
  exit 3
fi

sh "$installer"
echo "Guest Additions installer finished. Reboot the VM before testing."