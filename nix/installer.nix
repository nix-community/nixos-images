{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  # can be dropped after 23.11 is removed
  hasPerlless = builtins.pathExists "${modulesPath}/profiles/perlless.nix";
in
{
  # more descriptive hostname than just "nixos"
  networking.hostName = lib.mkDefault "nixos-installer";

  # We are stateless, so just default to latest.
  system.stateVersion = config.system.nixos.version;

  # use latest kernel we can support to get more hardware support
  boot.kernelPackages =
    lib.mkDefault
      (pkgs.zfs.override { removeLinuxDRM = pkgs.hostPlatform.isAarch64; }).latestCompatibleLinuxPackages;
  boot.zfs.removeLinuxDRM = lib.mkDefault pkgs.hostPlatform.isAarch64;

  documentation.enable = false;
  documentation.man.man-db.enable = false;

  environment.systemPackages = [
    pkgs.nixos-install-tools
    # for zapping of disko
    pkgs.jq
    # for copying extra files of nixos-anywhere
    pkgs.rsync
  ];

  imports = [
    ./nix-settings.nix
    # reduce closure size by removing perl
  ] ++ lib.optionals hasPerlless [
    "${modulesPath}/profiles/perlless.nix"
    # FIXME: we still are left with nixos-generate-config due to nixos-install-tools
    { system.forbiddenDependenciesRegexes = lib.mkForce []; }
  ];

  # Don't add nixpkgs to the image to save space, for our intended use case we don't need it
  system.installer.channel.enable = false;
}
