#!/usr/bin/env bash
set -euo pipefail

SERVICES=""
SINCE="1 hour ago"
OUTPUT=""
JSON=false

show_help() {
  cat <<'HELP'
Summary:
  Quick read-only Linux health snapshot for first-pass triage.

Usage:
  system-triage.sh [--services name,name] [--since time] [--output file] [--json]

Examples:
  ./scripts/system-triage.sh
  ./scripts/system-triage.sh --services sshd,nginx,docker
  ./scripts/system-triage.sh --since "2 hours ago" --output report.txt
  ./scripts/system-triage.sh --json

Notes:
  Does not change the system. Some sections depend on optional tools like
  systemctl, ss, journalctl, and docker.
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

run_quiet() {
  echo "+ $*"
  "$@" 2>/dev/null || true
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --services)
        SERVICES="${2:-}"
        [[ -n "$SERVICES" ]] || die "--services requires a comma-separated value"
        shift 2
        ;;
      --since)
        SINCE="${2:-}"
        [[ -n "$SINCE" ]] || die "--since requires a value"
        shift 2
        ;;
      --output)
        OUTPUT="${2:-}"
        [[ -n "$OUTPUT" ]] || die "--output requires a file path"
        shift 2
        ;;
      --json)
        JSON=true
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

print_host_info() {
  print_section "host"
  echo "hostname: $(hostname)"

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "os: ${PRETTY_NAME:-unknown}"
  fi

  echo "kernel: $(uname -r)"
  run_quiet uptime
}

print_cpu_memory() {
  print_section "cpu and memory"
  echo "cpu_count: $(getconf _NPROCESSORS_ONLN 2>/dev/null || echo unknown)"
  run_quiet free -h
}

print_filesystems() {
  print_section "filesystems"
  run_quiet df -hT

  print_section "top disk consumers under /"
  du -xh --max-depth=1 / 2>/dev/null | sort -hr | head -10 || true
}

print_systemd_info() {
  print_section "failed systemd units"

  if command_exists systemctl; then
    systemctl --failed --no-pager || true
  else
    echo "systemctl not available"
  fi
}

print_ports() {
  print_section "listening ports"

  if command_exists ss; then
    ss -ltnp 2>/dev/null | head -30 || true
  else
    echo "ss not available"
  fi
}

print_processes() {
  print_section "top cpu processes"
  ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu | head -10

  print_section "top memory processes"
  ps -eo pid,user,comm,%cpu,%mem --sort=-%mem | head -10
}

print_journal_errors() {
  print_section "recent journal errors"

  if command_exists journalctl; then
    journalctl -p err --since "$SINCE" --no-pager -n 30 || true
  else
    echo "journalctl not available"
  fi
}

print_requested_services() {
  [[ -n "$SERVICES" ]] || return 0

  print_section "requested services"

  if ! command_exists systemctl; then
    echo "systemctl not available"
    return 0
  fi

  IFS=',' read -r -a service_list <<< "$SERVICES"
  for service in "${service_list[@]}"; do
    [[ -n "$service" ]] || continue
    systemctl status "$service" --no-pager -l | sed -n '1,12p' || true
  done
}

print_docker_info() {
  command_exists docker || return 0

  print_section "docker"
  docker info --format 'ServerVersion={{.ServerVersion}} Containers={{.Containers}} Running={{.ContainersRunning}}' 2>/dev/null \
    || echo "docker installed but not responding"
}

collect_text() {
  print_host_info
  print_cpu_memory
  print_filesystems
  print_systemd_info
  print_ports
  print_processes
  print_journal_errors
  print_requested_services
  print_docker_info
}

print_json() {
  printf '{"hostname":"%s","kernel":"%s","uptime":"%s"}\n' \
    "$(hostname)" \
    "$(uname -r)" \
    "$(uptime | sed 's/"//g')"
}

main() {
  parse_args "$@"

  if [[ "$JSON" == true ]]; then
    print_json
  elif [[ -n "$OUTPUT" ]]; then
    collect_text | tee "$OUTPUT"
  else
    collect_text
  fi
}

main "$@"