#!/usr/bin/env bash
set -euo pipefail

CSV=false
INCLUDE_SYSTEM=false

show_help() {
  cat <<'HELP'
Summary:
  Summarize local account access and SSH key presence.

Usage:
  user-access-audit.sh [--csv] [--include-system]

Examples:
  ./scripts/user-access-audit.sh
  ./scripts/user-access-audit.sh --csv
  ./scripts/user-access-audit.sh --include-system

Notes:
  Read-only. Handles sudo/wheel group differences and skips checks that are not readable.
HELP
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

die() {
  echo "error: $*" >&2
  exit 2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --csv)
        CSV=true
        shift
        ;;
      --include-system)
        INCLUDE_SYSTEM=true
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

get_group_members() {
  local group_name="$1"

  if getent group "$group_name" >/dev/null 2>&1; then
    getent group "$group_name" | awk -F: '{print $4}'
  fi
}

get_admin_users() {
  local users=""
  local sudo_members
  local wheel_members

  sudo_members=$(get_group_members sudo || true)
  wheel_members=$(get_group_members wheel || true)

  users="$sudo_members,$wheel_members"
  echo "$users"
}

get_lock_state() {
  local user="$1"

  if command_exists passwd; then
    passwd -S "$user" 2>/dev/null | awk '{print $2}' || echo "unknown"
  elif command_exists usermod; then
    echo "unknown"
  else
    echo "unknown"
  fi
}

get_home_owner() {
  local home="$1"

  if [[ ! -d "$home" ]]; then
    echo "missing"
    return 0
  fi

  if stat -c '%U:%G' "$home" >/dev/null 2>&1; then
    stat -c '%U:%G' "$home"
  elif stat -f '%Su:%Sg' "$home" >/dev/null 2>&1; then
    stat -f '%Su:%Sg' "$home"
  else
    echo "unknown"
  fi
}

has_authorized_keys() {
  local home="$1"

  [[ -f "$home/.ssh/authorized_keys" ]]
}

get_last_login() {
  local user="$1"

  if command_exists lastlog; then
    lastlog -u "$user" 2>/dev/null \
      | awk 'NR == 2 { print substr($0, 44) }' \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || echo "unknown"
  elif command_exists last; then
    last -n 1 "$user" 2>/dev/null | head -1 || echo "unknown"
  else
    echo "unknown"
  fi
}

print_header() {
  if [[ "$CSV" == true ]]; then
    echo "user,uid,shell,sudo_or_wheel,locked,home_owner,authorized_keys,last_login"
  else
    printf '%-18s %-8s %-22s %-8s %-8s %-16s %-15s %s\n' \
      "user" "uid" "shell" "admin" "locked" "home_owner" "auth_keys" "last_login"
  fi
}

print_user() {
  local user="$1"
  local uid="$2"
  local home="$3"
  local shell="$4"
  local admin_users="$5"
  local admin="no"
  local locked
  local owner
  local auth="no"
  local last

  if [[ ",$admin_users," == *",$user,"* ]]; then
    admin="yes"
  fi

  locked=$(get_lock_state "$user")
  owner=$(get_home_owner "$home")

  if has_authorized_keys "$home"; then
    auth="yes"
  fi

  last=$(get_last_login "$user")

  if [[ "$CSV" == true ]]; then
    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$user" "$uid" "$shell" "$admin" "$locked" "$owner" "$auth" "$last"
  else
    printf '%-18s %-8s %-22s %-8s %-8s %-16s %-15s %s\n' \
      "$user" "$uid" "$shell" "$admin" "$locked" "$owner" "$auth" "$last"
  fi
}

main() {
  parse_args "$@"

  local admin_users
  admin_users=$(get_admin_users)

  print_header

  while IFS=: read -r user _ uid _ _ home shell; do
    if [[ "$INCLUDE_SYSTEM" != true && "$uid" -lt 1000 ]]; then
      continue
    fi

    if [[ "$INCLUDE_SYSTEM" != true && "$shell" =~ (nologin|false)$ ]]; then
      continue
    fi

    print_user "$user" "$uid" "$home" "$shell" "$admin_users"
  done < /etc/passwd
}

main "$@"