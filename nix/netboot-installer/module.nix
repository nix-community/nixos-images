{ config, lib, modulesPath, pkgs, ... }:
{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
  ];

  # We are stateless, so just default to latest.
  system.stateVersion = config.system.nixos.version;

  system.build.netboot = pkgs.symlinkJoin {
    name = "netboot";
    paths = with config.system.build; [
      netbootRamdisk
      kernel
      (pkgs.runCommand "kernel-params" {} ''
        mkdir -p $out
        ln -s "${config.system.build.toplevel}/kernel-params" $out/kernel-params
        ln -s "${config.system.build.toplevel}/init" $out/init
      '')
    ];
    preferLocalBuild = true;
  };

  # IPMI SOL console redirection stuff
  boot.kernelParams =
    [ "console=tty0" ] ++
    (lib.optional (pkgs.stdenv.hostPlatform.isAarch32 || pkgs.stdenv.hostPlatform.isAarch64) "console=ttyAMA0,115200") ++
    (lib.optional (pkgs.stdenv.hostPlatform.isRiscV) "console=ttySIF0,115200") ++
    [ "console=ttyS0,115200" ];

  documentation.enable = false;
  # Not really needed. Saves a few bytes and the only service we are running is sshd, which we want to be reachable.
  networking.firewall.enable = false;

  systemd.network.enable = true;
  networking.dhcpcd.enable = false;

  systemd.network.networks."10-uplink" = {
    matchConfig.Type = "ether";
    networkConfig = {
      DHCP = "yes";
      LLMNR = "yes";
      EmitLLDP = "yes";
      IPv6AcceptRA = "no";
      MulticastDNS = "yes";
      LinkLocalAddressing = "yes";
      LLDP = "yes";
    };

    dhcpV4Config = {
      UseHostname = false;
      ClientIdentifier = "mac";
    };
  };

  # for zapping of disko
  environment.systemPackages = [
    pkgs.jq
  ];

  systemd.services.log-network-status = {
    wantedBy = [ "multi-user.target" ];
    # No point in restarting this. We just need this after boot
    restartIfChanged = false;

    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
      ExecStart = [
        # Allow failures, so it still prints what interfaces we have even if we
        # not get online
        "-${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online"
        "${pkgs.iproute2}/bin/ip -c addr"
        "${pkgs.iproute2}/bin/ip -c -6 route"
        "${pkgs.iproute2}/bin/ip -c -4 route"
      ];
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

  boot.initrd.postMountCommands = ''
    # add user keys if they are available.
    mkdir -m 700 -p /mnt-root/root/.ssh
    mkdir -m 755 -p /mnt-root/etc/ssh
    mkdir -m 755 -p /mnt-root/root/network
    if [[ -f ssh/authorized_keys ]]; then
      install -m 400 ssh/authorized_keys /mnt-root/root/.ssh
    fi
  '';
}
