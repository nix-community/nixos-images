#!/usr/bin/env nix-shell
#!nix-shell -p nix -p coreutils -p bash -p gh -i bash
set -xeuo pipefail

build_netboot_image() {
  tag=$1
  arch=$2
  tmp=$3
  img=$(nix-build --no-out-link -I "nixpkgs=https://github.com/NixOS/nixpkgs/archive/${tag}.tar.gz" '<nixpkgs/nixos/release.nix>' -A "netboot.$arch")
  cp "$(readlink $img/bzImage)" "$tmp/bzImage-$arch"
  echo "$tmp/bzImage-$arch"
  cp "$(readlink $img/initrd)" "$tmp/initrd-$arch"
  echo "$tmp/initrd-$arch"
}

main() {
  tag=${1:-nixos-unstable}
  arch=${2:-x86_64-linux}
  sha256s=()
  tmp="$(mktemp -d)"
  trap 'rm -rf -- "$tmp"' EXIT
  assets=($(build_netboot_image "$tag" "$arch" "$tmp"))

  for asset in "${assets[@]}"; do
    pushd "$(dirname $asset)"
    sha256sum "$(basename $asset)" > "$TMP/sha256sums"
    popd
  done
  assets+=("$TMP/sha256sums")

  # Since we cannot atomically update a release, we delete the old one before
  gh release delete "$tag" </dev/null || true
  gh release create --title "$tag (build $(date +"%Y-%m-%d"))" "$tag" "${assets[@]}" </dev/null
}

main "$@"
