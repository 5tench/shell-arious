#!/usr/bin/env bash
set -euo pipefail

TARGET=""
CHECK_SUID=false
CHECK_WORLD_WRITABLE=false
EXCLUDES=""

show_help() {
  cat <<'HELP'
Summary:
  Find risky filesystem permissions under a target path.

Usage:
  permission-audit.sh --path dir [--suid] [--world-writable] [--exclude a,b]

Examples:
  ./scripts/permission-audit.sh --path /var/www
  ./scripts/permission-audit.sh --path /etc --suid --world-writable
  ./scripts/permission-audit.sh --path /home --exclude ".cache,node_modules"

Notes:
  Read-only. Reports findings only; does not chmod, chown, or delete.
HELP
}

die() {
  echo "error: $*" >&2
  exit 2
}

print_section() {
  echo
  echo "== $* =="
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)
        TARGET="${2:-}"
        [[ -n "$TARGET" ]] || die "--path requires a directory"
        shift 2
        ;;
      --suid)
        CHECK_SUID=true
        shift
        ;;
      --world-writable)
        CHECK_WORLD_WRITABLE=true
        shift
        ;;
      --exclude)
        EXCLUDES="${2:-}"
        [[ -n "$EXCLUDES" ]] || die "--exclude requires a comma-separated value"
        shift 2
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

  [[ -n "$TARGET" ]] || die "--path is required"
  [[ -d "$TARGET" ]] || die "path not found: $TARGET"
}

is_excluded() {
  local path="$1"

  [[ -n "$EXCLUDES" ]] || return 1

  IFS=',' read -r -a patterns <<< "$EXCLUDES"
  for pattern in "${patterns[@]}"; do
    [[ -n "$pattern" ]] || continue
    if [[ "$path" == *"/$pattern"* || "$path" == *"$pattern"* ]]; then
      return 0
    fi
  done

  return 1
}

print_find_results() {
  local title="$1"
  shift

  print_section "$title"

  while IFS= read -r item; do
    if ! is_excluded "$item"; then
      echo "$item"
    fi
  done < <(find "$TARGET" -xdev "$@" -print 2>/dev/null | head -200)
}

main() {
  parse_args "$@"

  if [[ -n "$EXCLUDES" ]]; then
    echo "exclude patterns: $EXCLUDES"
  fi

  print_find_results "world-writable files" -type f -perm -0002
  print_find_results "world-writable directories" -type d -perm -0002
  print_find_results "suid files" -type f -perm -4000
  print_find_results "sgid files" -type f -perm -2000
  print_find_results "no owner" -nouser
  print_find_results "no group" -nogroup

  print_section "private keys with loose permissions"
  find "$TARGET" -xdev -type f \
    \( -name 'id_rsa' -o -name '*.pem' -o -name '*.key' \) \
    ! -perm 0600 -ls 2>/dev/null \
    | head -100 || true

  print_section "authorized_keys with loose permissions"
  find "$TARGET" -xdev -type f -name authorized_keys ! -perm 0600 -ls 2>/dev/null \
    | head -100 || true
}

main "$@"