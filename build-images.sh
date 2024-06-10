#!/usr/bin/env nix-shell
#!nix-shell -p nix -p coreutils -p bash -p gh -i bash
# shellcheck shell=bash
set -xeuo pipefail
shopt -s lastpipe

build_netboot_image() {
  declare -r tag=$1 channel=$2 arch=$3 tmp=$4
  img=$(nix build --print-out-paths --option accept-flake-config true -L ".#packages.${arch}.netboot-nixos-${channel//./}")
  kernel=$(echo "$img"/*Image)
  kernelName=$(basename "$kernel")
  ln -s "$kernel" "$tmp/$kernelName-$arch"
  echo "$tmp/$kernelName-$arch"
  ln -s "$img/initrd" "$tmp/initrd-$arch"
  echo "$tmp/initrd-$arch"
  sed -e "s!^kernel $kernelName!kernel https://github.com/nix-community/nixos-images/releases/download/${tag}/$kernelName-${arch}!" \
    -e "s!^initrd initrd!initrd https://github.com/nix-community/nixos-images/releases/download/${tag}/initrd-${arch}!" \
    -e "s!initrd=initrd!initrd=initrd-${arch}!" \
    <"$img/netboot.ipxe" \
    >"$tmp/netboot-$arch.ipxe"
  echo "$tmp/netboot-$arch.ipxe"
}

build_kexec_installer() {
  declare -r channel=$1 arch=$2 tmp=$3 variant=$4
  out=$(nix build --print-out-paths --option accept-flake-config true -L ".#packages.${arch}.kexec-installer-nixos-${channel}${variant}")
  echo "$out/nixos-kexec-installer${variant}-$arch.tar.gz"
}

build_image_installer() {
  declare -r channel=$1 arch=$2 tmp=$3
  out=$(nix build --print-out-paths --option accept-flake-config true -L ".#packages.${arch}.image-installer-nixos-${channel//./}")
  echo "$out/iso/nixos-installer-${arch}.iso"
}

main() {
  declare -r tag=${1:-nixos-unstable} arch=${2:-x86_64-linux}
  tmp="$(mktemp -d)"
  trap 'rm -rf -- "$tmp"' EXIT
  (
    channel=$(if [[ "$tag" == nixos-unstable ]]; then echo "unstable"; else echo "stable"; fi)
    build_kexec_installer "$channel" "$arch" "$tmp" ""
    build_kexec_installer "$channel" "$arch" "$tmp" "-noninteractive"
    build_netboot_image "$tag" "$channel" "$arch" "$tmp"
    build_image_installer "$channel" "$arch" "$tmp"
  ) | readarray -t assets
  for asset in "${assets[@]}"; do
    pushd "$(dirname "$asset")"
    popd
  done

  if ! gh release view "$tag"; then
    gh release create --title "$tag (build $(date +"%Y-%m-%d"))" "$tag"
  fi
  gh release upload --clobber "$tag" "${assets[@]}"
}

main "$@"
