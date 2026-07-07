#!/usr/bin/env bash
set -euo pipefail

SERVICE=""
UNIT=""
SINCE="1 hour ago"
LOGS=80

show_help() {
  cat <<'HELP'
Summary:
  Diagnose a systemd service without restarting or modifying it.

Usage:
  service-doctor.sh <service> [--since time] [--logs number]

Examples:
  ./scripts/service-doctor.sh nginx
  ./scripts/service-doctor.sh sshd --since "30 min ago"
  ./scripts/service-doctor.sh cron --logs 100

Notes:
  Read-only. Handles common service name differences such as ssh/sshd,
  cron/crond, and apache2/httpd when systemd is available.
HELP
}

die() {
  echo "error: $*" >&2
  exit 2
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

print_section() {
  echo
  echo "== $* =="
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since)
        SINCE="${2:-}"
        [[ -n "$SINCE" ]] || die "--since requires a value"
        shift 2
        ;;
      --logs)
        LOGS="${2:-}"
        [[ "$LOGS" =~ ^[0-9]+$ ]] || die "--logs must be numeric"
        shift 2
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        [[ -z "$SERVICE" ]] || die "only one service name is supported"
        SERVICE="$1"
        shift
        ;;
    esac
  done

  [[ -n "$SERVICE" ]] || die "service name required"
}

candidate_units() {
  case "$SERVICE" in
    ssh|sshd)
      printf '%s\n' sshd ssh
      ;;
    cron|crond)
      printf '%s\n' cron crond
      ;;
    apache|apache2|httpd)
      printf '%s\n' apache2 httpd
      ;;
    *)
      printf '%s\n' "$SERVICE"
      ;;
  esac
}

resolve_unit() {
  local candidate

  while IFS= read -r candidate; do
    if systemctl list-unit-files --type=service --no-legend 2>/dev/null \
      | awk '{print $1}' \
      | grep -qx "${candidate}.service\|${candidate}"; then
      UNIT="$candidate"
      return 0
    fi
  done < <(candidate_units)

  UNIT="$SERVICE"
  return 1
}

print_unit_summary() {
  print_section "unit"

  if ! resolve_unit; then
    echo "service not found in unit files: $SERVICE"
    echo "trying requested name anyway: $UNIT"
  elif [[ "$UNIT" != "$SERVICE" ]]; then
    echo "resolved service name: $SERVICE -> $UNIT"
  fi

  systemctl status "$UNIT" --no-pager -l | sed -n '1,25p' || true
}

print_properties() {
  print_section "properties"

  systemctl show "$UNIT" \
    -p ActiveState \
    -p SubState \
    -p UnitFileState \
    -p MainPID \
    -p NRestarts \
    --no-pager 2>/dev/null || true
}

print_logs() {
  print_section "recent logs"

  if command_exists journalctl; then
    journalctl -u "$UNIT" --since "$SINCE" -n "$LOGS" --no-pager || true
  else
    echo "journalctl not available"
  fi
}

print_ports_for_service() {
  print_section "ports owned by service pid"

  if ! command_exists ss; then
    echo "ss not available"
    return 0
  fi

  local pid
  pid=$(systemctl show "$UNIT" -p MainPID --value 2>/dev/null || echo 0)

  if [[ -z "$pid" || "$pid" == "0" ]]; then
    echo "no main pid"
    return 0
  fi

  ss -ltnp 2>/dev/null | grep "pid=$pid," \
    || echo "no listening TCP ports found for main pid"
}

run_config_check() {
  print_section "known config checks"

  case "$SERVICE" in
    nginx)
      if command_exists nginx; then
        nginx -t || echo "nginx config test failed"
      else
        echo "nginx binary not available"
      fi
      ;;
    apache|apache2|httpd)
      if command_exists apachectl; then
        apachectl configtest || echo "apachectl config test failed"
      elif command_exists httpd; then
        httpd -t || echo "httpd config test failed"
      else
        echo "apache/httpd test tool not available"
      fi
      ;;
    ssh|sshd)
      if command_exists sshd; then
        sshd -t || echo "sshd config test failed"
      else
        echo "sshd binary not available"
      fi
      ;;
    docker)
      if command_exists docker; then
        docker info >/dev/null && echo "docker info succeeded" || echo "docker info failed"
      else
        echo "docker binary not available"
      fi
      ;;
    cron|crond)
      echo "no cron config test defined"
      ;;
    *)
      echo "no service-specific config test defined"
      ;;
  esac
}

main() {
  parse_args "$@"

  if ! command_exists systemctl; then
    echo "systemctl not available; this script only performs systemd diagnostics." >&2
    echo "service requested: $SERVICE"
    exit 3
  fi

  print_unit_summary
  print_properties
  print_logs
  print_ports_for_service
  run_config_check
}

main "$@"