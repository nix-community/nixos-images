{lib, ...}:{
  # when grub ends up being bloat: kexec & netboot
  nixpkgs.overlays = [
    (final: prev: {
      # we don't need grub: save ~ 60MB
      grub2 = prev.coreutils;
      grub2_efi = prev.coreutils;
    })
  ];
}
