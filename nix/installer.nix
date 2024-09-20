{
  config,
  lib,
  pkgs,
  ...
}:
let
  latestZfsCompatibleLinuxPackages = lib.pipe pkgs.linuxKernel.packages [
    builtins.attrValues
    (builtins.filter (kPkgs: (builtins.tryEval kPkgs).success && kPkgs ? kernel && kPkgs.kernel.pname == "linux" && !kPkgs.zfs.meta.broken))
    (builtins.sort (a: b: (lib.versionOlder a.kernel.version b.kernel.version)))
    lib.last
  ];
in
{
  # more descriptive hostname than just "nixos"
  networking.hostName = lib.mkDefault "nixos-installer";

  # We are stateless, so just default to latest.
  system.stateVersion = config.system.nixos.version;

  # Enable bcachefs support
  boot.supportedFilesystems.bcachefs = lib.mkDefault true;

  # use latest kernel we can support to get more hardware support
  boot.zfs.package = pkgs.zfsUnstable;
  boot.kernelPackages = latestZfsCompatibleLinuxPackages;

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
  ] ++ lib.optional (pkgs.lib.versionAtLeast lib.version "24.11") pkgs.nixos-facter;

  imports = [
    ./nix-settings.nix
  ];

  # Don't add nixpkgs to the image to save space, for our intended use case we don't need it
  system.installer.channel.enable = false;
}
