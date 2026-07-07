#!/usr/bin/env bash
# ---
# Summary: Prints filesystem usage and largest entries under a path.
# Changes: None. This is read-only.
# Run: ./utils/disk-usage-report.sh [path] [top_count]
# ---

set -euo pipefail

# disk-usage-report.sh
# A small read-only helper for checking disk usage from the command line.
# Usage: ./disk-usage-report.sh [path] [top_count]

TARGET_PATH="${1:-.}"
TOP_COUNT="${2:-10}"

if [ ! -d "$TARGET_PATH" ]; then
    echo "Path not found or not a directory: $TARGET_PATH" >&2
    exit 1
fi

if ! [[ "$TOP_COUNT" =~ ^[0-9]+$ ]]; then
    echo "Top count must be a number." >&2
    exit 1
fi

echo "Disk usage report"
echo "Path: $TARGET_PATH"
echo "Top entries: $TOP_COUNT"
echo ""

echo "Filesystem space:"
df -h "$TARGET_PATH"
echo ""

echo "Largest items directly under $TARGET_PATH:"
du -ah --max-depth=1 "$TARGET_PATH" 2>/dev/null | sort -hr | head -n "$TOP_COUNT"
echo ""

echo "Tip: rerun with a specific path, for example:"
echo "  ./utils/disk-usage-report.sh /var/log 15"