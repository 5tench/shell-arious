#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'HELP'
Summary:
  Prints filesystem usage and largest entries under a path.

Usage:
  disk-usage-report.sh [path] [top_count]

Examples:
  ./utils/disk-usage-report.sh
  ./utils/disk-usage-report.sh /var/log 15

Notes:
  Read-only. Does not delete or modify files.
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

TARGET_PATH="${1:-.}"
TOP_COUNT="${2:-10}"

if [[ ! -d "$TARGET_PATH" ]]; then
  echo "Path not found or not a directory: $TARGET_PATH" >&2
  exit 1
fi

if [[ ! "$TOP_COUNT" =~ ^[0-9]+$ ]]; then
  echo "Top count must be a number." >&2
  exit 2
fi

echo "Disk usage report"
echo "Path: $TARGET_PATH"
echo "Top entries: $TOP_COUNT"
echo

echo "Filesystem space:"
df -h "$TARGET_PATH"
echo

echo "Largest items directly under $TARGET_PATH:"
du -ah --max-depth=1 "$TARGET_PATH" 2>/dev/null \
  | sort -hr \
  | head -n "$TOP_COUNT"