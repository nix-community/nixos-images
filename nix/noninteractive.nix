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
    pkgs.gptfdisk
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
    kernelModules = [
      "zfs"
      # we have to explicitly enable this, otherwise it is not loaded even when creating a raid:
      # https://github.com/nix-community/nixos-anywhere/issues/249
      "dm-raid"
    ];
    extraModulePackages = [
      config.boot.kernelPackages.zfs
    ];
  };

  networking.hostId = lib.mkDefault "8425e349";
}
