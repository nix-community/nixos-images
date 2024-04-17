{ config, lib, pkgs, ... }: {
  # more descriptive hostname than just "nixos"
  networking.hostName = lib.mkDefault "nixos-installer";

  # We are stateless, so just default to latest.
  system.stateVersion = config.system.nixos.version;

  # use latest kernel we can support to get more hardware support
  boot.kernelPackages = lib.mkDefault (pkgs.zfs.override {
    removeLinuxDRM = pkgs.hostPlatform.isAarch64;
  }).latestCompatibleLinuxPackages;
  boot.zfs.removeLinuxDRM = lib.mkDefault pkgs.hostPlatform.isAarch64;

  documentation.enable = false;

  environment.systemPackages = [
    # for zapping of disko
    pkgs.jq
    # for copying extra files of nixos-anywhere
    pkgs.rsync
  ];

  imports = [
    ./nix-settings.nix
  ];

  # Don't add nixpkgs to the image to save space, for our intended use case we don't need it
  system.installer.channel.enable = false;
}
