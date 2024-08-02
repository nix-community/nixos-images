# This module optimizes for non-interactive deployments by remove some store paths
# which are primarily useful for interactive installations.

{ lib, pkgs, modulesPath, ... }:
{
  disabledModules = [
    # This module adds values to multiple lists (systemPackages, supportedFilesystems)
    # which are impossible/unpractical to remove, so we disable the entire module.
    "profiles/base.nix"
  ];

  imports = [
    ./zfs-minimal.nix
    ./no-bootloaders.nix
    # reduce closure size by removing perl
    "${modulesPath}/profiles/perlless.nix"
    # FIXME: we still are left with nixos-generate-config due to nixos-install-tools
    { system.forbiddenDependenciesRegexes = lib.mkForce []; }
  ];

  # among others, this prevents carrying a stdenv with gcc in the image
  system.extraDependencies = lib.mkForce [ ];

  # prevents shipping nixpkgs, unnecessary if system is evaluated externally
  nix.registry = lib.mkForce { };

  # would pull in nano
  programs.nano.enable = false;

  # prevents strace
  environment.defaultPackages = lib.mkForce [ pkgs.rsync pkgs.parted pkgs.gptfdisk ];

  # normal users are not allowed with sys-users
  # see https://github.com/NixOS/nixpkgs/pull/328926
  users.users.nixos = {
    isSystemUser = true;
    isNormalUser = lib.mkForce false;
  };
  users.users.nixos.group = "nixos";
  users.groups.nixos = {};

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
  boot.kernelModules = [
    # we have to explicitly enable this, otherwise it is not loaded even when creating a raid:
    # https://github.com/nix-community/nixos-anywhere/issues/249
    "dm-raid"
  ];
}
