#!/usr/bin/env bash
# ---
# Summary: Searches and samples text files in a directory.
# Changes: None. This is read-only.
# Run: ./scripts/text-explorer.sh <directory> <pattern> [field] [delimiter] [file_pattern]
# ---

set -euo pipefail

show_help() {
    cat <<'HELP'
Usage: text-explorer.sh <directory> <search_pattern> [field_number] [delimiter] [file_pattern]

Examples:
  ./scripts/text-explorer.sh /var/log "ERROR|WARN" "" " " "*.log"
  ./scripts/text-explorer.sh ./logs "failed" 3 "," "*.csv"
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ $# -lt 2 ]]; then
    show_help >&2
    exit 2
fi

DIR="$1"
PATTERN="$2"
FIELD="${3:-}"
DELIM="${4:- }"
FILEPAT="${5:-*}"

if [[ ! -d "$DIR" ]]; then
    echo "Directory not found: $DIR" >&2
    exit 1
fi

echo "Directory explorer: $DIR"
echo "Pattern: $PATTERN | Field: ${FIELD:-none} | Files: $FILEPAT"
echo ""

echo "Found files:"
find "$DIR" -name "$FILEPAT" -type f | head -10
file_count=$(find "$DIR" -name "$FILEPAT" -type f | wc -l | tr -d ' ')
echo "Total: $file_count files"
echo ""

echo "Quick sample from first 3 files:"
find "$DIR" -name "$FILEPAT" -type f | head -3 | while IFS= read -r file; do
    echo "--- $file ---"
    head -2 "$file" || true
done

echo ""
echo "Search results:"
if [[ -z "$FIELD" ]]; then
    find "$DIR" -name "$FILEPAT" -type f -print0 | xargs -0 grep -EHi "$PATTERN" 2>/dev/null | sort -u || true
else
    find "$DIR" -name "$FILEPAT" -type f -print0 | xargs -0 grep -EHi "$PATTERN" 2>/dev/null | cut -d "$DELIM" -f "$FIELD" | sort -u || true
fi