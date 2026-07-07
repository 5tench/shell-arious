#!/usr/bin/env bash
set -euo pipefail

APPLY=false
PKG_MANAGER=""

show_help() {
  cat <<'HELP'
Summary:
  Shows or performs common local cleanup tasks for user cache, trash, package cache, and logs.

Usage:
  bash_cleanUp.sh [--apply]

Examples:
  ./utils/bash_cleanUp.sh
  ./utils/bash_cleanUp.sh --apply

Notes:
  Dry-run by default. Deletes files and runs cleanup commands only with --apply.
  Package-cache cleanup is selected at runtime for apt, dnf, yum, zypper, or pacman.
HELP
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
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
        echo "Unknown option: $1" >&2
        show_help >&2
        exit 2
        ;;
    esac
  done
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

run_or_preview() {
  echo "+ $*"

  if [[ "$APPLY" == true ]]; then
    "$@"
  fi
}

remove_directory_contents() {
  local target="$1"
  local needs_sudo="${2:-false}"

  if [[ ! -d "$target" ]]; then
    echo "Skipping $target: directory not found."
    return 0
  fi

  if [[ "$needs_sudo" == true ]]; then
    run_or_preview sudo find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  else
    run_or_preview find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  fi
}

package_cleanup_commands() {
  case "$PKG_MANAGER" in
    apt-get|apt)
      run_or_preview sudo "$PKG_MANAGER" autoremove -y
      run_or_preview sudo "$PKG_MANAGER" clean
      ;;
    dnf|yum)
      run_or_preview sudo "$PKG_MANAGER" autoremove -y
      run_or_preview sudo "$PKG_MANAGER" clean all
      ;;
    zypper)
      run_or_preview sudo zypper clean
      ;;
    pacman)
      run_or_preview sudo pacman -Sc --noconfirm
      ;;
    "")
      echo "No supported package manager found for package-cache cleanup."
      ;;
  esac
}

main() {
  parse_args "$@"
  detect_package_manager

  echo "System cleanup helper"
  echo "Package manager: ${PKG_MANAGER:-not found}"
  if [[ "$APPLY" == true ]]; then
    mode="apply"
  else
    mode="dry-run"
  fi

  echo "Mode: $mode"
  echo

  remove_directory_contents "$HOME/.cache/thumbnails"
  remove_directory_contents "$HOME/.local/share/Trash"
  remove_directory_contents "/var/crash" true

  if command_exists journalctl; then
    run_or_preview sudo journalctl --vacuum-time=7d
  else
    echo "Skipping journal cleanup: journalctl not available."
  fi

  package_cleanup_commands

  if [[ "$APPLY" != true ]]; then
    echo
    echo "No files were removed. Rerun with --apply to perform cleanup."
  fi
}

main "$@"
