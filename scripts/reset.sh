#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${SERVER_DIR:-$SCRIPT_DIR/server}"

stamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$SCRIPT_DIR/backups/world-$stamp"

worlds=()
for name in world world_nether world_the_end; do
    [ -d "$SERVER_DIR/$name" ] && worlds+=("$name")
done

if [ "${#worlds[@]}" -eq 0 ]; then
    printf '\033[1;33m[WARN]\033[0m No world found in %s, nothing to reset\n' "$SERVER_DIR" >&2
    exit 0
fi

printf '\033[1;34m[RESET]\033[0m Backing up old world to %s\n' "$backup_dir" >&2
mkdir -p "$backup_dir"
for name in "${worlds[@]}"; do
    mv "$SERVER_DIR/$name" "$backup_dir/$name"
done
printf '\033[1;32m[OK]\033[0m Old world moved to backup\n' >&2

printf '\033[1;34m[RESET]\033[0m Reset complete\n' >&2
printf '\033[1;32m[OK]\033[0m A fresh world will generate from the configured seed on the next start\n' >&2
printf '\033[1;32m[OK]\033[0m Start with %s/start.sh when ready\n' "$SERVER_DIR" >&2