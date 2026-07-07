#!/bin/bash

# Usage: ./dir_explorer.sh <directory> <search_pattern> [field_number] [delimiter] [file_pattern]
# Example: ./dir_explorer.sh /var/log "ERROR|WARN" 2 " " "*.log"  
#          (All .log files, search ERROR|WARN, cut 2nd space-delimited field)

if [ $# -lt 2 ]; then
    echo "Usage: $0 <directory> <search_pattern> [field] [delim] [file_pattern]"
    echo "Example: $0 /var/log 'ERROR' 3 ',' '*.log'"
    exit 1
fi

DIR=$1
PATTERN=$2
FIELD=${3:-}  # Optional field to cut
DELIM=${4:- } # Default space delimiter
FILEPAT=${5:-"*"}  # Default: all files

echo "=== DIRECTORY EXPLORER: $DIR ==="
echo "Pattern: '$PATTERN' | Field: $FIELD | Files: $FILEPAT"
echo ""

# 1. DISCOVER: List files
echo "📁 Found files:"
find "$DIR" -name "$FILEPAT" -type f | head -10  # Show first 10
FILE_COUNT=$(find "$DIR" -name "$FILEPAT" -type f | wc -l)
echo "Total: $FILE_COUNT files"
echo ""

# 2. SUMMARY: Sample from first/last files
echo "=== QUICK SUMMARY (First 3 Files) ==="
find "$DIR" -name "$FILEPAT" | head -3 | xargs -I {} sh -c 'echo "=== {} ==="; head -2 {}'
echo ""
echo "=== LAST LINES (Last 3 Files) ==="
find "$DIR" -name "$FILEPAT" | tail -3 | xargs -I {} sh -c 'echo "=== {} ==="; tail -2 {}'
echo ""

# 3. SEARCH ACROSS ALL: grep + cut pipeline
echo "=== FULL SEARCH RESULTS ($PATTERN) ==="
if [ -z "$FIELD" ]; then
    # Search only, page results
    find "$DIR" -name "$FILEPAT" -exec egrep -l "$PATTERN" {} \; | \
    xargs egrep -i "$PATTERN" | sort -u | less
else
    # Search + cut field, page results
    find "$DIR" -name "$FILEPAT" -exec egrep -i "$PATTERN" {} \; | \
    cut -d "$DELIM" -f "$FIELD" | sort -u | less
fi

echo "=== Press 'q' to exit less viewer ==="