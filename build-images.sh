#!/usr/bin/env nix-shell
#!nix-shell -p nixos-generators -p nix -p coreutils -p bash -p gh -i bash
# shellcheck shell=bash
set -xeuo pipefail

build_netboot_image() {
  declare -r tag=$1 arch=$2 tmp=$3 attr=${4:-netboot} suffix=${5:-}
  img=$(nix-build --no-out-link -I "nixpkgs=https://github.com/NixOS/nixpkgs/archive/${tag}.tar.gz" '<nixpkgs/nixos/release.nix>' -A "$attr.$arch")
  ln -s "$img/bzImage" "$tmp/bzImage$suffix-$arch"
  echo "$tmp/bzImage$suffix-$arch"
  ln -s "$img/initrd" "$tmp/initrd$suffix-$arch"
  echo "$tmp/initrd$suffix-$arch"
  sed -e "s!^kernel bzImage!kernel https://github.com/nix-community/nixos-images/releases/download/${tag}/bzImage${suffix}-${arch}!" \
    -e "s!^initrd initrd!initrd https://github.com/nix-community/nixos-images/releases/download/${tag}/initrd${suffix}-${arch}!" \
    -e "s!initrd=initrd!initrd=initrd$suffix-${arch}!" \
    < "$img/netboot.ipxe" \
    > "$tmp/netboot$suffix-$arch.ipxe"
  echo "$tmp/netboot$suffix-$arch.ipxe"
}

build_gnome_netboot_image() {
  build_netboot_image "$@" "netboot_gnome" "-gnome"
}

build_plasma5_netboot_image() {
  build_netboot_image "$@" "netboot_plasma5" "-plasma5"
}

build_kexec_bundle() {
  declare -r tag=$1 arch=$2 tmp=$3
  # the default configuration conflicts with the kexec bundle configuration
  echo "{}" > "$tmp/config.nix"
  nixos-generate -o "$tmp/kexec-bundle-$arch" -c "$tmp/config.nix" -f kexec-bundle -I "nixpkgs=https://github.com/NixOS/nixpkgs/archive/${tag}.tar.gz"
  echo "$tmp/kexec-bundle-$arch"
}

main() {
  declare -r tag=${1:-nixos-unstable} arch=${2:-x86_64-linux}
  tmp="$(mktemp -d)"
  trap 'rm -rf -- "$tmp"' EXIT
  readarray -t assets < <(
    build_kexec_bundle "$tag" "$arch" "$tmp"
    build_netboot_image "$tag" "$arch" "$tmp"
    build_gnome_netboot_image "$tag" "$arch" "$tmp"
    build_plasma5_netboot_image "$tag" "$arch" "$tmp"
  )

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
