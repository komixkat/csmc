#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${SERVER_DIR:-$SCRIPT_DIR/server}"

if [ ! -d "$SERVER_DIR" ]; then
    printf '\033[1;33m[WARN]\033[0m No server found at %s, nothing to reset\n' "$SERVER_DIR" >&2
    exit 0
fi

stamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$SCRIPT_DIR/backups/server-$stamp"

printf '\033[1;34m[RESET]\033[0m Moving %s to %s\n' "$SERVER_DIR" "$backup_dir" >&2
mkdir -p "$SCRIPT_DIR/backups"
mv "$SERVER_DIR" "$backup_dir"
rm -f "$SCRIPT_DIR/start.sh"

printf '\033[1;32m[OK]\033[0m Old server backed up to %s\n' "$backup_dir" >&2
printf '\033[1;32m[OK]\033[0m Clean start ready\n' >&2
printf '\033[1;32m[OK]\033[0m Re-run scripts/setup.sh to install a fresh server\n' >&2