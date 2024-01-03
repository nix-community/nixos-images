{ config, lib, pkgs, ... }:
# incorperate a space-optimized version of zfs
let
  zfs = pkgs.zfs.override {
    # this overrides saves 10MB
    samba = pkgs.coreutils;
  };
in
{
  services.udev.packages = [ zfs ]; # to hook zvol naming, etc.
  # unsure if need this, but in future udev rules could potentially point to systemd services.
  systemd.packages = [ zfs ];
  environment.defaultPackages = lib.mkForce [ zfs ]; # this merges with outer noninteractive module.

  boot.kernelModules = [ "zfs" ];
  boot.extraModulePackages = [
    (config.boot.kernelPackages.zfs.override {
      inherit (config.boot.zfs) removeLinuxDRM;
    })
  ];

  boot.kernelPatches = lib.optional (config.boot.zfs.removeLinuxDRM && pkgs.stdenv.hostPlatform.system == "aarch64-linux") {
    name = "export-neon-symbols-as-gpl";
    patch = pkgs.fetchpatch {
      url = "https://github.com/torvalds/linux/commit/aaeca98456431a8d9382ecf48ac4843e252c07b3.patch";
      hash = "sha256-L2g4G1tlWPIi/QRckMuHDcdWBcKpObSWSRTvbHRIwIk=";
      revert = true;
    };
  };

  networking.hostId = lib.mkDefault "8425e349";
}
