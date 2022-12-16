{
  description = "NixOS images";

  inputs.nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable-small";
  inputs.nixos-2211.url = "github:NixOS/nixpkgs/release-21.11";

  nixConfig.extra-substituters = [
    "https://cache.garnix.io"
  ];
  nixConfig.extra-trusted-public-keys = [
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
  ];

  outputs = { self, nixos-unstable, nixos-2211 }: {
    packages.x86_64-linux = let
      netboot = nixpkgs: (import (nixpkgs + "/nixos/release.nix") {}).netboot.x86_64-linux;
    in {
      netboot-unstable = netboot nixos-unstable;
      netboot-2211 = netboot nixos-2211;
    };
    nixosModules.kexec-installer = import ./nix/kexec-installer/module.nix;
    checks.x86_64-linux = {
      kexec-installer-unstable = nixos-unstable.legacyPackages.x86_64-linux.callPackage ./nix/kexec-installer/test.nix {};
      # networkd fails to set ipv6 gateway in 2211
      #kexec-installer-2211 = nixos-2211.legacyPackages.x86_64-linux.callPackage ./nix/kexec-installer/test.nix {};
    };
  };
}
