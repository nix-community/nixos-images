#!/usr/bin/env -S nix shell --inputs-from .# nixos-unstable#bash nixos-unstable#iproute2 nixos-unstable#findutils nixos-unstable#coreutils nixos-unstable#python3 nixos-unstable#jq --command bash

set -eu
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# This script can be used to see what network configuration would be restored by the restore_routes.py script for the current system.

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT
ip --json address >"$tmp/addrs.json"
ip -6 --json route >"$tmp/routes-v6.json"
ip -4 --json route >"$tmp/routes-v4.json"
python3 "$SCRIPT_DIR/restore_routes.py" "$tmp/addrs.json" "$tmp/routes-v4.json" "$tmp/routes-v6.json" "$tmp"
ls -la "$tmp"

find "$tmp" -type f -name "*.json" -print0 | while IFS= read -r -d '' file; do
  echo -e "\033[0;31m$(basename "$file")\033[0m"
  jq . "$file"
  echo ""
done

find "$tmp" -type f -name "*.network" -print0 | while IFS= read -r -d '' file; do
  echo -e "\033[0;31m$(basename "$file")\033[0m"
  cat "$file"
  echo ""
done
