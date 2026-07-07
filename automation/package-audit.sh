#!/usr/bin/env bash
set -euo pipefail

OS_ID="unknown"
OS_NAME="unknown"
OS_LIKE=""
PKG_MANAGER=""

show_help() {
  cat <<'HELP'
Summary:
  Read-only package and OS audit across common Linux package managers.

Usage:
  package-audit.sh

Examples:
  ./automation/package-audit.sh

Notes:
  Detects apt-get, apt, dnf, yum, zypper, or pacman at runtime.
  No packages are installed, updated, or removed.
HELP
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

print_section() {
  echo
  echo "== $* =="
}

detect_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_NAME="${PRETTY_NAME:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
  fi
}

detect_package_manager() {
  if command_exists dnf; then
    PKG_MANAGER="dnf"
  elif command_exists yum; then
    PKG_MANAGER="yum"
  elif command_exists apt-get; then
    PKG_MANAGER="apt-get"
  elif command_exists apt; then
    PKG_MANAGER="apt"
  elif command_exists zypper; then
    PKG_MANAGER="zypper"
  elif command_exists pacman; then
    PKG_MANAGER="pacman"
  else
    PKG_MANAGER=""
  fi
}

print_host_summary() {
  print_section "system"
  echo "host: $(hostname)"
  echo "date: $(date)"
  echo "os: $OS_NAME"
  echo "os_id: $OS_ID"
  echo "os_like: ${OS_LIKE:-unknown}"
  echo "kernel: $(uname -r)"
  echo "package_manager: ${PKG_MANAGER:-not found}"
}

print_apt_audit() {
  print_section "apt packages"

  if command_exists dpkg-query; then
    echo "installed_packages: $(dpkg-query -f '${binary:Package}\n' -W 2>/dev/null | wc -l)"
  else
    echo "installed_packages: unknown (dpkg-query not available)"
  fi

  echo
  echo "held packages:"
  if command_exists apt-mark; then
    apt-mark showhold 2>/dev/null || true
  else
    echo "apt-mark not available"
  fi

  echo
  echo "available updates:"
  if command_exists apt; then
    apt list --upgradable 2>/dev/null | sed '1d' || true
  elif command_exists apt-get; then
    apt-get --just-print upgrade 2>/dev/null | awk '/^Inst / { print $2, $3 }' || true
  fi

  echo
  echo "recent dpkg activity:"
  if [[ -r /var/log/dpkg.log ]]; then
    grep ' install ' /var/log/dpkg.log | tail -10 || true
  else
    echo "dpkg log not readable"
  fi
}

print_rpm_audit() {
  print_section "$PKG_MANAGER packages"

  if command_exists rpm; then
    echo "installed_packages: $(rpm -qa 2>/dev/null | wc -l)"
  else
    echo "installed_packages: unknown (rpm not available)"
  fi

  echo
  echo "available updates:"
  "$PKG_MANAGER" check-update || true

  echo
  echo "recent installed packages:"
  if command_exists rpm; then
    rpm -qa --last 2>/dev/null | head -10 || true
  else
    echo "rpm not available"
  fi
}

print_zypper_audit() {
  print_section "zypper packages"
  echo "installed_packages: $(rpm -qa 2>/dev/null | wc -l || echo unknown)"

  echo
  echo "available updates:"
  zypper list-updates 2>/dev/null || true

  echo
  echo "recent installed packages:"
  rpm -qa --last 2>/dev/null | head -10 || true
}

print_pacman_audit() {
  print_section "pacman packages"
  echo "installed_packages: $(pacman -Qq 2>/dev/null | wc -l)"

  echo
  echo "available updates:"
  pacman -Qu 2>/dev/null || true

  echo
  echo "recent package log entries:"
  if [[ -r /var/log/pacman.log ]]; then
    grep '\[ALPM\] installed' /var/log/pacman.log | tail -10 || true
  else
    echo "pacman log not readable"
  fi
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
  fi

  if [[ $# -gt 0 ]]; then
    echo "error: unknown argument: $1" >&2
    show_help >&2
    exit 2
  fi

  detect_os
  detect_package_manager
  print_host_summary

  case "$PKG_MANAGER" in
    apt-get|apt)
      print_apt_audit
      ;;
    dnf|yum)
      print_rpm_audit
      ;;
    zypper)
      print_zypper_audit
      ;;
    pacman)
      print_pacman_audit
      ;;
    "")
      echo
      echo "No supported package manager found."
      exit 1
      ;;
  esac
}

main "$@"