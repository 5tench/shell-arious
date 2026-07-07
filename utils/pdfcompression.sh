#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'HELP'
Summary:
  Compress a PDF with Ghostscript using a simple quality preset.

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

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

die() {
  echo "error: $*" >&2
  exit 2
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
  show_help >&2
  exit 2
fi

input="$1"
output="$2"
quality="${3:-ebook}"

if [[ ! -f "$input" ]]; then
  die "input PDF not found: $input"
fi

if [[ "$input" == "$output" ]]; then
  die "input and output paths must be different"
fi

output_dir="$(dirname -- "$output")"
if [[ "$output_dir" != "." && ! -d "$output_dir" ]]; then
  die "output directory not found: $output_dir"
fi

case "$quality" in
  screen|ebook|printer|prepress)
    ;;
  *)
    die "unsupported quality: $quality"
    ;;
esac

if ! command_exists gs; then
  echo "error: Ghostscript is required. Install the ghostscript package first." >&2
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