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
  system.stateVersion = config.system.nixos.version;

  # Enable bcachefs support
  boot.supportedFilesystems.bcachefs = lib.mkDefault true;

  # use latest kernel we can support to get more hardware support
  boot.zfs.package = pkgs.zfsUnstable;

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
    (pkgs.callPackage ./nixos-facter.nix {})

    pkgs.disko
  ];

  # Don't add nixpkgs to the image to save space, for our intended use case we don't need it
  system.installer.channel.enable = false;
}
