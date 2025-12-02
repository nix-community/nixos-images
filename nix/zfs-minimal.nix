{ config, lib, pkgs, ... }:
# incorperate a space-optimized version of zfs
let
  zfs = pkgs.zfs_unstable.override {
    # this overrides saves 10MB
    samba = pkgs.coreutils;

    python3 = pkgs.python3Minimal;
  };
in
{
  services.udev.packages = [ zfs ]; # to hook zvol naming, etc.
  # unsure if need this, but in future udev rules could potentially point to systemd services.
  systemd.packages = [ zfs ];
  environment.defaultPackages = lib.mkForce [ zfs ]; # this merges with outer noninteractive module.

  boot.kernelModules = [ "zfs" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.zfs_unstable ];

  networking.hostId = lib.mkDefault "8425e349";
}
