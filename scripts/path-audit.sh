#!/usr/bin/env bash
set -euo pipefail

CHECK_WRITABLE=false

show_help() {
  cat <<'HELP'
Summary:
  Inspect shell PATH for duplicates, missing directories, and risky entries.

Usage:
  path-audit.sh [--check-writable]

Examples:
  ./scripts/path-audit.sh
  ./scripts/path-audit.sh --check-writable

Notes:
  Read-only. Helps catch subtle shell environment problems.
HELP
}

die() {
  echo "error: $*" >&2
  exit 2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check-writable)
        CHECK_WRITABLE=true
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

print_path_entries() {
  IFS=':' read -r -a entries <<< "${PATH:-}"

  declare -A seen
  local missing=0
  local duplicate=0
  local risky=0
  local status

  printf '%-45s %s\n' "PATH entry" "status"
  printf '%-45s %s\n' "----------" "------"

  for entry in "${entries[@]}"; do
    status="ok"

    if [[ -z "$entry" || "$entry" == "." ]]; then
      status="relative-or-current-dir"
      risky=$((risky + 1))
    elif [[ "$entry" != /* ]]; then
      status="relative"
      risky=$((risky + 1))
    fi

    if [[ -n "${seen[$entry]:-}" ]]; then
      status="duplicate"
      duplicate=$((duplicate + 1))
    fi
    seen[$entry]=1

    if [[ ! -d "$entry" && "$entry" != "." && -n "$entry" ]]; then
      status="missing"
      missing=$((missing + 1))
    fi

    if [[ "$CHECK_WRITABLE" == true && -d "$entry" && -w "$entry" ]]; then
      status="$status,writable-by-current-user"
    fi

    printf '%-45s %s\n' "${entry:-<empty>}" "$status"
  done

  echo
  echo "Summary: missing=$missing duplicates=$duplicate risky=$risky"
}

print_common_tools() {
  echo
  echo "Common tool check:"

  for tool in git curl awk sed grep find sort xargs ssh; do
    if command -v "$tool" >/dev/null 2>&1; then
      echo "found: $tool"
    else
      echo "missing: $tool"
    fi
  done
}

main() {
  parse_args "$@"
  print_path_entries
  print_common_tools
}

main "$@"