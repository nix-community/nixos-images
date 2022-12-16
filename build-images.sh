#!/usr/bin/env nix-shell
#!nix-shell -p nixos-generators -p nix -p coreutils -p bash -p gh -i bash
# shellcheck shell=bash
set -xeuo pipefail
shopt -s lastpipe

build_netboot_image() {
  declare -r tag=$1 arch=$2 tmp=$3
  img=$(nix-build --no-out-link -I "nixpkgs=https://github.com/NixOS/nixpkgs/archive/${tag}.tar.gz" '<nixpkgs/nixos/release.nix>' -A "netboot.$arch")
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
  # run the test once we have kvm support in github actions
  # ignore=$(nix-build ./nix/kexec-installer/test.nix -I "nixpkgs=https://github.com/NixOS/nixpkgs/archive/${tag}.tar.gz" --argstr system "$arch")
  out=$(nix-build '<nixpkgs/nixos>' -o "$tmp/kexec-installer-$arch" -I nixos-config=./nix/kexec-installer/module.nix -I "nixpkgs=https://github.com/NixOS/nixpkgs/archive/${tag}.tar.gz" --argstr system "$arch" -A config.system.build.kexecTarball)
  echo "$out/nixos-kexec-installer-$arch.tar.gz"
}

main() {
  declare -r tag=${1:-nixos-unstable} arch=${2:-x86_64-linux}
  tmp="$(mktemp -d)"
  trap 'rm -rf -- "$tmp"' EXIT
  (
    build_kexec_installer "$tag" "$arch" "$tmp"
    build_kexec_bundle "$tag" "$arch" "$tmp"
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
