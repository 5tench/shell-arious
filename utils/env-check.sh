#!/usr/bin/env bash
# ---
# Summary: Checks whether common DevOps tools are installed and available in PATH.
# Changes: None. This is read-only.
# Run: ./utils/env-check.sh or ./utils/env-check.sh git docker terraform
# ---

set -euo pipefail

show_help() {
    cat <<'HELP'
Usage: env-check.sh [tool ...]

Checks whether common DevOps and workstation tools are available in PATH.
If no tools are provided, a default list is checked.
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ $# -gt 0 ]]; then
    tools=("$@")
else
    tools=(git curl wget jq yq docker podman terraform aws kubectl helm python3 bash shellcheck)
fi

missing=0
printf '%-16s %s\n' "Tool" "Status"
printf '%-16s %s\n' "----" "------"

for tool in "${tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf '%-16s found (%s)\n' "$tool" "$(command -v "$tool")"
    else
        printf '%-16s missing\n' "$tool"
        missing=$((missing + 1))
    fi
done

if [[ $missing -gt 0 ]]; then
    echo ""
    echo "Missing tools: $missing"
    exit 1
fi

echo ""
echo "All checked tools are available."