#!/usr/bin/env nix-shell
#!nix-shell -p nix -p coreutils -p bash -p gh -i bash
# shellcheck shell=bash
set -xeuo pipefail
shopt -s lastpipe

build_netboot_image() {
  declare -r tag=$1 arch=$2 tmp=$3
  img=$(nix build --print-out-paths --option accept-flake-config true -L ".#packages.${arch}.netboot-${tag//.}")
  ln -s "$img/bzImage" "$tmp/bzImage-$arch"
  echo "$tmp/bzImage-$arch"
  ln -s "$img/initrd" "$tmp/initrd-$arch"
  echo "$tmp/initrd-$arch"
  sed -e "s!^kernel bzImage!kernel https://github.com/nix-community/nixos-images/releases/download/${tag}/bzImage-${arch}!" \
    -e "s!^initrd initrd!initrd https://github.com/nix-community/nixos-images/releases/download/${tag}/initrd-${arch}!" \
    -e "s!initrd=initrd!initrd=initrd-${arch}!" \
    < "$img/netboot.ipxe" \
    > "$tmp/netboot-$arch.ipxe"
  echo "$tmp/netboot-$arch.ipxe"
}

build_kexec_installer() {
  declare -r tag=$1 arch=$2 tmp=$3
  out=$(nix build --print-out-paths --option accept-flake-config true -L ".#packages.${arch}.kexec-installer-${tag//.}")
  echo "$out/nixos-kexec-installer-$arch.tar.gz"
}

main() {
  declare -r tag=${1:-nixos-unstable} arch=${2:-x86_64-linux}
  tmp="$(mktemp -d)"
  trap 'rm -rf -- "$tmp"' EXIT
  (
    build_kexec_installer "$tag" "$arch" "$tmp"
    build_netboot_image "$tag" "$arch" "$tmp"
  ) | readarray -t assets
  for asset in "${assets[@]}"; do
    pushd "$(dirname "$asset")"
    sha256sum "$(basename "$asset")" >> "$TMP/sha256sums"
    popd
  done
  assets+=("$TMP/sha256sums")

  # Since we cannot atomically update a release, we delete the old one before
  gh release delete "$tag" </dev/null || true
  gh release create --title "$tag (build $(date +"%Y-%m-%d"))" "$tag" "${assets[@]}" </dev/null
}

main "$@"
