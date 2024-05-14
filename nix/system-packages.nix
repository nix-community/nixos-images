{pkgs, ... }: let
  # not availabe on not-os, so we extract it
  # out of a stipulated system evaluation
  cfg = (pkgs.nixos {}).config;
in {
  environment.systemPackages = [
    # for zapping of disko
    pkgs.jq
    # for copying extra files of nixos-anywhere
    pkgs.rsync
    # for installing nixos via nixos-anywhere
    cfg.system.build.nixos-enter
    cfg.system.build.nixos-install
  ];
}
