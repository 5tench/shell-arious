#!/usr/bin/env bash
set -euo pipefail

HOST=""
HOST_FILE=""
PORT=443
WARN_DAYS=30

show_help() {
  cat <<'HELP'
Summary:
  Check TLS certificate expiration for one host or a file of hosts.

Usage:
  cert-check.sh <host> [--port port] [--warn-days days]
  cert-check.sh --file hosts.txt [--port port] [--warn-days days]

Examples:
  ./scripts/cert-check.sh google.com
  ./scripts/cert-check.sh internal.example.com --port 8443
  ./scripts/cert-check.sh --file hosts.txt --warn-days 30

Notes:
  Uses openssl. Does not require root.
HELP
}

die() {
  echo "error: $*" >&2
  exit 2
}

require_openssl() {
  command -v openssl >/dev/null 2>&1 || die "openssl is required"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)
        HOST_FILE="${2:-}"
        [[ -n "$HOST_FILE" ]] || die "--file requires a path"
        shift 2
        ;;
      --port)
        PORT="${2:-}"
        [[ "$PORT" =~ ^[0-9]+$ ]] || die "--port must be numeric"
        shift 2
        ;;
      --warn-days)
        WARN_DAYS="${2:-}"
        [[ "$WARN_DAYS" =~ ^[0-9]+$ ]] || die "--warn-days must be numeric"
        shift 2
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        [[ -z "$HOST" ]] || die "only one host is allowed unless --file is used"
        HOST="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$HOST" && -z "$HOST_FILE" ]]; then
    die "host or --file is required"
  fi

  if [[ -n "$HOST_FILE" && ! -f "$HOST_FILE" ]]; then
    die "file not found: $HOST_FILE"
  fi
}

read_certificate() {
  local host="$1"
  local port="$2"

  echo \
    | openssl s_client -servername "$host" -connect "$host:$port" 2>/dev/null \
    | openssl x509 -noout -issuer -subject -enddate 2>/dev/null
}

check_host() {
  local host="$1"
  local port="$2"
  local cert
  local end_date
  local issuer
  local subject
  local expire_epoch
  local now_epoch
  local days_remaining
  local status="ok"

  if ! cert=$(read_certificate "$host" "$port"); then
    echo "$host:$port unable_to_read_certificate"
    return 1
  fi

  end_date=$(printf '%s\n' "$cert" | awk -F= '/notAfter/ { print $2 }')
  issuer=$(printf '%s\n' "$cert" | awk -F'issuer=' '/issuer=/ { print $2 }')
  subject=$(printf '%s\n' "$cert" | awk -F'subject=' '/subject=/ { print $2 }')

  expire_epoch=$(date -d "$end_date" +%s 2>/dev/null || echo 0)
  now_epoch=$(date +%s)
  days_remaining=$(( (expire_epoch - now_epoch) / 86400 ))

  if [[ "$days_remaining" -le "$WARN_DAYS" ]]; then
    status="warning"
  fi

  printf '%s:%s | days=%s | status=%s | expires=%s | issuer=%s | subject=%s\n' \
    "$host" "$port" "$days_remaining" "$status" "$end_date" "$issuer" "$subject"
}

main() {
  parse_args "$@"
  require_openssl

  if [[ -n "$HOST_FILE" ]]; then
    while IFS= read -r host; do
      [[ -z "$host" || "$host" =~ ^# ]] && continue
      check_host "$host" "$PORT" || true
    done < "$HOST_FILE"
  else
    check_host "$HOST" "$PORT"
  fi
}

main "$@"