{
  # HACK: Drop this once, we have https://github.com/NixOS/nixpkgs/pull/312863 merged

  # Both syslinux and grub also reference perl
  nixpkgs.overlays = [
    (final: prev: {
      # we don't need grub: save ~ 60MB
      grub2 = prev.coreutils;
      grub2_efi = prev.coreutils;
      syslinux = prev.coreutils;
    })
  ];
}
