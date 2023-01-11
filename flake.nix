{
  description = "NixOS images";

  inputs.nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable-small";
  inputs.nixos-2211.url = "github:NixOS/nixpkgs/release-22.11";

  nixConfig.extra-substituters = [
    "https://cache.garnix.io"
  ];
  nixConfig.extra-trusted-public-keys = [
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
  ];

  outputs = { self, nixos-unstable, nixos-2211 }: let
    supportedSystems = [ "aarch64-linux" "x86_64-linux" ];
    forAllSystems = nixos-unstable.lib.genAttrs supportedSystems;
  in {
    packages = forAllSystems (system: let
      netboot = nixpkgs: (import (nixpkgs + "/nixos/release.nix") {}).netboot.${system};
      kexec-installer = nixpkgs: (nixpkgs.legacyPackages.${system}.nixos [self.nixosModules.kexec-installer]).config.system.build.kexecTarball;
    in {
      netboot-nixos-unstable = netboot nixos-unstable;
      netboot-nixos-2211 = netboot nixos-2211;
      kexec-installer-nixos-unstable = kexec-installer nixos-unstable;
      kexec-installer-nixos-2211 = kexec-installer nixos-2211;
    });
    nixosModules.kexec-installer = import ./nix/kexec-installer/module.nix;
    checks.x86_64-linux = {
      kexec-installer-unstable = nixos-unstable.legacyPackages.x86_64-linux.callPackage ./nix/kexec-installer/test.nix {};
      kexec-installer-2211 = nixos-2211.legacyPackages.x86_64-linux.callPackage ./nix/kexec-installer/test.nix {};
    };
  };
}
