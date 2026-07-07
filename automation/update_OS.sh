#!/usr/bin/env bash
set -euo pipefail

APPLY=false
PKG_MANAGER=""
OS_NAME="unknown"

show_help() {
  cat <<'HELP'
Summary:
  Preview or apply system package updates using the local package manager.

Usage:
  update_OS.sh [--apply]

Examples:
  ./automation/update_OS.sh
  ./automation/update_OS.sh --apply

Notes:
  Dry-run by default. Supports apt-get, apt, dnf, yum, zypper, and pacman when available.
  Commands are printed before they run. No updates are applied unless --apply is passed.
HELP
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

die() {
  echo "error: $*" >&2
  exit 2
}

detect_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_NAME="${PRETTY_NAME:-unknown}"
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

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply)
        APPLY=true
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
}

run_or_preview() {
  echo "+ $*"

  if [[ "$APPLY" == true ]]; then
    "$@"
  fi
}

run_or_preview_allow_nonzero() {
  echo "+ $*"

  if [[ "$APPLY" == true ]]; then
    "$@" || true
  fi
}

run_apt_updates() {
  local apt_cmd="$1"

  run_or_preview sudo "$apt_cmd" update
  run_or_preview sudo "$apt_cmd" upgrade -y
  run_or_preview sudo "$apt_cmd" autoremove -y
  run_or_preview sudo "$apt_cmd" clean
}

run_rpm_updates() {
  run_or_preview_allow_nonzero sudo "$PKG_MANAGER" check-update
  run_or_preview sudo "$PKG_MANAGER" upgrade -y
  run_or_preview sudo "$PKG_MANAGER" autoremove -y
  run_or_preview sudo "$PKG_MANAGER" clean all
}

run_zypper_updates() {
  run_or_preview sudo zypper --non-interactive refresh
  run_or_preview sudo zypper --non-interactive update
  run_or_preview sudo zypper clean
}

run_pacman_updates() {
  run_or_preview sudo pacman -Syu --noconfirm
}

main() {
  parse_args "$@"
  detect_os
  detect_package_manager

  echo "OS: $OS_NAME"
  echo "Package manager: ${PKG_MANAGER:-not found}"
  if [[ "$APPLY" == true ]]; then
    mode="apply"
  else
    mode="dry-run"
  fi

  echo "Mode: $mode"
  echo

  case "$PKG_MANAGER" in
    apt-get|apt)
      run_apt_updates "$PKG_MANAGER"
      ;;
    dnf|yum)
      run_rpm_updates
      ;;
    zypper)
      run_zypper_updates
      ;;
    pacman)
      run_pacman_updates
      ;;
    "")
      echo "No supported package manager found." >&2
      exit 3
      ;;
  esac

  if [[ "$APPLY" != true ]]; then
    echo
    echo "Dry run only. Rerun with --apply to execute these commands."
  fi
}

main "$@"
