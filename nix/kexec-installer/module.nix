{ config, lib, modulesPath, pkgs, ... }:
let
  restore-network = pkgs.writers.writePython3 "restore-network" {
    flakeIgnore = ["E501"];
  } ./restore_routes.py;

  # does not link with iptables enabled
  iprouteStatic = pkgs.pkgsStatic.iproute2.override { iptables = null; };
in {
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
  ];
  options = {
    system.kexec-installer.name = lib.mkOption {
      type = lib.types.str;
      default = "nixos-kexec-installer";
      description = ''
        The variant of the kexec installer to use.
      '';
    };
  };

  config = {
    # We are stateless, so just default to latest.
    system.stateVersion = config.system.nixos.version;

    # This is a variant of the upstream kexecScript that also allows embedding
    # a ssh key.
    system.build.kexecRun = pkgs.runCommand "kexec-run" {} ''
      install -D -m 0755 ${./kexec-run.sh} $out

      sed -i \
        -e 's|@init@|${config.system.build.toplevel}/init|' \
        -e 's|@kernelParams@|${lib.escapeShellArgs config.boot.kernelParams}|' \
        $out

      ${pkgs.shellcheck}/bin/shellcheck $out
    '';

    system.build.kexecTarball = pkgs.runCommand "kexec-tarball" {} ''
      mkdir kexec $out
      cp "${config.system.build.netbootRamdisk}/initrd" kexec/initrd
      cp "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}" kexec/bzImage
      cp "${config.system.build.kexecRun}" kexec/run
      cp "${pkgs.pkgsStatic.kexec-tools}/bin/kexec" kexec/kexec
      cp "${iprouteStatic}/bin/ip" kexec/ip
      tar -czvf $out/${config.system.kexec-installer.name}-${pkgs.stdenv.hostPlatform.system}.tar.gz kexec
    '';

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

    # for detection if we are on kexec
    environment.etc.is_kexec.text = "true";

    # for zapping of disko
    environment.systemPackages = [
      pkgs.jq
    ];

    systemd.services.restore-network = {
      before = [ "network-pre.target" ];
      wants = [ "network-pre.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = [
          "${restore-network} /root/network/addrs.json /root/network/routes-v4.json /root/network/routes-v6.json /etc/systemd/network"
        ];
      };

      unitConfig.ConditionPathExists = [
        "/root/network/addrs.json"
        "/root/network/routes-v4.json"
        "/root/network/routes-v6.json"
      ];
    };

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
  };
}
