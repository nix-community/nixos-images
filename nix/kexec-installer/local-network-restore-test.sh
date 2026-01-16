#!/usr/bin/env -S nix shell --inputs-from .# nixos-unstable#bash nixos-unstable#iproute2 nixos-unstable#findutils nixos-unstable#coreutils nixos-unstable#python3 nixos-unstable#jq --command bash

set -eu
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# This script can be used to see what network configuration would be restored by the restore_routes.py script for the current system.

iproute2Dump() {
  mkdir iproute2
  ip --json addr > iproute2/addrs.json
  ip -4 --json route > iproute2/routes-v4.json
  ip -6 --json route > iproute2/routes-v6.json
}
systemdMajorVersion() {
  version="$(
    busctl \
      --system \
      --json=pretty \
      get-property \
      org.freedesktop.systemd1 \
      /org/freedesktop/systemd1 \
      org.freedesktop.systemd1.Manager \
      Version | jq -r '.data'
  )"
  printf "%s" "${version%%.*}"
}
networkdDump() {
  mkdir -p networkd/iface
  networkctl list --json=pretty >  networkd/list.json
  for iface in $(cat networkd/list.json  | jq -r '.Interfaces.[] | select(.AdministrativeState == "configured") | .Name'); do
    for type in netdev link network; do
      conf="networkd/iface/00-$iface.$type"
      networkctl cat "@$iface:$type" > "$conf" || true
      if ! [ -s "$conf" ]; then
        rm "$conf"
      fi
    done
  done
}

dump_dir=$(mktemp -d)
output_dir=$(mktemp -d)
trap "cd - ; rm -rf $dump_dir ; rm -rf $output_dir" EXIT

cd "$dump_dir"
if command -v networkctl > /dev/null &&
  command -v busctl > /dev/null &&
  systemctl is-active systemd-networkd --quiet &&
  [ "$(systemdMajorVersion)" -ge "257" ] ; then
  networkdDump
fi
iproute2Dump

python3 \
  "$SCRIPT_DIR/restore_routes.py" \
  "$dump_dir/iproute2/addrs.json" \
  "$dump_dir/iproute2/routes-v4.json" \
  "$dump_dir/iproute2/routes-v6.json" \
  "$dump_dir/networkd/list.json" \
  "$dump_dir/networkd/iface" \
  "$output_dir"
ls -la "$output_dir"

find "$output_dir" -type f -print0 | while IFS= read -r -d '' file; do
  echo -e "\033[0;31m$(basename "$file")\033[0m"
  case "$file" in
    *.json) jq . "$file" ;;
    *) cat "$file" ;;
  esac
  echo ""
done
