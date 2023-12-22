{
  description = "NixOS images";

  inputs.nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable-small";
  inputs.nixos-2311.url = "github:NixOS/nixpkgs/release-23.11";

  nixConfig.extra-substituters = [ "https://nix-community.cachix.org" ];
  nixConfig.extra-trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];

  outputs = { self, nixos-unstable, nixos-2311 }:
    let
      supportedSystems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixos-unstable.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          netboot = nixpkgs: (import (nixpkgs + "/nixos/release.nix") { }).netboot.${system};
          kexec-installer = nixpkgs: modules: (nixpkgs.legacyPackages.${system}.nixos (modules ++ [ self.nixosModules.kexec-installer ])).config.system.build.kexecTarball;
          netboot-installer = nixpkgs: (nixpkgs.legacyPackages.${system}.nixos [ self.nixosModules.netboot-installer ]).config.system.build.netboot;
        in
        {
          netboot-nixos-unstable = netboot nixos-unstable;
          netboot-nixos-2311 = netboot nixos-2311;
          kexec-installer-nixos-unstable = kexec-installer nixos-unstable [ ];
          kexec-installer-nixos-2311 = kexec-installer nixos-2311 [ ];

          kexec-installer-nixos-unstable-noninteractive = kexec-installer nixos-unstable [
            {
              system.kexec-installer.name = "nixos-kexec-installer-noninteractive";
            }
            self.nixosModules.noninteractive
          ];
          kexec-installer-nixos-2311-noninteractive = kexec-installer nixos-2311 [
            {
              system.kexec-installer.name = "nixos-kexec-installer-noninteractive";
            }
            self.nixosModules.noninteractive
          ];

          netboot-installer-nixos-unstable = netboot-installer nixos-unstable;
          netboot-installer-nixos-2311 = netboot-installer nixos-2311;
        });
      nixosModules = {
        kexec-installer = ./nix/kexec-installer/module.nix;
        noninteractive = ./nix/noninteractive.nix;
        # TODO: also add a test here once we have https://github.com/NixOS/nixpkgs/pull/228346 merged
        netboot-installer = ./nix/netboot-installer/module.nix;
      };
      checks =
        let
          # re-export the packages as checks
          packages = forAllSystems (system: nixos-unstable.lib.mapAttrs' (n: nixos-unstable.lib.nameValuePair "package-${n}") self.packages.${system});
          checks =
            let
              pkgs = nixos-unstable.legacyPackages.x86_64-linux;
            in
            {
              kexec-installer-unstable = pkgs.callPackage ./nix/kexec-installer/test.nix {
                kexecTarball = self.packages.x86_64-linux.kexec-installer-nixos-unstable-noninteractive;
              };
              shellcheck = pkgs.runCommand "shellcheck"
                {
                  nativeBuildInputs = [ pkgs.shellcheck ];
                } ''
                shellcheck ${(pkgs.nixos [self.nixosModules.kexec-installer]).config.system.build.kexecRun}
                touch $out
              '';
              kexec-installer-2311 = nixos-2311.legacyPackages.x86_64-linux.callPackage ./nix/kexec-installer/test.nix {
                kexecTarball = self.packages.x86_64-linux.kexec-installer-nixos-2311-noninteractive;
              };
            };
        in
        nixos-unstable.lib.recursiveUpdate packages { x86_64-linux = checks; };
    };
}
