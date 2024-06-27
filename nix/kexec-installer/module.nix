{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:
let
  restore-network = pkgs.writers.writePython3 "restore-network" {
    flakeIgnore = [ "E501" ];
  } ./restore_routes.py;

  # does not link with iptables enabled
  iprouteStatic = pkgs.pkgsStatic.iproute2.override { iptables = null; };

  kexec-tools = pkgs.pkgsStatic.kexec-tools.overrideAttrs (old: {
    patches = old.patches ++ [
      (pkgs.fetchpatch {
        url = "https://marc.info/?l=kexec&m=166636009110699&q=mbox";
        hash = "sha256-wi0/Ajy/Ac+7npKEvDsMzgNhEWhOMFeoUWcpgGrmVDc=";
      })
    ];

    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
      pkgs.pkgsStatic.buildPackages.autoreconfHook
    ];
    meta = old.meta // {
      badPlatforms = [ ]; # allow riscv64
    };
  });
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
    system.build.kexecRun =
      pkgs.runCommand "kexec-run" { nativeBuildInputs = [ pkgs.buildPackages.shellcheck ]; }
        ''
          install -D -m 0755 ${./kexec-run.sh} $out

          sed -i \
            -e 's|@init@|${config.system.build.toplevel}/init|' \
            -e 's|@kernelParams@|${lib.escapeShellArgs config.boot.kernelParams}|' \
            $out

          shellcheck $out
        '';

    system.build.kexecTarball = pkgs.runCommand "kexec-tarball" { } ''
      mkdir kexec $out
      cp "${config.system.build.netbootRamdisk}/initrd" kexec/initrd
      cp "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}" kexec/bzImage
      cp "${config.system.build.kexecRun}" kexec/run
      cp "${kexec-tools}/bin/kexec" kexec/kexec
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
          "${restore-network} /root/network/addrs.json /root/network/routes-v4.json /root/network/routes-v6.json /etc/systemd/network"
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
