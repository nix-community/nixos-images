{
  description = "NixOS images";

  inputs.nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable-small";
  inputs.nixos-2211.url = "github:NixOS/nixpkgs/release-22.11";

  nixConfig.extra-substituters = [
    "https://nix-community.cachix.org"
  ];
  nixConfig.extra-trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
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
    checks.x86_64-linux = let
      pkgs = nixos-unstable.legacyPackages.x86_64-linux;
    in {
      kexec-installer-unstable = pkgs.callPackage ./nix/kexec-installer/test.nix {};
      shellcheck = pkgs.runCommand "shellcheck" {
        nativeBuildInputs = [ pkgs.shellcheck ];
      } ''
        shellcheck ${(pkgs.nixos [self.nixosModules.kexec-installer]).config.system.build.kexecRun}
        touch $out
      '';
      kexec-installer-2211 = nixos-2211.legacyPackages.x86_64-linux.callPackage ./nix/kexec-installer/test.nix {};
    };
  };
}
