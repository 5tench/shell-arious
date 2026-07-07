#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'HELP'
Summary:
  Compresses a PDF using Ghostscript.

Usage:
  pdfcompression.sh <input.pdf> <output.pdf> [quality]

Examples:
  ./utils/pdfcompression.sh input.pdf output.pdf
  ./utils/pdfcompression.sh input.pdf output.pdf screen

Notes:
  Writes a new output PDF and does not modify the input file.
  Quality options: screen, ebook, printer, prepress.
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

input="${1:-}"
output="${2:-}"
quality="${3:-ebook}"

if [[ -z "$input" || -z "$output" ]]; then
  show_help >&2
  exit 2
fi

if [[ ! -f "$input" ]]; then
  echo "Input PDF not found: $input" >&2
  exit 1
fi

case "$quality" in
  screen|ebook|printer|prepress)
    ;;
  *)
    echo "Unsupported quality: $quality" >&2
    exit 2
    ;;
esac

if ! command -v gs >/dev/null 2>&1; then
  echo "Ghostscript is required. Install the ghostscript package first." >&2
  exit 1
fi

gs -sDEVICE=pdfwrite \
  -dCompatibilityLevel=1.4 \
  -dPDFSETTINGS="/$quality" \
  -dNOPAUSE \
  -dQUIET \
  -dBATCH \
  -sOutputFile="$output" \
  "$input"

echo "Compressed PDF written to: $output"