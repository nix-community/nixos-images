{ config, lib, pkgs, ... }: {
  # We are stateless, so just default to latest.
  system.stateVersion = config.system.nixos.version;

  # use latest kernel we can support to get more hardware support
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  # IPMI SOL console redirection stuff
  boot.kernelParams =
    [ "console=tty0" ] ++
    (lib.optional (pkgs.stdenv.hostPlatform.isAarch32 || pkgs.stdenv.hostPlatform.isAarch64) "console=ttyAMA0,115200") ++
    (lib.optional (pkgs.stdenv.hostPlatform.isRiscV) "console=ttySIF0,115200") ++
    [ "console=ttyS0,115200" ];

  documentation.enable = false;
  # Not really needed. Saves a few bytes and the only service we are running is sshd, which we want to be reachable.
  networking.firewall.enable = false;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.dhcpcd.enable = false;

  # for zapping of disko
  environment.systemPackages = [ pkgs.jq ];

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
        "${pkgs.systemd}/bin/networkctl status"
      ];
    };
  };

  # Restore ssh host and user keys if they are available.
  # This avoids warnings of unknown ssh keys.
  boot.initrd.postMountCommands = ''
    mkdir -m 700 -p /mnt-root/root/.ssh
    mkdir -m 755 -p /mnt-root/etc/ssh
    mkdir -m 755 -p /mnt-root/root/network
    if [[ -f ssh/authorized_keys ]]; then
      install -m 400 ssh/authorized_keys /mnt-root/root/.ssh
    fi
    install -m 400 ssh/ssh_host_* /mnt-root/etc/ssh
    cp *.json /mnt-root/root/network/
  '';
}
