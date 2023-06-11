# This module optimizes for non-interactive deployments by remove some store paths
# which are primarily useful for interactive installations.

{ config, lib, pkgs, ... }: {
  disabledModules = [
    # This module adds values to multiple lists (systemPackages, supportedFilesystems)
    # which are impossible/unpractical to remove, so we disable the entire module.
    "profiles/base.nix"
  ];

  # among others, this prevents carrying a stdenv with gcc in the image
  system.extraDependencies = lib.mkForce [ ];

  # prevents shipping nixpkgs, unnecessary if system is evaluated externally
  nix.registry = lib.mkForce { };

  # would pull in nano
  programs.nano.syntaxHighlight = lib.mkForce false;

  # prevents nano, strace
  environment.defaultPackages = lib.mkForce [
    pkgs.rsync
    pkgs.parted
    (pkgs.zfs.override {
      # this overrides saves 10MB
      samba = pkgs.coreutils;
    })
  ];

  # we are missing this from base.nix
  boot.supportedFilesystems = [
    "btrfs"
    # probably not needed but does not seem to increase closure size
    "cifs"
    "f2fs"
    ## anyone still using this over ext4?
    #"jfs"
    "ntfs"
    ## no longer seems to be maintained, anyone still using it?
    #"reiserfs"
    "vfat"
    "xfs"
  ];
  boot = {
    kernelModules = [ "zfs" ];
    extraModulePackages = [
      config.boot.kernelPackages.zfs
    ];
  };

  networking.hostId = lib.mkDefault "8425e349";

  # we can drop this after 23.05 has been released, which has this set by default
  hardware.enableRedistributableFirmware = lib.mkForce false;
}
