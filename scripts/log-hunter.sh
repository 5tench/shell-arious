#!/usr/bin/env bash
set -euo pipefail

PATH_TO_SEARCH="."
PATTERN=""
FILE_PATTERN="*.log"
IGNORE_CASE=false
CONTEXT=0
TOP=false
JOURNAL=false
UNIT=""
SINCE="today"
OUTPUT=""

show_help() {
  cat <<'HELP'
Summary:
  Search files or journal logs with useful defaults for troubleshooting.

Usage:
  log-hunter.sh --pattern regex [--path dir|--journal] [--unit name] [--since time]

Examples:
  ./scripts/log-hunter.sh --path /var/log --pattern "error|failed"
  ./scripts/log-hunter.sh --path /var/log/nginx --pattern " 500 " --top
  ./scripts/log-hunter.sh --journal --unit sshd --since today --pattern "Failed password"

Notes:
  Read-only. File search defaults to the current directory unless --journal is used.
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
      --path)
        PATH_TO_SEARCH="${2:-}"
        [[ -n "$PATH_TO_SEARCH" ]] || die "--path requires a directory"
        shift 2
        ;;
      --pattern)
        PATTERN="${2:-}"
        [[ -n "$PATTERN" ]] || die "--pattern requires a value"
        shift 2
        ;;
      --file-pattern)
        FILE_PATTERN="${2:-}"
        [[ -n "$FILE_PATTERN" ]] || die "--file-pattern requires a value"
        shift 2
        ;;
      --case-insensitive)
        IGNORE_CASE=true
        shift
        ;;
      --context)
        CONTEXT="${2:-0}"
        [[ "$CONTEXT" =~ ^[0-9]+$ ]] || die "--context must be numeric"
        shift 2
        ;;
      --top)
        TOP=true
        shift
        ;;
      --journal)
        JOURNAL=true
        shift
        ;;
      --unit)
        UNIT="${2:-}"
        [[ -n "$UNIT" ]] || die "--unit requires a value"
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
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done

  [[ -n "$PATTERN" ]] || die "--pattern is required"
}

build_grep_options() {
  GREP_OPTIONS=(-E -n)

  if [[ "$IGNORE_CASE" == true ]]; then
    GREP_OPTIONS+=(-i)
  fi

  if [[ "$CONTEXT" != "0" ]]; then
    GREP_OPTIONS+=(-C "$CONTEXT")
  fi
}

search_journal() {
  command_exists journalctl || die "journalctl not available"

  local journal_args=(--since "$SINCE" --no-pager)

  if [[ -n "$UNIT" ]]; then
    journal_args+=(-u "$UNIT")
  fi

  journalctl "${journal_args[@]}" \
    | grep "${GREP_OPTIONS[@]}" -- "$PATTERN" || true
}

search_files() {
  [[ -d "$PATH_TO_SEARCH" ]] || die "path not found: $PATH_TO_SEARCH"

  find "$PATH_TO_SEARCH" -type f -name "$FILE_PATTERN" -print0 2>/dev/null \
    | xargs -0 grep "${GREP_OPTIONS[@]}" -- "$PATTERN" 2>/dev/null || true
}

produce_results() {
  if [[ "$JOURNAL" == true ]]; then
    search_journal
  else
    search_files
  fi
}

main() {
  parse_args "$@"
  build_grep_options

  if [[ "$TOP" == true ]]; then
    produce_results \
      | awk -F: '{print $1}' \
      | sort \
      | uniq -c \
      | sort -nr \
      | head -20
  elif [[ -n "$OUTPUT" ]]; then
    produce_results | tee "$OUTPUT"
  else
    produce_results
  fi
}

main "$@"