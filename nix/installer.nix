{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./latest-zfs-kernel.nix
    ./nix-settings.nix
  ];
  # more descriptive hostname than just "nixos"
  networking.hostName = lib.mkDefault "nixos-installer";

  # We are stateless, so just default to latest.
  system.stateVersion = config.system.nixos.release;

  # Enable bcachefs support
  boot.supportedFilesystems.bcachefs = lib.mkDefault true;

  # use latest kernel we can support to get more hardware support
  boot.zfs.package = pkgs.zfs_unstable;

  documentation.enable = false;
  documentation.man.man-db.enable = false;

  # make it easier to debug boot failures
  boot.initrd.systemd.emergencyAccess = true;

  environment.systemPackages = [
    pkgs.nixos-install-tools
    # for zapping of disko
    pkgs.jq
    # for copying extra files of nixos-anywhere
    pkgs.rsync
    # alternative to nixos-generate-config
    # TODO: use nixpkgs again after next nixos release
    pkgs.nixos-facter

    pkgs.disko
  ];

  # enable zswap to help with low memory systems
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.max_pool_percent=50"
    "zswap.compressor=zstd"
    # recommended for systems with little memory
    "zswap.zpool=zsmalloc"
  ];

  # Don't add nixpkgs to the image to save space, for our intended use case we don't need it
  system.installer.channel.enable = false;
}
