{ config, lib, modulesPath, pkgs, ... }:
{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
    ../installer.nix
    ../networkd.nix
    ../serial.nix
    ../restore-remote-access.nix
    ../no-grub.nix
  ];

  # We are stateless, so just default to latest.
  system.stateVersion = config.system.nixos.version;

  system.build.netboot = pkgs.symlinkJoin {
    name = "netboot";
    paths = with config.system.build; [
      netbootRamdisk
      kernel
      (pkgs.runCommand "kernel-params" { } ''
        mkdir -p $out
        ln -s "${config.system.build.toplevel}/kernel-params" $out/kernel-params
        ln -s "${config.system.build.toplevel}/init" $out/init
      '')
    ];
    preferLocalBuild = true;
  };
  systemd.network.networks."10-uplink" = {
    matchConfig.Type = "ether";
    networkConfig = {
      DHCP = "yes";
      EmitLLDP = "yes";
      IPv6AcceptRA = "yes";
      MulticastDNS = "yes";
      LinkLocalAddressing = "yes";
      LLDP = "yes";
    };

    dhcpV4Config = {
      UseHostname = false;
      ClientIdentifier = "mac";
    };
  };

  networking.hostName = "";
  # overrides normal activation script for setting hostname
  system.activationScripts.hostname = lib.mkForce ''
    # apply hostname from cmdline
    for o in $(< /proc/cmdline); do
      case $o in
        hostname=*)
          IFS== read -r -a hostParam <<< "$o"
          ;;
      esac
    done
    hostname "''${hostParam[1]:-nixos}"
  '';
}
