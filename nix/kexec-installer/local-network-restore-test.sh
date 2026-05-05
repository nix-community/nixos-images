#!/usr/bin/env -S nix shell --inputs-from .# nixos-unstable#bash nixos-unstable#iproute2 nixos-unstable#findutils nixos-unstable#coreutils nixos-unstable#python3 nixos-unstable#jq --command bash

set -eu
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# This script can be used to see what network configuration would be restored by the restore_routes.py script for the current system.

iproute2Dump() {
  mkdir iproute2
  ip --json addr >iproute2/addrs.json
  ip -4 --json route >iproute2/routes-v4.json
  ip -6 --json route >iproute2/routes-v6.json
}

systemdMajorVersion() {
  version="$(
    busctl \
      --system \
      get-property \
      org.freedesktop.systemd1 \
      /org/freedesktop/systemd1 \
      org.freedesktop.systemd1.Manager \
      Version
  )"
  version="${version#s \"}"
  version="${version%\"}"
  version="${version%%\.*}"

  printf "%s" "$version"
}
networkctlParseIface() {
  # trim leading spapce
  trim="${1#"${1%%[![:space:]]*}"}"
  # trim iface number
  trim="${trim#"${trim%%[![:digit:]]*}"}"
  # trim leading spapce
  trim="${trim#"${trim%%[![:space:]]*}"}"
  # just get the interface
  trim="${trim%%[[:space:]]*}"

  printf '%s' "$trim"
}
networkdDump() {
  mkdir -p networkd/iface
  networkctl list --json=pretty >networkd/list.json

  networkctl list --no-legend | while read -r line; do
    iface="$(networkctlParseIface "$line")"
    state="${line##*[[:space:]]}"

    if [ "$state" != "configured" ] &&
      [ "$state" != "configuring" ]; then
      continue
    fi

    for type in netdev link network; do
      conf="networkd/iface/00-$iface.$type"
      networkctl cat "@$iface:$type" >"$conf" || true
      if ! [ -s "$conf" ]; then
        rm "$conf"
      fi
    done
  done
}
depCheck() {
  for dep; do
    command -v "$dep" 1>/dev/null ||
      return 127
  done
  return 0
}

dump_dir=$(mktemp -d)
output_dir=$(mktemp -d)
trap "cd - ; rm -rf $dump_dir ; rm -rf $output_dir" EXIT

cd "$dump_dir"
if depCheck networkctl busctl systemctl &&
  systemctl is-active systemd-networkd --quiet &&
  [ "$(systemdMajorVersion)" -ge "257" ]; then
  # networkctl cat "@$iface:*" was added in systemd v257
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
