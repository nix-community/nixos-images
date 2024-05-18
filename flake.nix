{
  description = "NixOS images";

  inputs.nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable-small";
  inputs.nixos-2311.url = "github:NixOS/nixpkgs/release-23.11";

  inputs.not-os = {
    url = "/home/blaggacao/src/github.com/cleverca22/not-os?ref=ref/pulls/34/head";
    flake = false;
  };
  nixConfig.extra-substituters = [ "https://numtide.cachix.org" ];
  nixConfig.extra-trusted-public-keys = [ "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE=" ];

  outputs = { self, nixos-unstable, nixos-2311, not-os }:
    let
      supportedSystems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixos-unstable.lib.genAttrs supportedSystems;
      not-os-eval = nixpkgs: extraModules: import (not-os + /eval-config.nix) {
        inherit nixpkgs extraModules;
      };
    in
    {
      packages = forAllSystems (system:
        let
          netboot = nixpkgs: (import (nixpkgs + "/nixos/release.nix") { }).netboot.${system};
          kexec-installer = nixpkgs: modules: (nixpkgs.legacyPackages.${system}.nixos (modules ++ [ self.nixosModules.kexec-installer-nixos ])).config.system.build.kexecTarball;
          kexec-not-os-installer = nixpkgs: extraModules: ((not-os-eval nixpkgs extraModules).evalModules ({ modules = [self.nixosModules.kexec-installer-not-os];})).config.system.build.kexecTarball;
          netboot-installer = nixpkgs: (nixpkgs.legacyPackages.${system}.nixos [ self.nixosModules.netboot-installer ]).config.system.build.netboot;
          image-installer = nixpkgs: (nixpkgs.legacyPackages.${system}.nixos [ self.nixosModules.image-installer ]).config.system.build.isoImage;
        in
        {
          netboot-nixos-unstable = netboot nixos-unstable;
          netboot-nixos-2311 = netboot nixos-2311;
          kexec-installer-nixos-unstable = kexec-installer nixos-unstable [ ];
          kexec-installer-nixos-2311 = kexec-installer nixos-2311 [ ];

          image-installer-nixos-unstable = image-installer nixos-unstable;
          image-installer-nixos-2311 = image-installer nixos-2311;

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

          kexec-installer-not-os-2311 = kexec-not-os-installer nixos-2311 [
            {nixpkgs = {inherit system;};}
          ];

          netboot-installer-nixos-unstable = netboot-installer nixos-unstable;
          netboot-installer-nixos-2311 = netboot-installer nixos-2311;
        });
      nixosModules = rec {
        kexec-installer-nixos = ./nix/kexec-installer/nixos.nix;
        kexec-installer = kexec-installer-nixos; # back compat
        kexec-installer-not-os = ./nix/kexec-installer/not-os.nix;
        noninteractive = ./nix/noninteractive.nix;
        # TODO: also add a test here once we have https://github.com/NixOS/nixpkgs/pull/228346 merged
        netboot-installer = ./nix/netboot-installer/module.nix;
        image-installer = ./nix/image-installer/module.nix;
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
              kexec-installer-not-os-2311 = nixos-2311.legacyPackages.x86_64-linux.callPackage ./nix/kexec-installer/not-os-test.nix {
                kexecTarball = self.packages.x86_64-linux.kexec-installer-not-os-2311;
                imports = [
                  (not-os + /tests/test-instrumentation.nix)                  
                ];
              };
            };
        in
        nixos-unstable.lib.recursiveUpdate packages { x86_64-linux = checks; };
    };
}
