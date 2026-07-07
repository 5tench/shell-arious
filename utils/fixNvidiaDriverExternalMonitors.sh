#!/usr/bin/env bash
set -euo pipefail

APPLY=false

show_help() {
  cat <<'HELP'
Summary:
  Lists or runs Ubuntu NVIDIA/Mesa refresh commands for external monitor troubleshooting.

Usage:
  fixNvidiaDriverExternalMonitors.sh [--apply]

Examples:
  ./utils/fixNvidiaDriverExternalMonitors.sh
  ./utils/fixNvidiaDriverExternalMonitors.sh --apply

Notes:
  Dry-run by default. This workflow is Ubuntu/apt-specific because it uses a PPA.
  On non-apt systems, the script exits with a clear message and makes no changes.
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

run_or_show() {
  local command_text="$1"

  if [[ "$APPLY" == true ]]; then
    echo "+ $command_text"
    eval "$command_text"
  else
    echo "DRY RUN: $command_text"
  fi
}

main() {
  parse_args "$@"

  if ! command_exists apt; then
    echo "apt not found. This NVIDIA/Mesa helper is only written for Ubuntu-style apt systems." >&2
    exit 3
  fi

  if ! command_exists add-apt-repository; then
    echo "add-apt-repository not found. Install software-properties-common before using this helper." >&2
    exit 3
  fi

  local commands=(
    "sudo apt update"
    "sudo apt upgrade -y"
    "sudo add-apt-repository ppa:kisak/kisak-mesa -y"
    "sudo apt update"
    "sudo apt upgrade -y"
    "sudo apt install -y nvidia-driver-535"
  )

  for command_text in "${commands[@]}"; do
    run_or_show "$command_text"
  done

  if [[ "$APPLY" == true ]]; then
    echo "Driver commands completed. Reboot before testing external monitors."
  else
    echo "No changes made. Rerun with --apply to execute these commands."
  fi
}

main "$@"