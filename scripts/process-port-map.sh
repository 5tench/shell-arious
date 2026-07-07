#!/usr/bin/env bash
set -euo pipefail

PORT=""
PROCESS=""
JSON=false
SOURCE_TOOL=""

show_help() {
  cat <<'HELP'
Summary:
  Map listening TCP ports to processes.

Usage:
  process-port-map.sh [--port port] [--process name] [--json]

Examples:
  ./scripts/process-port-map.sh
  ./scripts/process-port-map.sh --port 8080
  ./scripts/process-port-map.sh --process nginx

Notes:
  Read-only. Prefers ss, then netstat, then lsof when available.
HELP
}

die() {
  echo "error: $*" >&2
  exit 2
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        PORT="${2:-}"
        [[ "$PORT" =~ ^[0-9]+$ ]] || die "--port must be numeric"
        shift 2
        ;;
      --process)
        PROCESS="${2:-}"
        [[ -n "$PROCESS" ]] || die "--process requires a value"
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

collect_with_ss() {
  SOURCE_TOOL="ss"
  ss -ltnp 2>/dev/null || true
}

collect_with_netstat() {
  SOURCE_TOOL="netstat"
  netstat -ltnp 2>/dev/null || true
}

collect_with_lsof() {
  SOURCE_TOOL="lsof"
  lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null || true
}

collect_ports() {
  if command_exists ss; then
    collect_with_ss
  elif command_exists netstat; then
    collect_with_netstat
  elif command_exists lsof; then
    collect_with_lsof
  else
    die "ss, netstat, or lsof is required"
  fi
}

filter_results() {
  local data="$1"

  if [[ -n "$PORT" ]]; then
    data=$(printf '%s\n' "$data" | grep -E "(^|[:.])$PORT([[:space:]]|$)|PID|COMMAND|State" || true)
  fi

  if [[ -n "$PROCESS" ]]; then
    data=$(printf '%s\n' "$data" | grep -Ei "PID|COMMAND|State|$PROCESS" || true)
  fi

  printf '%s\n' "$data"
}

print_json() {
  awk -v source="$SOURCE_TOOL" '
    NR > 1 {
      gsub(/"/, "\\\"")
      printf "%s{\"source\":\"%s\",\"line\":\"%s\"}", sep, source, $0
      sep=","
    }
    END { print "" }
  ' | awk '{ print "[" $0 "]" }'
}

main() {
  parse_args "$@"

  local data
  data=$(collect_ports)
  data=$(filter_results "$data")

  if [[ "$JSON" == true ]]; then
    printf '%s\n' "$data" | print_json
  else
    echo "source: $SOURCE_TOOL"
    printf '%s\n' "$data"
  fi
}

main "$@"