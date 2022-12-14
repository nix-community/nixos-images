{
  description = "NixOS images";

  outputs = { self }: {
    nixosModules.kexec-installer = ./nix/kexec-installer/module.nix;
  };
}
