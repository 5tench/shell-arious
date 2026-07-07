#!/usr/bin/env bash
set -euo pipefail

USER_FILTER=""
TIMERS_ONLY=false

show_help() {
  cat <<'HELP'
Summary:
  Show cron jobs and systemd timers that may run scheduled work.

Usage:
  cron-timer-audit.sh [--user name] [--timers]

Examples:
  ./scripts/cron-timer-audit.sh
  ./scripts/cron-timer-audit.sh --user alex
  ./scripts/cron-timer-audit.sh --timers

Notes:
  Read-only. Checks common Debian and RHEL-family cron locations when readable.
HELP
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

print_section() {
  echo
  echo "== $* =="
}

die() {
  echo "error: $*" >&2
  exit 2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        USER_FILTER="${2:-}"
        [[ -n "$USER_FILTER" ]] || die "--user requires a username"
        shift 2
        ;;
      --timers)
        TIMERS_ONLY=true
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

print_file_without_comments() {
  local file="$1"

  if [[ -r "$file" ]]; then
    sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$file"
  else
    echo "not readable: $file"
  fi
}

print_system_cron() {
  print_section "/etc/crontab"
  [[ -e /etc/crontab ]] && print_file_without_comments /etc/crontab || echo "not found"

  print_section "/etc/cron.d"
  if [[ -d /etc/cron.d ]]; then
    find /etc/cron.d -maxdepth 1 -type f -print 2>/dev/null | while IFS= read -r file; do
      echo "-- $file"
      print_file_without_comments "$file"
    done
  else
    echo "not found"
  fi

  print_section "periodic cron directories"
  for dir in /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
    if [[ -d "$dir" ]]; then
      echo "-- $dir"
      find "$dir" -maxdepth 1 -type f -printf '%p\n' 2>/dev/null || true
    fi
  done
}

print_spool_cron() {
  print_section "cron spool locations"

  local spool_dirs=(
    /var/spool/cron
    /var/spool/cron/crontabs
  )

  for dir in "${spool_dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
      continue
    fi

    echo "-- $dir"
    find "$dir" -maxdepth 1 -type f -print 2>/dev/null | while IFS= read -r file; do
      if [[ -n "$USER_FILTER" && "$(basename "$file")" != "$USER_FILTER" ]]; then
        continue
      fi

      echo "file: $file"
      print_file_without_comments "$file"
    done
  done
}

print_user_cron() {
  print_section "user crontab command"

  if ! command_exists crontab; then
    echo "crontab command not available"
    return 0
  fi

  if [[ -n "$USER_FILTER" ]]; then
    crontab -l -u "$USER_FILTER" 2>/dev/null || echo "no readable crontab for $USER_FILTER"
  else
    echo "use --user <name> to inspect a specific user with crontab -l"
  fi
}

print_timers() {
  print_section "systemd timers"

  if command_exists systemctl; then
    systemctl list-timers --all --no-pager || true
  else
    echo "systemctl not available"
  fi
}

main() {
  parse_args "$@"

  if [[ "$TIMERS_ONLY" != true ]]; then
    print_system_cron
    print_spool_cron
    print_user_cron
  fi

  print_timers
}

main "$@"