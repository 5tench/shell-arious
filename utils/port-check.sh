#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'HELP'
Summary:
  Checks whether a local TCP port is listening.

Usage:
  port-check.sh <port>

Examples:
  ./utils/port-check.sh 22
  ./utils/port-check.sh 8080

Notes:
  Read-only. Uses ss when available and falls back to netstat.
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

port="${1:-}"

if [[ -z "$port" || ! "$port" =~ ^[0-9]+$ || "$port" -lt 1 || "$port" -gt 65535 ]]; then
  echo "Provide a valid TCP port from 1 to 65535." >&2
  show_help >&2
  exit 2
fi

port_is_listening_from() {
  local command_name="$1"
  local port_pattern=":$port"

  "$command_name" -ltnp 2>/dev/null | awk -v port="$port_pattern" '
    $4 ~ port "$" {
      found = 1
      print
    }
    END {
      exit found ? 0 : 1
    }
  '
}

echo "Checking local TCP port: $port"

if command -v ss >/dev/null 2>&1; then
  if port_is_listening_from ss; then
    echo "Port $port is listening."
    exit 0
  fi
elif command -v netstat >/dev/null 2>&1; then
  if port_is_listening_from netstat; then
    echo "Port $port is listening."
    exit 0
  fi
else
  echo "Neither ss nor netstat is available." >&2
  exit 3
fi

echo "Port $port does not appear to be listening locally."
exit 1