{ config, lib, modulesPath, pkgs, ... }:
let
  restore-network = pkgs.writers.writePython3Bin "restore-network" { flakeIgnore = [ "E501" ]; }
    ./restore_routes.py;

  # does not link with iptables enabled
  iprouteStatic = pkgs.pkgsStatic.iproute2.override { iptables = null; };
in
{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
    ../installer.nix
    ../networkd.nix
    ../serial.nix
    ../restore-remote-access.nix
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
    # This is a variant of the upstream kexecScript that also allows embedding
    # a ssh key.
    system.build.kexecRun = pkgs.runCommand "kexec-run" { } ''
      install -D -m 0755 ${./kexec-run.sh} $out

      sed -i \
        -e 's|@init@|${config.system.build.toplevel}/init|' \
        -e 's|@kernelParams@|${lib.escapeShellArgs config.boot.kernelParams}|' \
        $out

      ${pkgs.shellcheck}/bin/shellcheck $out
    '';

    system.build.kexecTarball = pkgs.runCommand "kexec-tarball" { } ''
      mkdir kexec $out
      cp "${config.system.build.netbootRamdisk}/initrd" kexec/initrd
      cp "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}" kexec/bzImage
      cp "${config.system.build.kexecRun}" kexec/run
      cp "${pkgs.pkgsStatic.kexec-tools}/bin/kexec" kexec/kexec
      cp "${iprouteStatic}/bin/ip" kexec/ip
      ${lib.optionalString (pkgs.hostPlatform == pkgs.buildPlatform) ''
        kexec/ip -V
        kexec/kexec --version
      ''}
      tar -czvf $out/${config.system.kexec-installer.name}-${pkgs.stdenv.hostPlatform.system}.tar.gz kexec
    '';

    # for detection if we are on kexec
    environment.etc.is_kexec.text = "true";

    systemd.services.restore-network = {
      before = [ "network-pre.target" ];
      wants = [ "network-pre.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = [
          "${restore-network}/bin/restore-network /root/network/addrs.json /root/network/routes-v4.json /root/network/routes-v6.json /etc/systemd/network"
        ];
      };

      unitConfig.ConditionPathExists = [
        "/root/network/addrs.json"
        "/root/network/routes-v4.json"
        "/root/network/routes-v6.json"
      ];
    };
  };
}
