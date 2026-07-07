#!/usr/bin/env bash
# ---
# Summary: Read-only package and OS audit for Debian/Ubuntu or RHEL-family systems.
# Changes: None. This only prints information.
# Run: ./automation/package-audit.sh
# ---

set -euo pipefail

show_help() {
    cat <<'HELP'
Usage: package-audit.sh

Prints a read-only package and OS summary for Debian/Ubuntu or RHEL-family systems.
No packages are installed, updated, or removed.
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

echo "System package audit"
echo "Host: $(hostname)"
echo "Date: $(date)"
echo ""

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "OS: ${PRETTY_NAME:-unknown}"
else
    echo "OS: unknown"
fi

echo "Kernel: $(uname -r)"
echo ""

if command -v apt >/dev/null 2>&1; then
    echo "Package manager: apt"
    echo "Installed packages: $(dpkg-query -f '${binary:Package}\n' -W 2>/dev/null | wc -l)"
    echo "Held packages:"
    apt-mark showhold 2>/dev/null || true
    echo ""
    echo "Pending upgrades:"
    apt list --upgradable 2>/dev/null | sed '1d' || true
elif command -v dnf >/dev/null 2>&1; then
    echo "Package manager: dnf"
    echo "Installed packages: $(rpm -qa 2>/dev/null | wc -l)"
    echo ""
    echo "Pending updates:"
    dnf check-update || true
elif command -v yum >/dev/null 2>&1; then
    echo "Package manager: yum"
    echo "Installed packages: $(rpm -qa 2>/dev/null | wc -l)"
    echo ""
    echo "Pending updates:"
    yum check-update || true
else
    echo "No supported package manager found."
    exit 1
fi