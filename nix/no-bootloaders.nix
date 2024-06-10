{ lib, ... }: {
  # HACK: Drop this, once we have 24.11 everywhere
  nixpkgs.overlays = lib.optionals (lib.versionOlder lib.version "24.11pre") [
    # Both syslinux and grub also reference perl
    (final: prev: {
      # we don't need grub: save ~ 60MB
      grub2 = prev.coreutils;
      grub2_efi = prev.coreutils;
      syslinux = prev.coreutils;
    })
  ];
}
